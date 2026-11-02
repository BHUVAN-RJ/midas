import XCTest
@testable import Midas

// Build 22 dead-end sweep for App Review guideline 2.1 (lead brief, founder approved 2026-11-01,
// docs/briefs/build-22-2026-10-31.md). A returning user who opened Midas offline was shown the
// sign-up screen until the next launch, with no way to retry. Now: "Can't Connect" and "Try Again",
// the stored session kept.

private final class DeadEndSessionStore: SessionStore, @unchecked Sendable {
    var token: String?
    init(token: String?) { self.token = token }
    func loadToken() -> String? { token }
    func saveToken(_ token: String) { self.token = token }
    func clearToken() { token = nil }
}

private final class DeadEndAuthAPI: AuthAPI, @unchecked Sendable {
    var currentUserResult: Result<MidasUser, Error> = .failure(URLError(.notConnectedToInternet))
    var currentUserCalls = 0

    func registrationChallenge(name: String) async throws -> RegistrationChallenge {
        RegistrationChallenge(challengeId: "r1", challenge: Data([1]), userId: Data([2]), userName: name, relyingPartyId: "rp")
    }

    func completeRegistration(challengeId: String, registration: PasskeyRegistration) async throws -> AuthSession {
        throw AuthAPIError.badResponse
    }

    func loginChallenge() async throws -> LoginChallenge {
        LoginChallenge(challengeId: "l1", challenge: Data([1]), relyingPartyId: "rp")
    }

    func completeLogin(challengeId: String, assertion: PasskeyAssertion) async throws -> AuthSession {
        throw AuthAPIError.badResponse
    }

    func currentUser(token: String) async throws -> MidasUser {
        currentUserCalls += 1
        return try currentUserResult.get()
    }
}

@MainActor
private final class DeadEndPasskeys: PasskeyAuthenticating {
    func createPasskey(for challenge: RegistrationChallenge) async throws -> PasskeyRegistration {
        throw PasskeyError.canceled
    }

    func signIn(with challenge: LoginChallenge) async throws -> PasskeyAssertion {
        throw PasskeyError.canceled
    }
}

@MainActor
final class Build22DeadEndTests: XCTestCase {
    func testOfflineLaunchWithAStoredSessionShowsCantConnectNotTheSignUpScreen() async {
        let api = DeadEndAuthAPI()
        let store = DeadEndSessionStore(token: "kept")
        let model = AuthModel(api: api, store: store, passkeys: DeadEndPasskeys())
        await model.start()
        XCTAssertEqual(model.state, .cannotConnect)
        XCTAssertEqual(store.token, "kept")
        XCTAssertEqual(OnboardingRules.stage(for: model.state, introSeen: true, teachSeen: true), .cannotConnect)
        XCTAssertEqual(OnboardingRules.stage(for: model.state, introSeen: false, teachSeen: false), .cannotConnect)
    }

    func testTryAgainSignsInOnceTheServerAnswers() async {
        let api = DeadEndAuthAPI()
        let store = DeadEndSessionStore(token: "kept")
        let model = AuthModel(api: api, store: store, passkeys: DeadEndPasskeys())
        await model.start()
        let priya = MidasUser(id: "u1", name: "Priya")
        api.currentUserResult = .success(priya)
        await model.retryStart()
        XCTAssertEqual(model.state, .signedIn(priya))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(api.currentUserCalls, 2)
    }

    func testTryAgainWhileStillOfflineStaysOnCantConnect() async {
        let api = DeadEndAuthAPI()
        let model = AuthModel(api: api, store: DeadEndSessionStore(token: "kept"), passkeys: DeadEndPasskeys())
        await model.start()
        await model.retryStart()
        XCTAssertEqual(model.state, .cannotConnect)
        XCTAssertEqual(api.currentUserCalls, 2)
    }

    func testARejectedSessionOnTryAgainShowsTheWelcomeScreen() async {
        let api = DeadEndAuthAPI()
        let store = DeadEndSessionStore(token: "stale")
        let model = AuthModel(api: api, store: store, passkeys: DeadEndPasskeys())
        await model.start()
        api.currentUserResult = .failure(AuthAPIError.signInRequired)
        await model.retryStart()
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(store.token)
    }

    func testTryAgainDoesNothingUnlessCantConnectIsShowing() async {
        let api = DeadEndAuthAPI()
        let model = AuthModel(api: api, store: DeadEndSessionStore(token: nil), passkeys: DeadEndPasskeys())
        await model.start()
        await model.retryStart()
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertEqual(api.currentUserCalls, 0)
    }

    func testCantConnectUsesTheHouseWords() {
        XCTAssertEqual(RestoreCopy.failedTitle, "Can’t Connect")
        XCTAssertEqual(RestoreCopy.retryButton, "Try Again")
    }
}
