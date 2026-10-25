import UserNotifications
import XCTest
@testable import Midas

// Push for Make (docs/briefs/make-contract.md sections 4 and 8, founder 2026-10-24): after sign-in
// the permission is asked once, Midas registers on every launch it may notify, each token goes to
// `POST /push/register` with its APNs host read from the provisioning profile, a push's
// `userInfo["make"]` opens the right thread, and no banner shows for the thread on screen. Also the
// other two server calls the shell makes for Make: `POST /repairs/blocked`, `GET /make/sidekicks`.

@MainActor
private final class FakePushSystem: PushSystem {
    var status: UNAuthorizationStatus
    /// What the status becomes once the person answers the prompt.
    var statusAfterPrompt: UNAuthorizationStatus
    private(set) var prompts = 0
    private(set) var registrations = 0

    init(status: UNAuthorizationStatus, statusAfterPrompt: UNAuthorizationStatus = .authorized) {
        self.status = status
        self.statusAfterPrompt = statusAfterPrompt
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> Bool {
        prompts += 1
        status = statusAfterPrompt
        return statusAfterPrompt == .authorized
    }

    func registerForRemoteNotifications() {
        registrations += 1
    }
}

@MainActor
final class MakePushTests: XCTestCase {
    private var defaultsSuite = ""
    private var sentBodies: [PushRegisterAPI.Body] = []

    override func setUp() {
        super.setUp()
        defaultsSuite = "make-push-\(UUID().uuidString)"
        sentBodies = []
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    private func makeRegistration(_ system: FakePushSystem) throws -> PushRegistration {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        func sandbox() -> String {
            PushEnvironment.sandbox
        }
        func send(_ body: PushRegisterAPI.Body) async {
            sentBodies.append(body)
        }
        return PushRegistration(system: system, defaults: defaults, bundleId: "com.bhuvanrj.midas.test", environment: sandbox, send: send)
    }

    // MARK: Permission and registration

    func testThePermissionIsAskedOnceThenMidasRegistersEveryLaunch() async throws {
        let system = FakePushSystem(status: .notDetermined)
        let registration = try makeRegistration(system)
        await registration.afterSignIn()
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 1)

        // The next launch: no prompt, registers again (the token goes up on every launch)
        let nextLaunch = try makeRegistration(system)
        await nextLaunch.afterSignIn()
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 2)
    }

    func testNotNowIsNeverAskedAgainAndNothingRegisters() async throws {
        let system = FakePushSystem(status: .notDetermined, statusAfterPrompt: .denied)
        let registration = try makeRegistration(system)
        await registration.afterSignIn()
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 0)

        // Even if iOS still says "not determined" (the prompt was swiped away), Midas asks once
        system.status = .notDetermined
        await registration.afterSignIn()
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 0)
    }

    func testAlreadyAllowedRegistersWithoutAsking() async throws {
        let system = FakePushSystem(status: .authorized)
        let registration = try makeRegistration(system)
        await registration.afterSignIn()
        XCTAssertEqual(system.prompts, 0)
        XCTAssertEqual(system.registrations, 1)
    }

    func testEveryTokenGoesToTheServerAsHexWithItsHostAndBundle() async throws {
        let registration = try makeRegistration(FakePushSystem(status: .authorized))
        await registration.didRegister(deviceToken: Data([0x0A, 0xFF, 0x00, 0x7B]))
        XCTAssertEqual(sentBodies, [PushRegisterAPI.Body(token: "0aff007b", env: "sandbox", bundleId: "com.bhuvanrj.midas.test")])
        XCTAssertEqual(registration.sent, sentBodies)
    }

    func testTheRegisterRequestIsAnAuthorisedJSONPost() throws {
        let origin = try XCTUnwrap(URL(string: "https://midas-api-staging.midas-backend.workers.dev"))
        let body = PushRegisterAPI.Body(token: "0aff", env: "production", bundleId: "com.bhuvanrj.midas")
        let request = try PushRegisterAPI.request(platformOrigin: origin, token: "session-token", body: body)
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api-staging.midas-backend.workers.dev/push/register")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try JSONDecoder().decode(PushRegisterAPI.Body.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(sent, body)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(Set(fields.keys), ["token", "env", "bundleId"])
    }

    // MARK: The APNs host

    private func fakeProfile(apsEnvironment: String?) throws -> Data {
        var entitlements: [String: Any] = ["application-identifier": "ZQ2JPFYL98.com.bhuvanrj.midas"]
        if let apsEnvironment {
            entitlements["aps-environment"] = apsEnvironment
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Name": "Midas", "Entitlements": entitlements], format: .xml, options: 0)
        // The real file wraps the list in a signed envelope: bytes before and after it
        var profile = Data([0x30, 0x82, 0x1F, 0x00, 0x06, 0x09])
        profile.append(plist)
        profile.append(Data([0xA0, 0x82, 0x0D, 0x00]))
        return profile
    }

    func testTheHostComesFromTheProvisioningProfile() throws {
        XCTAssertEqual(PushEnvironment.fromProvisioningProfile(try fakeProfile(apsEnvironment: "development")), "sandbox")
        XCTAssertEqual(PushEnvironment.fromProvisioningProfile(try fakeProfile(apsEnvironment: "production")), "production")
        XCTAssertEqual(PushEnvironment.fromProvisioningProfile(try fakeProfile(apsEnvironment: nil)), "production")
        XCTAssertEqual(PushEnvironment.fromProvisioningProfile(nil), "production", "the App Store and TestFlight ship no profile")
        XCTAssertEqual(PushEnvironment.fromProvisioningProfile(Data("not a profile".utf8)), "production")
    }

    // MARK: A push, read

    func testAPushPayloadOpensThePersonsOrTheFoundersThread() throws {
        let card = try XCTUnwrap(MakePushPayload(userInfo: ["make": ["kind": "card", "requestId": "request01", "userId": "user0001", "cardId": "card00001"]]))
        XCTAssertFalse(card.isForFounder)
        XCTAssertEqual(card.thread, MakeThreadRef(userId: nil, reqId: "request01"))
        XCTAssertEqual(card.cardId, "card00001")

        let built = try XCTUnwrap(MakePushPayload(userInfo: ["make": ["kind": "built", "requestId": "request01", "userId": "user0001"]]))
        XCTAssertFalse(built.isForFounder)

        let message = try XCTUnwrap(MakePushPayload(userInfo: ["make": ["kind": "message", "requestId": "request01", "userId": "user0001"]]))
        XCTAssertTrue(message.isForFounder)
        XCTAssertEqual(message.thread, MakeThreadRef(userId: "user0001", reqId: "request01"))
        let answer = try XCTUnwrap(MakePushPayload(userInfo: ["make": ["kind": "answer", "requestId": "request01", "userId": "user0001"]]))
        XCTAssertTrue(answer.isForFounder)

        XCTAssertNil(MakePushPayload(userInfo: ["midasSidekickId": "reminders", "midasReminderId": "r1"]), "a reminder notification is not Make's")
        XCTAssertNil(MakePushPayload(userInfo: ["make": ["kind": "typing", "requestId": "request01", "userId": "user0001"]]))
        XCTAssertNil(MakePushPayload(userInfo: ["make": ["kind": "card", "userId": "user0001"]]))
    }

    func testNoBannerForTheThreadAlreadyOnScreen() throws {
        let message = try XCTUnwrap(MakePushPayload(userInfo: ["make": ["kind": "message", "requestId": "request01", "userId": "user0001"]]))
        XCTAssertFalse(message.showsBanner(openThread: MakeThreadRef(userId: "user0001", reqId: "request01")))
        XCTAssertTrue(message.showsBanner(openThread: MakeThreadRef(userId: "user0001", reqId: "request02")))
        XCTAssertTrue(message.showsBanner(openThread: MakeThreadRef(userId: nil, reqId: "request01")), "the person's own copy of the request is another screen")
        XCTAssertTrue(message.showsBanner(openThread: nil))
    }

    // MARK: The other calls

    func testTheBlockedSwipeLogIsAnAuthorisedPostWithANewClientIdEachTime() throws {
        let origin = try XCTUnwrap(URL(string: "https://midas-api.midas-backend.workers.dev"))
        let device = RepairDeviceInfo(device: "iPhone17,1", iosVersion: "27.0", appVersion: "0.1.0", appBuild: "15")
        let first = RepairBlockedLog.body(sidekickId: MakeSidekick.id, device: device)
        let second = RepairBlockedLog.body(sidekickId: MakeSidekick.id, device: device)
        XCTAssertNotEqual(first.clientId, second.clientId)
        XCTAssertEqual(first.clientId.count, 32)
        XCTAssertEqual(first.appVersion, "0.1.0")
        XCTAssertEqual(first.appBuild, "15")

        let request = try RepairBlockedLog.request(platformOrigin: origin, token: "session-token", body: first)
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api.midas-backend.workers.dev/repairs/blocked")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
        let sent = try JSONDecoder().decode(RepairBlockedLog.Body.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(sent, first)
        XCTAssertEqual(sent.sidekickId, "make")
    }

    func testTheBuiltPickerListsEverySidekickButTheBuiltInOnes() throws {
        let body = Data(#"{"sidekicks":[{"id":"plants","name":"Plants","version":"3"},{"id":"jess","name":"jess","version":"built-in"},{"id":"make","name":"Make","version":"built-in"},{"id":"make-inbox","name":"Inbox","version":"built-in"},{"id":"reminders","name":"Reminders","version":"7"}]}"#.utf8)
        let buildables = MakeAPI.buildables(from: body)
        XCTAssertEqual(buildables.map(\.id), ["plants", "reminders"])
        XCTAssertEqual(buildables.first, MakeBuildable(id: "plants", name: "Plants", version: "3"))
        XCTAssertTrue(MakeAPI.buildables(from: Data("Not Found".utf8)).isEmpty, "a 404 page before the route lands lists nothing")

        let origin = try XCTUnwrap(URL(string: "https://midas-api-staging.midas-backend.workers.dev"))
        let request = MakeAPI.sidekicksRequest(platformOrigin: origin, token: "session-token")
        XCTAssertEqual(request.url?.path(), "/make/sidekicks")
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
    }

    func testBuiltNeedsAPickAndAPlan() {
        XCTAssertFalse(MakeBuiltPicker.canSend(pickedId: nil, plan: "Water"))
        XCTAssertFalse(MakeBuiltPicker.canSend(pickedId: "plants", plan: "  "))
        XCTAssertTrue(MakeBuiltPicker.canSend(pickedId: "plants", plan: "Water"))
    }

    // MARK: The entitlements

    func testBothAppsCanReceivePushes() throws {
        let midasFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Midas")
        for name in ["Midas.entitlements", "Midas-Test.entitlements"] {
            let data = try Data(contentsOf: midasFolder.appending(path: name))
            let entitlements = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(entitlements["aps-environment"] as? String, "development", name)
        }
    }
}
