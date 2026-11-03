import UIKit
import XCTest
@testable import Midas

// AI consent (Apple guideline 5.1.2(i); founder, 2026-11-02; docs/mockups/ai-consent-2026-11-02.html):
// "Allow AI?" once after the four teaching cards (A1), and again at each jess or Edit use after
// Not Now (D1); the AI switch in Settings; nothing goes to jess or Edit's servers before Allow.

/// A transcriber that never hears anything; the jess screen only has to open.
@MainActor
private final class SilentVoiceTranscriber: VoiceTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {}

    func stop() {}
}

private final class UnusedVoiceParser: VoiceReminderParsing, @unchecked Sendable {
    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        .unreachable
    }
}

/// A repair transcriber that never hears anything; the tests type their words.
@MainActor
private final class SilentRepairTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {}

    func stop() {}
}

private final class AcceptingUploadAPI: RepairUploadAPI, @unchecked Sendable {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .accepted
    }
}

/// Counts every request that reaches the network and answers 500.
private final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0

    static func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }

    static func requestCount() -> Int {
        lock.lock()
        let current = count
        lock.unlock()
        return current
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class AIConsentTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var outboxURL: URL!
    private let user = MidasUser(id: "u1", name: "Bhuvan")

    override func setUp() {
        super.setUp()
        suiteName = "AIConsentTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "ai-consent-\(UUID().uuidString)")
        CountingURLProtocol.reset()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private func makeMemory() -> AIConsentMemory {
        AIConsentMemory(defaults: defaults)
    }

    private func makeCenter() -> AIConsentCenter {
        AIConsentCenter(memory: makeMemory())
    }

    // MARK: The answer is remembered

    func testNothingIsAllowedBeforeTheQuestion() {
        let memory = makeMemory()
        XCTAssertEqual(memory.answer, .notAsked)
        XCTAssertFalse(memory.isAllowed)
        XCTAssertFalse(makeCenter().isAllowed)
    }

    func testAnswerSurvivesARelaunch() {
        let first = makeCenter()
        first.allow()
        XCTAssertEqual(makeCenter().answer, .allowed)
        XCTAssertEqual(defaults.string(forKey: AIConsentMemory.answerKey), "allowed")
        let second = makeCenter()
        second.decline()
        XCTAssertEqual(makeCenter().answer, .declined)
        XCTAssertFalse(makeMemory().isAllowed)
    }

    func testSigningOutForgetsTheAnswer() {
        let center = makeCenter()
        center.allow()
        center.forget()
        XCTAssertEqual(center.answer, .notAsked)
        XCTAssertNil(defaults.string(forKey: AIConsentMemory.answerKey))
        XCTAssertEqual(makeCenter().answer, .notAsked)
    }

    // MARK: A1: once, after the four cards

    func testScreenShowsOnlyOnHomeUntilAnswered() {
        XCTAssertTrue(AIConsentRules.showsOnboardingScreen(stage: .home, answer: .notAsked))
        XCTAssertFalse(AIConsentRules.showsOnboardingScreen(stage: .home, answer: .allowed))
        XCTAssertFalse(AIConsentRules.showsOnboardingScreen(stage: .home, answer: .declined))
        for stage in [OnboardingStage.checking, .cannotConnect, .intro, .welcome, .teach] {
            XCTAssertFalse(AIConsentRules.showsOnboardingScreen(stage: stage, answer: .notAsked), "\(stage) must not show Allow AI?")
        }
    }

    func testNewUserSeesItAfterTheCardsThenHome() {
        let progress = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        let center = makeCenter()
        progress.finishIntro()
        progress.noteAuthState(.signedIn(user))
        let cardsStage = progress.stage(for: .signedIn(user))
        XCTAssertEqual(cardsStage, .teach)
        XCTAssertFalse(AIConsentRules.showsOnboardingScreen(stage: cardsStage, answer: center.answer), "not before the cards")
        progress.finishTeach()
        let afterCards = progress.stage(for: .signedIn(user))
        XCTAssertTrue(AIConsentRules.showsOnboardingScreen(stage: afterCards, answer: center.answer))
        center.decline()
        XCTAssertFalse(AIConsentRules.showsOnboardingScreen(stage: afterCards, answer: center.answer), "Not Now goes home too")
    }

    func testUserSignedInBeforeThisBuildSeesItOnce() {
        let progress = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        progress.noteAuthState(.signedIn(user))
        let stage = progress.stage(for: .signedIn(user))
        XCTAssertTrue(AIConsentRules.showsOnboardingScreen(stage: stage, answer: makeCenter().answer))
        makeCenter().allow()
        let relaunched = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertFalse(AIConsentRules.showsOnboardingScreen(stage: relaunched.stage(for: .signedIn(user)), answer: makeCenter().answer))
    }

    // MARK: D1: asked again at use after Not Now

    func testAllowedActionRunsAtOnce() {
        let center = makeCenter()
        center.allow()
        var runs = 0
        center.run { runs += 1 }
        XCTAssertEqual(runs, 1)
        XCTAssertFalse(center.isAskShown)
    }

    func testActionWaitsForAllowThenRunsOnceWhenTheSheetHasGone() {
        let center = makeCenter()
        var runs = 0
        center.run { runs += 1 }
        XCTAssertEqual(runs, 0, "nothing may run before Allow")
        XCTAssertTrue(center.isAskShown)
        center.allow()
        XCTAssertFalse(center.isAskShown)
        XCTAssertEqual(runs, 0, "runs only once the sheet is gone")
        center.askDismissed()
        XCTAssertEqual(runs, 1)
        center.askDismissed()
        XCTAssertEqual(runs, 1, "runs once")
        XCTAssertEqual(makeCenter().answer, .allowed)
    }

    func testNotNowDropsTheActionAndAsksAgainNextTime() {
        let center = makeCenter()
        var runs = 0
        center.run { runs += 1 }
        center.decline()
        center.askDismissed()
        XCTAssertEqual(runs, 0)
        XCTAssertEqual(center.answer, .declined)
        center.run { runs += 1 }
        XCTAssertTrue(center.isAskShown, "D1: the same screen again at the next use")
        XCTAssertEqual(runs, 0)
    }

    func testSwipingTheSheetAwaySendsNothing() {
        let center = makeCenter()
        var runs = 0
        center.run { runs += 1 }
        center.askDismissed()
        XCTAssertEqual(runs, 0)
        XCTAssertEqual(center.answer, .notAsked)
    }

    // MARK: The Settings switch

    func testSwitchOffStopsAndOnAsksFirst() {
        let center = makeCenter()
        center.allow()
        center.setAllowed(false)
        XCTAssertFalse(center.isAllowed)
        XCTAssertEqual(makeCenter().answer, .declined)
        var runs = 0
        center.run { runs += 1 }
        XCTAssertTrue(center.isAskShown, "jess and Edit ask again after the switch is off")
        XCTAssertEqual(runs, 0)
        center.setAllowed(true)
        XCTAssertTrue(makeCenter().isAllowed)
    }

    // MARK: jess asks before its screen opens

    private func makeVoiceFlow(center: AIConsentCenter?) -> VoiceReminderFlow {
        func isSignedIn() -> Bool { true }
        func lists() -> [VoiceReminderList] { [] }
        func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing { SilentVoiceTranscriber() }
        func save(_ reminder: VoiceResolvedReminder) throws {}
        func now() -> Date { Date(timeIntervalSince1970: 1_760_000_000) }
        func timeZone() -> TimeZone { TimeZone(identifier: "America/Los_Angeles")! }
        func app() -> VoiceParseApp { VoiceParseApp(version: "0.1.0", build: "22", ios: "26.0", device: "iPhone17,1") }
        var dependencies = VoiceReminderDependencies(isSignedIn: isSignedIn, lists: lists, makeTranscriber: makeTranscriber, api: UnusedVoiceParser(), save: save, now: now, timeZone: timeZone, app: app)
        if let center {
            func isAIAllowed() -> Bool { center.isAllowed }
            dependencies.aiAllowed = isAIAllowed
            dependencies.askForAI = center.run
        }
        return VoiceReminderFlow(dependencies: dependencies)
    }

    func testJessDoesNotOpenBeforeAllow() {
        let center = makeCenter()
        let flow = makeVoiceFlow(center: center)
        flow.request()
        XCTAssertFalse(flow.isPresented, "jess must not listen before Allow")
        XCTAssertTrue(center.isAskShown)
        center.allow()
        center.askDismissed()
        XCTAssertTrue(flow.isPresented, "Allow opens jess")
    }

    func testJessAfterNotNowAsksAgainAndStaysClosed() {
        let center = makeCenter()
        center.decline()
        let flow = makeVoiceFlow(center: center)
        flow.request()
        XCTAssertFalse(flow.isPresented)
        XCTAssertTrue(center.isAskShown)
        center.decline()
        center.askDismissed()
        XCTAssertFalse(flow.isPresented)
    }

    func testJessOpensAtOnceWhenAllowed() {
        let center = makeCenter()
        center.allow()
        let flow = makeVoiceFlow(center: center)
        flow.request()
        XCTAssertTrue(flow.isPresented)
        XCTAssertFalse(center.isAskShown)
    }

    // MARK: Edit asks at Send

    private static func snapshot() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
        return renderer.image(actions: Self.fillWhite)
    }

    private static func fillWhite(_ context: UIGraphicsImageRendererContext) {
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
    }

    private func makeRepairSession(center: AIConsentCenter) -> RepairSession {
        let uploader = RepairUploader(api: AcceptingUploadAPI(), outbox: RepairOutbox(directoryURL: outboxURL))
        let versions = SidekickBundleVersions()
        versions.record(sidekickId: "reminders", version: "v7", scope: "user")
        let session = RepairSession(sidekickId: "reminders", snapshot: Self.snapshot(), viewSize: CGSize(width: 20, height: 30), transcriber: SilentRepairTranscriber(), uploader: uploader, bundleVersions: versions)
        session.aiConsent = center
        session.typedText = "make the button bigger"
        return session
    }

    func testEditSendWaitsForAllow() {
        let center = makeCenter()
        let session = makeRepairSession(center: center)
        var sent = 0
        session.onSent = { _, _ in sent += 1 }
        session.sendWhenAllowed()
        XCTAssertNil(session.finish, "Edit must not send before Allow")
        XCTAssertEqual(sent, 0)
        XCTAssertTrue(center.isAskShown)
        center.allow()
        center.askDismissed()
        XCTAssertEqual(session.finish, .sent)
        XCTAssertEqual(sent, 1)
    }

    func testEditNotNowKeepsTheLayerOpenAndSendsNothing() {
        let center = makeCenter()
        let session = makeRepairSession(center: center)
        session.sendWhenAllowed()
        center.decline()
        center.askDismissed()
        XCTAssertNil(session.finish)
        XCTAssertEqual(center.answer, .declined)
    }

    func testEditSendsAtOnceWhenAllowed() {
        let center = makeCenter()
        center.allow()
        let session = makeRepairSession(center: center)
        session.sendWhenAllowed()
        XCTAssertEqual(session.finish, .sent)
        XCTAssertFalse(center.isAskShown)
    }

    // MARK: Backstop: no request leaves the phone before Allow

    func testAIRequestTokenOnlyAfterAllow() {
        func token() -> String? { "session-token" }
        let memory = makeMemory()
        XCTAssertNil(AIConsentRules.tokenForAIRequest(memory: memory, sessionToken: token))
        memory.save(.declined)
        XCTAssertNil(AIConsentRules.tokenForAIRequest(memory: memory, sessionToken: token))
        memory.save(.allowed)
        XCTAssertEqual(AIConsentRules.tokenForAIRequest(memory: memory, sessionToken: token), "session-token")
    }

    private func countingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func jessRequest() -> JessRouteRequest {
        let app = VoiceParseApp(version: "0.1.0", build: "22", ios: "26.0", device: "iPhone17,1")
        return JessRouteRequest(transcript: "remind me to call mum", now: "2026-11-02T10:00:00-08:00", timeZone: "America/Los_Angeles", locale: "en_US", sidekicks: [], app: app, listenMs: 1200)
    }

    func testJessRequestNeverLeavesThePhoneBeforeAllow() async {
        let memory = makeMemory()
        let tokenForJess: @Sendable () -> String? = { AIConsentRules.tokenForAIRequest(memory: memory, sessionToken: { "session-token" }) }
        let router = RemoteJessRouter(platformOrigin: URL(string: "https://example.invalid")!, session: countingSession(), sessionToken: tokenForJess)
        let blocked = await router.route(jessRequest())
        XCTAssertEqual(blocked, .unreachable)
        XCTAssertEqual(CountingURLProtocol.requestCount(), 0, "no request before Allow")
        memory.save(.allowed)
        _ = await router.route(jessRequest())
        XCTAssertEqual(CountingURLProtocol.requestCount(), 1, "after Allow the request goes out")
    }

    // MARK: Words (docs/WRITING.md)

    func testWordsOnTheScreen() {
        // No feature or provider names on the screen; those stay on /privacy (build 22 feedback,
        // founder 2026-11-02, midas-intel design doc "Build 22 feedback from TestFlight").
        XCTAssertEqual(AIConsentCopy.title, "Third-Party Services")
        XCTAssertEqual(AIConsentCopy.allow, "Allow")
        XCTAssertEqual(AIConsentCopy.notNow, "Not Now")
        XCTAssertEqual(AIConsentCopy.privacyPolicy, "Privacy Policy")
        XCTAssertEqual(AIConsentCopy.settingsSwitch, "Third-Party Services")
        let labels = [AIConsentCopy.title, AIConsentCopy.allow, AIConsentCopy.notNow, AIConsentCopy.privacyPolicy]
        for label in labels {
            XCTAssertFalse(label.hasSuffix("."), "no period on titles and buttons: \(label)")
        }
    }

    func testPrivacyPolicyOpensThePrivacyPage() {
        let origin = URL(string: "https://midas-api-staging.midas-backend.workers.dev")!
        XCTAssertEqual(AIConsentCopy.privacyURL(platformOrigin: origin).absoluteString, "https://midas-api-staging.midas-backend.workers.dev/privacy")
    }
}
