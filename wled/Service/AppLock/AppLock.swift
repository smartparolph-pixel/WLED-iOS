import Foundation
import LocalAuthentication

/// How long Sinag may stay in the background before App lock asks to unlock again.
enum AppLockTimeout: String, CaseIterable, Identifiable {
    case immediately
    case twoMinutes
    case fiveMinutes

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .immediately: return 0
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        }
    }
}

/// When App lock asks to unlock again. Pure, so it can be unit-tested.
enum AppLockPolicy {
    /// - Parameters:
    ///   - backgroundedAt: When the app went to the background (system uptime), or nil if it has not.
    ///   - now: System uptime now.
    static func shouldLockOnReturn(
        enabled: Bool,
        backgroundedAt: TimeInterval?,
        now: TimeInterval,
        timeout: AppLockTimeout
    ) -> Bool {
        guard enabled, let backgroundedAt else { return false }
        return now - backgroundedAt >= timeout.seconds
    }

    /// Settings unlocked at `unlockedAt` stay unlocked until the chosen time has passed ("Immediately": never).
    static func stillUnlocked(unlockedAt: TimeInterval, now: TimeInterval, timeout: AppLockTimeout) -> Bool {
        timeout != .immediately && now - unlockedAt < timeout.seconds
    }
}

/// What App Lock covers.
enum AppLockMode: String, CaseIterable, Identifiable {
    case off
    /// The lights stay free to use; opening or changing settings needs Face ID, Touch ID or the passcode.
    case settingsOnly
    /// Opening the app needs Face ID, Touch ID or the passcode.
    case wholeApp

    var id: String { rawValue }
}

/// App lock: when on, the phone's own Face ID, Touch ID or passcode is needed to open the app, at launch and
/// after `AppLockPolicy` says it was in the background long enough. Nothing is stored but the setting; iOS
/// does the checking and never shares biometric data with the app.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    private static let enabledKey = "AppLock.enabled"
    private static let timeoutKey = "AppLock.timeout"
    private static let settingsOnlyKey = "AppLock.settingsOnly"

    @Published private(set) var isLocked: Bool
    /// True while the system unlock prompt is up (it makes the app inactive; that must not cover or relock).
    @Published private(set) var isAuthenticating = false
    /// Set when App lock was turned off because the phone no longer has a passcode.
    @Published var turnedOffNoPasscode = false

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// With `isEnabled`: only settings need the unlock, not opening the app.
    @Published var settingsOnly: Bool {
        didSet { UserDefaults.standard.set(settingsOnly, forKey: Self.settingsOnlyKey) }
    }

    var mode: AppLockMode {
        get { !isEnabled ? .off : settingsOnly ? .settingsOnly : .wholeApp }
        set {
            isEnabled = newValue != .off
            settingsOnly = newValue == .settingsOnly
            if newValue != .wholeApp { isLocked = false }
        }
    }

    /// The whole app is locked when in the background or opened.
    var locksWholeApp: Bool { mode == .wholeApp }

    @Published var timeout: AppLockTimeout {
        didSet { UserDefaults.standard.set(timeout.rawValue, forKey: Self.timeoutKey) }
    }

    private var backgroundedAt: TimeInterval?
    /// When settings were last unlocked (`.settingsOnly`); they stay open for the chosen time.
    private var settingsUnlockedAt: TimeInterval?

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let onlySettings = UserDefaults.standard.bool(forKey: Self.settingsOnlyKey)
        isEnabled = enabled
        settingsOnly = onlySettings
        timeout = AppLockTimeout(rawValue: UserDefaults.standard.string(forKey: Self.timeoutKey) ?? "") ?? .twoMinutes
        isLocked = enabled && !onlySettings
        if enabled && !Self.isAvailable {
            turnOffNoPasscode()
        }
    }

    /// The phone has a passcode (and possibly Face ID or Touch ID), so App lock can be used.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func didEnterBackground() {
        if !isLocked { backgroundedAt = ProcessInfo.processInfo.systemUptime }
    }

    func didBecomeActive() {
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        if AppLockPolicy.shouldLockOnReturn(
            enabled: locksWholeApp, backgroundedAt: since, now: ProcessInfo.processInfo.systemUptime, timeout: timeout
        ) {
            lock()
        }
    }

    /// Shows Face ID, Touch ID or the passcode prompt. - Returns: true when the user confirmed.
    func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// True when opening or changing settings must ask first (`.settingsOnly`, not unlocked recently). If the
    /// passcode was removed, App Lock turns itself off instead (with a notice) and nothing is asked.
    var settingsNeedUnlock: Bool {
        guard mode == .settingsOnly else { return false }
        guard Self.isAvailable else {
            turnOffNoPasscode()
            return false
        }
        guard let since = settingsUnlockedAt else { return true }
        return !AppLockPolicy.stillUnlocked(
            unlockedAt: since, now: ProcessInfo.processInfo.systemUptime, timeout: timeout
        )
    }

    /// Asks for Face ID, Touch ID or the passcode when settings need it. - Returns: true when allowed.
    func requireSettingsUnlock() async -> Bool {
        guard settingsNeedUnlock else { return true }
        let ok = await authenticate(reason: String(localized: "Unlock to change settings"))
        if ok { settingsUnlockedAt = ProcessInfo.processInfo.systemUptime }
        return ok
    }

    func unlock() async {
        if await authenticate(reason: String(localized: "Unlock Sinag")) {
            isLocked = false
        }
    }

    private func lock() {
        if Self.isAvailable {
            isLocked = true
        } else {
            turnOffNoPasscode()
        }
    }

    /// The passcode was removed: turn App lock off rather than lock the user out.
    private func turnOffNoPasscode() {
        settingsOnly = false
        isEnabled = false
        isLocked = false
        turnedOffNoPasscode = true
    }
}
