import SwiftUI

/// Covers the app while it is locked, and in the app switcher while App lock is on. What is underneath stays as
/// it was, so the user returns to the same screen after unlocking.
struct AppLockModifier: ViewModifier {
    @ObservedObject var appLock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    private var covered: Bool {
        appLock.isLocked || (appLock.isEnabled && scenePhase != .active && !appLock.isAuthenticating)
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(covered)
            .overlay {
                if covered {
                    AppLockScreen(appLock: appLock, showUnlock: appLock.isLocked)
                }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .background: appLock.didEnterBackground()
                case .active: appLock.didBecomeActive()
                default: break
                }
            }
            .alert("App Lock Turned Off", isPresented: $appLock.turnedOffNoPasscode) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This iPhone no longer has a passcode, so App Lock was turned off. Set a passcode to turn it on again.")
            }
    }
}

extension View {
    func appLock(_ appLock: AppLock) -> some View {
        modifier(AppLockModifier(appLock: appLock))
    }
}

private struct AppLockScreen: View {
    @ObservedObject var appLock: AppLock
    let showUnlock: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image("SinagLockup")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 72)
                    .accessibilityLabel("Sinag")
                if showUnlock {
                    Image(systemName: "lock.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 24)
                    Text("Sinag is locked")
                        .font(.title2)
                    Button("Unlock") {
                        Task { await appLock.unlock() }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            }
            .padding(32)
        }
        // Open the prompt by itself when the lock screen appears while the app is in front.
        .task(id: scenePhase) {
            if showUnlock && scenePhase == .active && !appLock.isAuthenticating {
                await appLock.unlock()
            }
        }
    }
}
