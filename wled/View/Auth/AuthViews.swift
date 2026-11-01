import SwiftUI

/// Splash → Log in / Sign up → device list. An account is required before the device screens open.
struct AppRootView: View {
    @StateObject private var session = AppSession()

    var body: some View {
        Group {
            switch session.phase {
            case .splash:
                SplashView().task { await session.start() }
            case .signedOut:
                NavigationStack {
                    LoginView(auth: session.auth) { session.didSignIn() }
                }
            case .signedIn:
                DeviceListView()
            }
        }
        .environmentObject(session)
        .environment(\.appSession, session)
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }
}

/// Always dark: reversed lockup and the tagline in Gold Tint on Lantern Navy, centered.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            SinagLockup(reversed: true, width: 260)
            Text("Every celebration, connected.")
                .font(SinagFont.medium(17, relativeTo: .headline))
                .foregroundStyle(SinagColor.goldTint)
                .multilineTextAlignment(.center)
        }
        .padding(SinagMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SinagColor.lanternNavy.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Log in

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @Environment(\.openURL) private var openURL
    @FocusState private var focus: Field?
    private let auth: AuthService
    private let onSignedIn: () -> Void

    private enum Field { case email, password }

    init(auth: AuthService, onSignedIn: @escaping () -> Void) {
        self.auth = auth
        self.onSignedIn = onSignedIn
        _viewModel = StateObject(wrappedValue: LoginViewModel(auth: auth))
    }

    var body: some View {
        AuthScreen {
            VStack(spacing: 12) {
                SinagLockup()
                Text("Every celebration, connected.")
                    .font(SinagFont.regular(16, relativeTo: .body))
                    .foregroundStyle(SinagColor.tagline)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            SinagTextField(
                label: String(localized: "Email"),
                text: $viewModel.email,
                kind: .email,
                error: viewModel.emailError?.message,
                onSubmit: { focus = .password }
            )
            .focused($focus, equals: .email)
            SinagTextField(
                label: String(localized: "Password"),
                text: $viewModel.password,
                kind: .password,
                error: viewModel.passwordError?.message,
                submitLabel: .done,
                onSubmit: submit
            )
            .focused($focus, equals: .password)
            FormMessageView(message: viewModel.message)
            SinagPrimaryButton(title: String(localized: "Log in"), loading: viewModel.loading, action: submit)
                .padding(.top, 4)
            SinagTextLink(title: String(localized: "Forgot password?")) {
                Task { await viewModel.forgotPassword() }
            }
            LabeledDivider(text: String(localized: "New to Sinag?"))
            NavigationLink {
                SignUpView(auth: auth, onSignedIn: onSignedIn)
            } label: {
                Text("Sign up with email")
                    .font(SinagFont.medium(16, relativeTo: .headline))
                    .foregroundStyle(SinagColor.text)
                    .frame(maxWidth: .infinity, minHeight: SinagMetrics.controlHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: SinagMetrics.cornerRadius).stroke(SinagColor.text, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            SinagTextLink(title: String(localized: "Privacy Policy"), underline: true) {
                if let url = SinagLinks.privacyPolicy { openURL(url) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func submit() {
        focus = nil
        Task {
            if await viewModel.submit() { onSignedIn() }
        }
    }
}

// MARK: - Sign up

struct SignUpView: View {
    @StateObject private var viewModel: SignUpViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    private let onSignedIn: () -> Void

    private enum Field { case name, email, password, confirm }

    init(auth: AuthService, onSignedIn: @escaping () -> Void) {
        self.onSignedIn = onSignedIn
        _viewModel = StateObject(wrappedValue: SignUpViewModel(auth: auth))
    }

    var body: some View {
        AuthScreen(topAlignment: .leading) {
            Text("Create your account")
                .font(SinagFont.bold(24, relativeTo: .title2))
                .foregroundStyle(SinagColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Set up your parol in a minute.")
                .font(SinagFont.regular(15, relativeTo: .subheadline))
                .foregroundStyle(SinagColor.muted)
                .padding(.bottom, 12)
            SinagTextField(
                label: String(localized: "Name"), text: $viewModel.name, kind: .name,
                error: viewModel.nameError?.message, onSubmit: { focus = .email }
            )
            .focused($focus, equals: .name)
            SinagTextField(
                label: String(localized: "Email"), text: $viewModel.email, kind: .email,
                error: viewModel.emailError?.message, onSubmit: { focus = .password }
            )
            .focused($focus, equals: .email)
            SinagTextField(
                label: String(localized: "Password"), text: $viewModel.password, kind: .newPassword,
                error: viewModel.passwordError?.message, onSubmit: { focus = .confirm }
            )
            .focused($focus, equals: .password)
            SinagTextField(
                label: String(localized: "Confirm password"), text: $viewModel.confirmPassword, kind: .newPassword,
                error: viewModel.confirmError?.message, submitLabel: .done, onSubmit: submit
            )
            .focused($focus, equals: .confirm)
            FormMessageView(message: viewModel.message)
            SinagPrimaryButton(title: String(localized: "Create account"), loading: viewModel.loading, action: submit)
                .padding(.top, 8)
            agreement
        } bottom: {
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .font(SinagFont.regular(14, relativeTo: .footnote))
                    .foregroundStyle(SinagColor.muted)
                SinagTextLink(title: String(localized: "Log in")) { dismiss() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// "By creating an account, you agree to our Privacy Policy. ..." with the policy as a link.
    private var agreement: some View {
        var text = AttributedString(localized: "By creating an account, you agree to our Privacy Policy. We use your details only to set up your account and run your parols.")
        if let range = text.range(of: String(localized: "Privacy Policy")), let url = SinagLinks.privacyPolicy {
            text[range].link = url
            text[range].underlineStyle = .single
            text[range].foregroundColor = SinagColor.text
        }
        return Text(text)
            .font(SinagFont.regular(13, relativeTo: .footnote))
            .foregroundStyle(SinagColor.muted)
            .tint(SinagColor.text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private func submit() {
        focus = nil
        Task {
            if await viewModel.submit() { onSignedIn() }
        }
    }
}

// MARK: - Shared layout

/// Paper (light) or navy (dark) screen. `top` sits at the top and `bottom` at the bottom when there is
/// room; everything scrolls above the keyboard when there is not.
struct AuthScreen<Top: View, Bottom: View>: View {
    var topAlignment: HorizontalAlignment = .center
    @ViewBuilder let top: Top
    @ViewBuilder let bottom: Bottom

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: topAlignment, spacing: 8) { top }
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: topAlignment, vertical: .center))
                        .padding(.top, 48)
                    Spacer(minLength: 32)
                    VStack(spacing: 8) { bottom }
                }
                .frame(maxWidth: SinagMetrics.maxFormWidth)
                .padding(SinagMetrics.screenPadding)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SinagColor.background.ignoresSafeArea())
    }
}

/// "———— New to Sinag? ————"
struct LabeledDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(SinagColor.fieldBorder).frame(height: 1)
            Text(text)
                .font(SinagFont.regular(13, relativeTo: .footnote))
                .foregroundStyle(SinagColor.muted)
                .fixedSize()
            Rectangle().fill(SinagColor.fieldBorder).frame(height: 1)
        }
    }
}

struct FormMessageView: View {
    let message: FormMessage?

    var body: some View {
        if let message {
            if message.isError {
                SinagFieldError(message: message.text).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(message.text)
                    .font(SinagFont.regular(13, relativeTo: .footnote))
                    .foregroundStyle(SinagColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Previews

#Preview("Splash") {
    SplashView()
}

#Preview("Log in - light") {
    NavigationStack { LoginView(auth: FakeAuthService(store: InMemorySessionStore())) {} }
        .preferredColorScheme(.light)
}

#Preview("Log in - dark") {
    NavigationStack { LoginView(auth: FakeAuthService(store: InMemorySessionStore())) {} }
        .preferredColorScheme(.dark)
}

#Preview("Sign up - light") {
    NavigationStack { SignUpView(auth: FakeAuthService(store: InMemorySessionStore())) {} }
        .preferredColorScheme(.light)
}

#Preview("Sign up - dark") {
    NavigationStack { SignUpView(auth: FakeAuthService(store: InMemorySessionStore())) {} }
        .preferredColorScheme(.dark)
}
