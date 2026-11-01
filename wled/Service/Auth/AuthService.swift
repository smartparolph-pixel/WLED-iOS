import Foundation
import Security

/// A signed-in user. `token` is a secret: never log it.
struct AuthSession: Codable, Equatable, CustomStringConvertible {
    let userId: String
    let email: String
    let name: String?
    let token: String

    var description: String { "AuthSession(userId: \(userId), email: \(email))" }
}

enum AuthError: Error, Equatable {
    case invalidCredentials, emailInUse, network, unknown

    var message: String {
        switch self {
        case .invalidCredentials: return String(localized: "Email or password is incorrect.")
        case .emailInUse: return String(localized: "An account with this email already exists.")
        case .network: return String(localized: "Can't connect. Check your internet connection and try again.")
        case .unknown: return String(localized: "Something went wrong. Please try again.")
        }
    }
}

/// Account operations used by the Sinag screens. The real provider (Supabase) is not wired yet;
/// until then `FakeAuthService` is used (see `AppSession`).
@MainActor
protocol AuthService: AnyObject {
    func login(email: String, password: String) async -> Result<AuthSession, AuthError>
    func signUp(name: String, email: String, password: String) async -> Result<AuthSession, AuthError>
    /// Returns false only when the request could not be sent. Never reveals whether the email exists.
    func requestPasswordReset(email: String) async -> Bool
    func signOut() async
    /// The stored session, or nil when signed out.
    func currentSession() async -> AuthSession?
}

/// Where the session survives app restarts. Implementations must keep the token encrypted at rest.
@MainActor
protocol SessionStore: AnyObject {
    func save(_ session: AuthSession)
    func load() -> AuthSession?
    func clear()
}

/// ⚠️ DEVELOPMENT ONLY. Not a real backend: accounts live in memory and no data leaves the phone.
///
/// Replace with the Supabase implementation before release. Behaviour, so every screen state can be
/// exercised by hand:
/// - Sign up succeeds unless the email was already used in this run (`.emailInUse`).
/// - Log in succeeds for any account created in this run with the same password, and for any email
///   with the password "password123". An email containing "offline" simulates a `.network` error.
/// - Every call waits `latency` so the loading states are visible.
@MainActor
final class FakeAuthService: AuthService {
    static let demoPassword = "password123"
    private static let offlineMarker = "offline"

    private let store: SessionStore
    private let latency: Duration
    private var accounts: [String: (name: String, password: String)] = [:]

    init(store: SessionStore, latency: Duration = .milliseconds(800)) {
        self.store = store
        self.latency = latency
    }

    func login(email: String, password: String) async -> Result<AuthSession, AuthError> {
        try? await Task.sleep(for: latency)
        let key = normalized(email)
        if key.contains(Self.offlineMarker) { return .failure(.network) }
        let account = accounts[key]
        guard account?.password == password || password == Self.demoPassword else {
            return .failure(.invalidCredentials)
        }
        return .success(startSession(email: key, name: account?.name))
    }

    func signUp(name: String, email: String, password: String) async -> Result<AuthSession, AuthError> {
        try? await Task.sleep(for: latency)
        let key = normalized(email)
        if key.contains(Self.offlineMarker) { return .failure(.network) }
        if accounts[key] != nil { return .failure(.emailInUse) }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[key] = (trimmedName, password)
        return .success(startSession(email: key, name: trimmedName))
    }

    func requestPasswordReset(email: String) async -> Bool {
        try? await Task.sleep(for: latency)
        return !normalized(email).contains(Self.offlineMarker)
    }

    func signOut() async {
        store.clear()
    }

    func currentSession() async -> AuthSession? {
        store.load()
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func startSession(email: String, name: String?) -> AuthSession {
        let session = AuthSession(userId: UUID().uuidString, email: email, name: name, token: "fake-\(UUID().uuidString)")
        store.save(session)
        return session
    }
}

/// Keeps the session in the iOS Keychain (encrypted by the system, this device only).
@MainActor
final class KeychainSessionStore: SessionStore {
    private let service: String
    private let account = "session"

    init(service: String = (Bundle.main.bundleIdentifier ?? "sinag") + ".auth") {
        self.service = service
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// In-memory store for tests and previews.
@MainActor
final class InMemorySessionStore: SessionStore {
    private var session: AuthSession?
    func save(_ session: AuthSession) { self.session = session }
    func load() -> AuthSession? { session }
    func clear() { session = nil }
}

/// Field problems shown under the fields.
enum FieldError: Equatable {
    case required, invalidEmail, passwordTooShort, passwordsDiffer

    var message: String {
        switch self {
        case .required: return String(localized: "This field is required")
        case .invalidEmail: return String(localized: "Enter a valid email address")
        case .passwordTooShort: return String(localized: "Use at least 8 characters")
        case .passwordsDiffer: return String(localized: "Passwords don't match")
        }
    }
}

enum AuthValidation {
    static let minPasswordLength = 8

    // Pragmatic format check: something@something.tld, no spaces. The server has the final say.
    private static let emailPattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#

    static func email(_ value: String) -> FieldError? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .required }
        return trimmed.range(of: emailPattern, options: .regularExpression) == nil ? .invalidEmail : nil
    }

    static func newPassword(_ value: String) -> FieldError? {
        if value.isEmpty { return .required }
        return value.count < minPasswordLength ? .passwordTooShort : nil
    }

    static func confirmPassword(_ password: String, _ confirm: String) -> FieldError? {
        if confirm.isEmpty { return .required }
        return confirm == password ? nil : .passwordsDiffer
    }

    static func required(_ value: String) -> FieldError? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .required : nil
    }
}
