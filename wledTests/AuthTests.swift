import Foundation
import Testing
@testable import WLED

struct AuthValidationTests {

    @Test func email() {
        #expect(AuthValidation.email(" ") == .required)
        #expect(AuthValidation.email("juan") == .invalidEmail)
        #expect(AuthValidation.email("juan@parol") == .invalidEmail)
        #expect(AuthValidation.email("juan dela@cruz.ph") == .invalidEmail)
        #expect(AuthValidation.email("juan@sinagtechlabs.com") == nil)
        #expect(AuthValidation.email("  juan@sinag.ph  ") == nil)
    }

    @Test func passwordNeedsEightCharacters() {
        #expect(AuthValidation.newPassword("") == .required)
        #expect(AuthValidation.newPassword("1234567") == .passwordTooShort)
        #expect(AuthValidation.newPassword("12345678") == nil)
    }

    @Test func confirmPasswordMustMatch() {
        #expect(AuthValidation.confirmPassword("parol2026", "") == .required)
        #expect(AuthValidation.confirmPassword("parol2026", "parol2025") == .passwordsDiffer)
        #expect(AuthValidation.confirmPassword("parol2026", "parol2026") == nil)
    }
}

@MainActor
struct FakeAuthServiceTests {

    private let store = InMemorySessionStore()
    private var service: FakeAuthService { FakeAuthService(store: store, latency: .zero) }

    @Test func signUpThenLogInAndOut() async {
        let auth = service
        if case .failure = await auth.signUp(name: "Juan", email: "Juan@Sinag.ph", password: "parol2026") {
            Issue.record("Sign up should succeed")
        }
        #expect(await auth.currentSession()?.email == "juan@sinag.ph")
        #expect(await auth.signUp(name: "J", email: "juan@sinag.ph", password: "parol2026") == .failure(.emailInUse))

        await auth.signOut()
        #expect(await auth.currentSession() == nil)
        #expect(await auth.login(email: "juan@sinag.ph", password: "wrong-pass") == .failure(.invalidCredentials))
        if case .failure = await auth.login(email: "juan@sinag.ph", password: "parol2026") {
            Issue.record("Log in should succeed")
        }
        #expect(await auth.currentSession()?.name == "Juan")
    }

    @Test func demoPasswordAndOfflineMarker() async {
        let auth = service
        if case .failure = await auth.login(email: "anyone@sinag.ph", password: FakeAuthService.demoPassword) {
            Issue.record("Demo password should log in")
        }
        #expect(await auth.login(email: "offline@sinag.ph", password: "parol2026") == .failure(.network))
        #expect(await auth.requestPasswordReset(email: "offline@sinag.ph") == false)
        #expect(await auth.requestPasswordReset(email: "juan@sinag.ph"))
    }

    @Test func signUpShowsMismatchBeforeSubmit() {
        let viewModel = SignUpViewModel(auth: service)
        viewModel.password = "parol2026"
        viewModel.confirmPassword = "parol"
        #expect(viewModel.confirmError == .passwordsDiffer)
        #expect(viewModel.emailError == nil)
    }
}

@MainActor
struct SessionStoreTests {

    @Test func keychainRoundTrip() {
        let store = KeychainSessionStore(service: "sinag.tests.\(UUID().uuidString)")
        let session = AuthSession(userId: "id-1", email: "juan@sinag.ph", name: "Juan", token: "secret-token")
        store.save(session)
        #expect(store.load() == session)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func descriptionHidesToken() {
        let session = AuthSession(userId: "id", email: "e@x.ph", name: nil, token: "secret-token")
        #expect(!session.description.contains("secret-token"))
    }
}
