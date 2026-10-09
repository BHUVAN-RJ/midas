import XCTest
@testable import Midas

final class Base64URLTests: XCTestCase {
    func testEncodesWithUrlSafeAlphabetAndNoPadding() {
        let bytes = Data([0xfb, 0xff, 0xbf])
        XCTAssertEqual(Base64URL.encode(bytes), "-_-_")
        XCTAssertEqual(Base64URL.encode(Data([0xff])), "_w")
    }

    func testDecodesUnpaddedText() {
        XCTAssertEqual(Base64URL.decode("_w"), Data([0xff]))
        XCTAssertEqual(Base64URL.decode("-_-_"), Data([0xfb, 0xff, 0xbf]))
        XCTAssertNil(Base64URL.decode("@@@"))
    }
}

final class AuthOptionsParserTests: XCTestCase {
    // Shape of @simplewebauthn/server registration options, as the backend returns them.
    func testParsesRegistrationOptions() throws {
        let json = """
        {"challengeId":"c1","options":{"challenge":"AQID","rp":{"name":"Midas","id":"midas-api.midas-backend.workers.dev"},
        "user":{"id":"BAUG","name":"Priya","displayName":"Priya"},"pubKeyCredParams":[]}}
        """
        let challenge = try AuthOptionsParser.registration(from: Data(json.utf8))
        XCTAssertEqual(challenge.challengeId, "c1")
        XCTAssertEqual(challenge.challenge, Data([1, 2, 3]))
        XCTAssertEqual(challenge.userId, Data([4, 5, 6]))
        XCTAssertEqual(challenge.userName, "Priya")
        XCTAssertEqual(challenge.relyingPartyId, "midas-api.midas-backend.workers.dev")
    }

    func testRejectsRegistrationOptionsWithoutRelyingParty() {
        let json = #"{"challengeId":"c1","options":{"challenge":"AQID","user":{"id":"BAUG","name":"P"}}}"#
        XCTAssertThrowsError(try AuthOptionsParser.registration(from: Data(json.utf8)))
    }

    func testParsesLoginOptions() throws {
        let json = #"{"challengeId":"c2","options":{"challenge":"AQID","rpId":"midas-api.midas-backend.workers.dev"}}"#
        let challenge = try AuthOptionsParser.login(from: Data(json.utf8))
        XCTAssertEqual(challenge.challengeId, "c2")
        XCTAssertEqual(challenge.challenge, Data([1, 2, 3]))
        XCTAssertEqual(challenge.relyingPartyId, "midas-api.midas-backend.workers.dev")
    }
}

final class WebAuthnPayloadTests: XCTestCase {
    func testRegistrationPayloadMatchesServerShape() throws {
        let registration = PasskeyRegistration(credentialId: Data([0xff]), clientDataJSON: Data([1]), attestationObject: Data([2]))
        let payload = WebAuthnPayload.registration(challengeId: "c1", registration: registration)
        XCTAssertEqual(payload["challengeId"] as? String, "c1")
        let credential = try XCTUnwrap(payload["credential"] as? [String: Any])
        XCTAssertEqual(credential["id"] as? String, "_w")
        XCTAssertEqual(credential["rawId"] as? String, "_w")
        XCTAssertEqual(credential["type"] as? String, "public-key")
        let response = try XCTUnwrap(credential["response"] as? [String: Any])
        XCTAssertEqual(response["clientDataJSON"] as? String, "AQ")
        XCTAssertEqual(response["attestationObject"] as? String, "Ag")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
    }

    func testAssertionPayloadCarriesSignatureAndUserHandle() throws {
        let assertion = PasskeyAssertion(
            credentialId: Data([0xff]),
            clientDataJSON: Data([1]),
            authenticatorData: Data([2]),
            signature: Data([3]),
            userHandle: Data([4])
        )
        let payload = WebAuthnPayload.assertion(challengeId: "c2", assertion: assertion)
        let credential = try XCTUnwrap(payload["credential"] as? [String: Any])
        let response = try XCTUnwrap(credential["response"] as? [String: Any])
        XCTAssertEqual(response["authenticatorData"] as? String, "Ag")
        XCTAssertEqual(response["signature"] as? String, "Aw")
        XCTAssertEqual(response["userHandle"] as? String, "BA")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
    }
}

final class KeychainSessionStoreTests: XCTestCase {
    func testSavesReplacesAndClearsTheToken() {
        let store = KeychainSessionStore(service: "com.bhuvanrj.midas.tests.\(UUID().uuidString)")
        XCTAssertNil(store.loadToken())
        store.saveToken("first")
        store.saveToken("second")
        XCTAssertEqual(store.loadToken(), "second")
        store.clearToken()
        XCTAssertNil(store.loadToken())
    }
}

// MARK: - AuthModel

private final class MemorySessionStore: SessionStore, @unchecked Sendable {
    var token: String?
    init(token: String? = nil) { self.token = token }
    func loadToken() -> String? { token }
    func saveToken(_ token: String) { self.token = token }
    func clearToken() { token = nil }
}

private final class FakeAuthAPI: AuthAPI, @unchecked Sendable {
    var currentUserResult: Result<MidasUser, Error> = .failure(AuthAPIError.signInRequired)
    var loginResult: Result<AuthSession, Error> = .failure(AuthAPIError.signInRequired)
    var registeredNames: [String] = []
    var currentUserCalls = 0

    func registrationChallenge(name: String) async throws -> RegistrationChallenge {
        registeredNames.append(name)
        return RegistrationChallenge(challengeId: "r1", challenge: Data([1]), userId: Data([2]), userName: name, relyingPartyId: "rp")
    }

    func completeRegistration(challengeId: String, registration: PasskeyRegistration) async throws -> AuthSession {
        AuthSession(token: "new-token", user: MidasUser(id: "u1", name: registeredNames.last ?? ""))
    }

    func loginChallenge() async throws -> LoginChallenge {
        LoginChallenge(challengeId: "l1", challenge: Data([1]), relyingPartyId: "rp")
    }

    func completeLogin(challengeId: String, assertion: PasskeyAssertion) async throws -> AuthSession {
        try loginResult.get()
    }

    func currentUser(token: String) async throws -> MidasUser {
        currentUserCalls += 1
        return try currentUserResult.get()
    }
}

@MainActor
private final class FakePasskeys: PasskeyAuthenticating {
    var error: Error?

    func createPasskey(for challenge: RegistrationChallenge) async throws -> PasskeyRegistration {
        if let error { throw error }
        return PasskeyRegistration(credentialId: Data([9]), clientDataJSON: Data(), attestationObject: Data())
    }

    func signIn(with challenge: LoginChallenge) async throws -> PasskeyAssertion {
        if let error { throw error }
        return PasskeyAssertion(credentialId: Data([9]), clientDataJSON: Data(), authenticatorData: Data(), signature: Data(), userHandle: Data())
    }
}

@MainActor
final class AuthModelTests: XCTestCase {
    func testNoStoredTokenShowsWelcomeWithoutCallingServer() async {
        let api = FakeAuthAPI()
        let model = AuthModel(api: api, store: MemorySessionStore(), passkeys: FakePasskeys())
        await model.start()
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertEqual(api.currentUserCalls, 0)
    }

    func testValidStoredTokenSignsIn() async {
        let api = FakeAuthAPI()
        api.currentUserResult = .success(MidasUser(id: "u1", name: "Priya"))
        let model = AuthModel(api: api, store: MemorySessionStore(token: "t"), passkeys: FakePasskeys())
        await model.start()
        XCTAssertEqual(model.state, .signedIn(MidasUser(id: "u1", name: "Priya")))
    }

    func testRejectedStoredTokenIsClearedAndShowsWelcome() async {
        let api = FakeAuthAPI()
        let store = MemorySessionStore(token: "stale")
        let model = AuthModel(api: api, store: store, passkeys: FakePasskeys())
        await model.start()
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(store.token)
    }

    func testNetworkFailureKeepsTheStoredToken() async {
        let api = FakeAuthAPI()
        api.currentUserResult = .failure(URLError(.notConnectedToInternet))
        let store = MemorySessionStore(token: "kept")
        let model = AuthModel(api: api, store: store, passkeys: FakePasskeys())
        await model.start()
        XCTAssertEqual(store.token, "kept")
        XCTAssertNotNil(model.errorMessage)
    }

    func testCreateAccountSendsTrimmedNameAndStoresSession() async {
        let api = FakeAuthAPI()
        let store = MemorySessionStore()
        let model = AuthModel(api: api, store: store, passkeys: FakePasskeys())
        await model.createAccount(name: "  Priya ")
        XCTAssertEqual(api.registeredNames, ["Priya"])
        XCTAssertEqual(store.token, "new-token")
        XCTAssertEqual(model.state, .signedIn(MidasUser(id: "u1", name: "Priya")))
    }

    func testBlankNameNeverReachesTheServer() async {
        let api = FakeAuthAPI()
        let model = AuthModel(api: api, store: MemorySessionStore(), passkeys: FakePasskeys())
        await model.createAccount(name: "   ")
        XCTAssertTrue(api.registeredNames.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    func testCanceledPasskeySheetLeavesUserSignedOutWithNoError() async {
        let api = FakeAuthAPI()
        let passkeys = FakePasskeys()
        passkeys.error = PasskeyError.canceled
        let store = MemorySessionStore()
        let model = AuthModel(api: api, store: store, passkeys: passkeys)
        await model.start()
        await model.createAccount(name: "Priya")
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(store.token)
    }

    func testReturningUserSignsInWithPasskey() async {
        let api = FakeAuthAPI()
        let returningUser = MidasUser(id: "u7", name: "Sam")
        api.loginResult = .success(AuthSession(token: "login-token", user: returningUser))
        let store = MemorySessionStore()
        let model = AuthModel(api: api, store: store, passkeys: FakePasskeys())
        await model.signInWithPasskey()
        XCTAssertEqual(model.state, .signedIn(returningUser))
        XCTAssertEqual(store.token, "login-token")
    }

    func testUnknownPasskeyShowsAnError() async {
        let api = FakeAuthAPI()
        let model = AuthModel(api: api, store: MemorySessionStore(), passkeys: FakePasskeys())
        await model.start()
        await model.signInWithPasskey()
        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNotNil(model.errorMessage)
    }
}

final class EntitlementsTests: XCTestCase {
    // The passkey domain in the app must be the backend's relying party id.
    func testAssociatedDomainMatchesPlatformOrigin() {
        XCTAssertEqual(PlatformConfig.platformOrigin.host, "midas-api.midas-backend.workers.dev")
    }
}
