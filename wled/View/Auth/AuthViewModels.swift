import Foundation

/// Which part of the app is showing. An account is required before the device screens open.
@MainActor
final class AppSession: ObservableObject {
    enum Phase: Equatable { case splash, signedOut, signedIn }

    @Published private(set) var phase: Phase = .splash
    let auth: AuthService

    // TODO(auth): replace FakeAuthService with the Supabase implementation once it exists.
    init(auth: AuthService = FakeAuthService(store: KeychainSessionStore())) {
        self.auth = auth
    }

    /// Shows the splash for at least 1.5 s, then routes on whether a session exists.
    func start() async {
        guard phase == .splash else { return }
        let started = ContinuousClock.now
        let session = await auth.currentSession()
        let remaining = Duration.milliseconds(1_500) - (ContinuousClock.now - started)
        if remaining > .zero { try? await Task.sleep(for: remaining) }
        phase = session == nil ? .signedOut : .signedIn
    }

    func didSignIn() { phase = .signedIn }

    func signOut() async {
        await auth.signOut()
        phase = .signedOut
    }
}

/// Message shown above the primary button.
struct FormMessage: Equatable {
    let text: String
    let isError: Bool
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    /// Errors only show after the first submit, then update as the user types.
    @Published private(set) var showErrors = false
    @Published private(set) var loading = false
    @Published private(set) var message: FormMessage?

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    var emailError: FieldError? { showErrors ? AuthValidation.email(email) : nil }
    var passwordError: FieldError? { showErrors ? AuthValidation.required(password) : nil }

    /// - Returns: true when signed in.
    func submit() async -> Bool {
        guard !loading else { return false }
        showErrors = true
        message = nil
        guard emailError == nil, passwordError == nil else { return false }
        loading = true
        defer { loading = false }
        switch await auth.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) {
        case .success:
            password = ""
            return true
        case .failure(let error):
            message = FormMessage(text: error.message, isError: true)
            return false
        }
    }

    func forgotPassword() async {
        guard !loading else { return }
        guard AuthValidation.email(email) == nil else {
            showErrors = true
            message = FormMessage(text: String(localized: "Enter your email above, then tap Forgot password? again."), isError: true)
            return
        }
        loading = true
        defer { loading = false }
        let sent = await auth.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        message = sent
            ? FormMessage(text: String(localized: "If an account exists for that email, we've sent a link to reset your password."), isError: false)
            : FormMessage(text: AuthError.network.message, isError: true)
    }
}

@MainActor
final class SignUpViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published private(set) var showErrors = false
    @Published private(set) var loading = false
    @Published private(set) var message: FormMessage?

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    var nameError: FieldError? { showErrors ? AuthValidation.required(name) : nil }
    var emailError: FieldError? { showErrors ? AuthValidation.email(email) : nil }
    var passwordError: FieldError? { showErrors ? AuthValidation.newPassword(password) : nil }
    /// A mismatch shows as soon as both password fields have text.
    var confirmError: FieldError? {
        if showErrors { return AuthValidation.confirmPassword(password, confirmPassword) }
        return !confirmPassword.isEmpty && confirmPassword != password ? .passwordsDiffer : nil
    }

    /// - Returns: true when the account was created and signed in.
    func submit() async -> Bool {
        guard !loading else { return false }
        showErrors = true
        message = nil
        guard nameError == nil, emailError == nil, passwordError == nil, confirmError == nil else { return false }
        loading = true
        defer { loading = false }
        let result = await auth.signUp(
            name: name,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        switch result {
        case .success:
            password = ""
            confirmPassword = ""
            return true
        case .failure(let error):
            message = FormMessage(text: error.message, isError: true)
            return false
        }
    }
}
