import SwiftUI
import XCTest
@testable import Midas

// jess in the background, one result card, jess for everyone (founder, 2026-10-22; docs/PRODUCT.md
// section of that name; brief midas-intel docs/plans/2026-10-22-jess-background-brief.md item 5):
// background time is asked for and the request survives leaving the Listening screen; a request
// iOS stopped is finished exactly once on the next open (never applied twice); jess posts no iOS
// notification; every result is one home page card (states, kept on disk, newest first, kept
// until dismissed); the built-in jess Sidekick is listed, opens the Listening screen and has no
// tools.

private let backgroundRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let laZone = TimeZone(identifier: "America/Los_Angeles")!
private let tokyoZone = TimeZone(identifier: "Asia/Tokyo")!
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
private let saidTime = ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!
private let laterTime = ISO8601DateFormatter().date(from: "2026-10-21T09:30:00Z")!
private let milkInput = #"{"title":"Milk","notes":null,"list":null,"when":null}"#

/// Waits for something done on the main actor after an await.
@MainActor
private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private func temporaryResultsFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "jess-results-\(UUID().uuidString)/results.json")
}

/// iOS background time: counts begin and end, and can end the time early.
@MainActor
private final class StubBackgroundTime: JessBackgroundTime {
    private(set) var begun = 0
    private(set) var ended: [Int] = []
    private var expiredHandlers: [Int: @MainActor () -> Void] = [:]
    private var nextToken = 1

    var openTokens: [Int] {
        Array(expiredHandlers.keys)
    }

    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        begun += 1
        let token = nextToken
        nextToken += 1
        expiredHandlers[token] = expired
        return token
    }

    func end(_ token: Int) {
        ended.append(token)
        expiredHandlers[token] = nil
    }

    /// iOS ends the time before the answer came.
    func expireAll() {
        let handlers = expiredHandlers
        for (_, handler) in handlers {
            handler()
        }
    }
}

/// Stands in for JessRouter.route: answers from a list. A done answer is applied (counted, and
/// `onApplied` called) before the hold after-apply, as the real router writes the ops and then
/// awaits its report. It can hold before the answer (a slow server) or after the apply.
@MainActor
private final class HeldRoute {
    enum Hold {
        case none
        case beforeAnswer
        case afterApply
    }

    struct Call {
        let transcript: String
        let listenMs: Int
        let saidAt: Date
        let timeZone: String
    }

    var answers: [JessResult]
    var hold: Hold = .none
    private(set) var calls: [Call] = []
    private(set) var applied = 0
    private(set) var returned = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    init(answers: [JessResult]) {
        self.answers = answers
    }

    var isHolding: Bool {
        !held.isEmpty
    }

    func route(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        calls.append(Call(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone.identifier))
        let currentHold = hold
        if currentHold == .beforeAnswer {
            await waitForRelease()
        }
        let answer = answers.isEmpty ? JessResult.notDone(transcript: transcript) : answers.removeFirst()
        if case .done = answer {
            applied += 1
            onApplied(answer)
        }
        if currentHold == .afterApply {
            await waitForRelease()
        }
        returned += 1
        return answer
    }

    func release() {
        let waiting = held
        held = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    private func waitForRelease() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            held.append(continuation)
        }
    }
}

/// The clock and the place, changeable mid-test.
@MainActor
private final class Surroundings {
    var now = saidTime
    var zone = laZone
    var inForeground = false
    var signedIn = true
}

@MainActor
private func makeResults(file: URL, route: HeldRoute, time: StubBackgroundTime, surroundings: Surroundings) -> JessResults {
    func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        await route.route(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone, onApplied: onApplied)
    }
    func isSignedIn() -> Bool {
        surroundings.signedIn
    }
    func isInForeground() -> Bool {
        surroundings.inForeground
    }
    func now() -> Date {
        surroundings.now
    }
    func timeZone() -> TimeZone {
        surroundings.zone
    }
    let dependencies = JessResultsDependencies(route: routeCall, backgroundTime: time, isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    return JessResults(file: JessResultsFile(fileURL: file), dependencies: dependencies)
}

/// Starts a request the way the Listening screen does, without waiting for it.
@MainActor
private final class Submission {
    private(set) var isFinished = false

    init(results: JessResults, transcript: String) {
        Task { @MainActor [weak self] in
            await results.submit(transcript: transcript, listenMs: 900)
            self?.isFinished = true
        }
    }
}

// MARK: - Background time and leaving the screen

/// Stands in for the shared transcriber.
@MainActor
private final class SaidWords: VoiceTranscribing {
    var onUpdate: (@MainActor (VoiceTranscript) -> Void)?
    var onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        self.onUpdate = onUpdate
        self.onEnd = onEnd
    }

    func stop() {
        end(.stopped)
    }

    func say(_ text: String) {
        onUpdate?(VoiceTranscript(text: text, words: []))
    }

    func end(_ reason: VoiceTranscriptionEnd) {
        let endHandler = onEnd
        onEnd = nil
        onUpdate = nil
        endHandler?(reason)
    }
}

private final class NeverParser: VoiceReminderParsing, @unchecked Sendable {
    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        .unreachable
    }
}

@MainActor
private func makeFlow(results: JessResults, transcriber: SaidWords) -> VoiceReminderFlow {
    func isSignedIn() -> Bool {
        true
    }
    func lists() -> [VoiceReminderList] {
        []
    }
    func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing {
        transcriber
    }
    func save(_ reminder: VoiceResolvedReminder) throws {}
    func now() -> Date {
        saidTime
    }
    func timeZone() -> TimeZone {
        laZone
    }
    func app() -> VoiceParseApp {
        VoiceParseApp(version: "0.1.0", build: "5", ios: "26.1", device: "iPhone17,1")
    }
    func submitToJess(transcript: String, listenMs: Int) async {
        await results.submit(transcript: transcript, listenMs: listenMs)
    }
    var dependencies = VoiceReminderDependencies(isSignedIn: isSignedIn, lists: lists, makeTranscriber: makeTranscriber, api: NeverParser(), save: save, now: now, timeZone: timeZone, app: app)
    dependencies.route = submitToJess
    return VoiceReminderFlow(dependencies: dependencies)
}

@MainActor
final class JessBackgroundTimeTests: XCTestCase {
    func testBackgroundTimeIsAskedForAndLeavingTheScreenDoesNotCancelTheRequest() async {
        let route = HeldRoute(answers: [.done(text: "Added Bananas", at: nil, allDay: nil, timeZone: "America/Los_Angeles")])
        route.hold = .beforeAnswer
        let time = StubBackgroundTime()
        let results = makeResults(file: temporaryResultsFile(), route: route, time: time, surroundings: Surroundings())
        let transcriber = SaidWords()
        let flow = makeFlow(results: results, transcriber: transcriber)

        flow.request()
        await flow.startListening()
        XCTAssertFalse(flow.finishesInBackground, "while listening the way out is Cancel")
        transcriber.say("add bananas")
        transcriber.end(.silence)
        await waitUntil { route.isHolding }

        XCTAssertEqual(flow.phase, .sending)
        XCTAssertTrue(flow.finishesInBackground)
        XCTAssertEqual(VoiceReminderCopy.close, "Close")
        XCTAssertEqual(time.begun, 1, "background time asked for once the words are in")
        XCTAssertEqual(time.openTokens.count, 1)
        XCTAssertEqual(results.pendingRequests.count, 1, "on disk before it is sent")
        XCTAssertEqual(results.cards.first?.kind, .working)

        // Leaving the Listening screen (its button, home, lock) closes it; the request goes on
        flow.cancel()
        XCTAssertFalse(flow.isPresented)
        route.release()
        await waitUntil { results.cards.first?.kind != .working }

        XCTAssertEqual(results.cards.count, 1)
        XCTAssertEqual(results.cards.first?.kind, .done(text: "Added Bananas", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertEqual(results.cards.first?.transcript, "add bananas")
        XCTAssertEqual(route.applied, 1)
        XCTAssertTrue(results.pendingRequests.isEmpty)
        XCTAssertEqual(time.ended.count, 1, "the background time is given back")
        XCTAssertTrue(time.openTokens.isEmpty)
        XCTAssertNil(flow.banner, "no banner for jess results")
    }

    func testTheRealShellAsksIOSForBackgroundTime() throws {
        let source = try String(contentsOf: backgroundRepoRoot.appending(path: "shell/Midas/JessResults.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("UIApplication.shared.beginBackgroundTask(withName:"))
        XCTAssertTrue(source.contains("UIApplication.shared.endBackgroundTask("))
        let services = try String(contentsOf: backgroundRepoRoot.appending(path: "shell/Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertTrue(services.contains("backgroundTime: SystemJessBackgroundTime()"))
        XCTAssertTrue(services.contains("voiceDependencies.route = submitToJess"))
    }
}

// MARK: - Exactly once when iOS stops Midas

@MainActor
final class JessResumeExactlyOnceTests: XCTestCase {
    func testAnAppliedRequestOnlyShowsItsCardOnTheNextOpenAndIsNeverRunAgain() async {
        let file = temporaryResultsFile()
        let firstRoute = HeldRoute(answers: [.done(text: "Added Milk", at: nil, allDay: nil, timeZone: "America/Los_Angeles")])
        firstRoute.hold = .afterApply
        let firstTime = StubBackgroundTime()
        let first = makeResults(file: file, route: firstRoute, time: firstTime, surroundings: Surroundings())
        _ = Submission(results: first, transcript: "add milk")
        await waitUntil { firstRoute.isHolding }
        XCTAssertEqual(firstRoute.applied, 1)
        XCTAssertNotNil(first.pendingRequests.first?.applied, "marked applied in the turn the ops were written")

        // iOS stops Midas here; the next open reads the same file
        let secondRoute = HeldRoute(answers: [.done(text: "Added Milk", at: nil, allDay: nil, timeZone: "America/Los_Angeles")])
        let second = makeResults(file: file, route: secondRoute, time: StubBackgroundTime(), surroundings: Surroundings())
        XCTAssertEqual(second.cards.first?.kind, .working, "the card waits on disk too")
        await second.resume()
        XCTAssertEqual(secondRoute.calls.count, 0, "never sent or applied again")
        XCTAssertEqual(second.cards.count, 1)
        XCTAssertEqual(second.cards.first?.kind, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertTrue(second.pendingRequests.isEmpty)
        await second.resume()
        XCTAssertEqual(secondRoute.calls.count, 0)
        XCTAssertEqual(second.cards.count, 1)
        firstRoute.release()
    }

    func testARequestStoppedBeforeTheAnswerIsSentAgainOnceWithItsOwnTimeAndZone() async {
        let file = temporaryResultsFile()
        let firstRoute = HeldRoute(answers: [])
        firstRoute.hold = .beforeAnswer
        let first = makeResults(file: file, route: firstRoute, time: StubBackgroundTime(), surroundings: Surroundings())
        _ = Submission(results: first, transcript: "remind me to call mom tomorrow at 9")
        await waitUntil { firstRoute.isHolding }

        let surroundings = Surroundings()
        surroundings.now = laterTime
        surroundings.zone = tokyoZone
        let secondRoute = HeldRoute(answers: [.done(text: "Added Call mom", at: "2026-10-21T16:00:00.000Z", allDay: false, timeZone: "America/Los_Angeles")])
        let second = makeResults(file: file, route: secondRoute, time: StubBackgroundTime(), surroundings: surroundings)
        await second.resume()
        await second.resume()

        XCTAssertEqual(secondRoute.calls.count, 1, "sent again exactly once")
        XCTAssertEqual(secondRoute.applied, 1)
        XCTAssertEqual(secondRoute.calls.first?.transcript, "remind me to call mom tomorrow at 9")
        XCTAssertEqual(secondRoute.calls.first?.saidAt, saidTime, "with the time it was said")
        XCTAssertEqual(secondRoute.calls.first?.timeZone, "America/Los_Angeles", "and the zone it was said in")
        XCTAssertEqual(second.cards.first?.kind, .done(text: "Added Call mom", at: "2026-10-21T16:00:00.000Z", allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertTrue(second.pendingRequests.isEmpty)
        firstRoute.release()
    }

    func testNothingIsResumedSignedOut() async {
        let file = temporaryResultsFile()
        let firstRoute = HeldRoute(answers: [])
        firstRoute.hold = .beforeAnswer
        let first = makeResults(file: file, route: firstRoute, time: StubBackgroundTime(), surroundings: Surroundings())
        _ = Submission(results: first, transcript: "add milk")
        await waitUntil { firstRoute.isHolding }
        let surroundings = Surroundings()
        surroundings.signedIn = false
        let secondRoute = HeldRoute(answers: [])
        let second = makeResults(file: file, route: secondRoute, time: StubBackgroundTime(), surroundings: surroundings)
        await second.resume()
        XCTAssertEqual(secondRoute.calls.count, 0)
        XCTAssertEqual(second.pendingRequests.count, 1)
        firstRoute.release()
    }

    func testWhenIOSEndsTheTimeEarlyALostAnswerIsNotNotDoneAndIsFinishedOnTheNextOpen() async {
        let route = HeldRoute(answers: [.notDone(transcript: "add milk"), .done(text: "Added Milk", at: nil, allDay: nil, timeZone: "America/Los_Angeles")])
        route.hold = .beforeAnswer
        let time = StubBackgroundTime()
        let surroundings = Surroundings()
        let results = makeResults(file: temporaryResultsFile(), route: route, time: time, surroundings: surroundings)
        let submission = Submission(results: results, transcript: "add milk")
        await waitUntil { route.isHolding }

        time.expireAll()
        XCTAssertEqual(time.ended.count, 1, "the time is given back when iOS asks")
        // The connection dropped while Midas was stopped: the router saw no answer
        route.release()
        await waitUntil { submission.isFinished }
        XCTAssertEqual(results.pendingRequests.count, 1, "kept, not recorded as Not Done")
        XCTAssertEqual(results.cards.first?.kind, .working)
        XCTAssertEqual(route.calls.count, 1)

        route.hold = .none
        surroundings.inForeground = true
        await results.resume()
        XCTAssertEqual(route.calls.count, 2)
        XCTAssertEqual(route.applied, 1)
        XCTAssertEqual(results.cards.first?.kind, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertTrue(results.pendingRequests.isEmpty)
        XCTAssertEqual(time.begun, 2)
        XCTAssertTrue(time.openTokens.isEmpty)
    }

    func testALostAnswerNoticedWithMidasBackOnScreenIsSentAgainAtOnce() async {
        let route = HeldRoute(answers: [.notDone(transcript: "add milk"), .done(text: "Added Milk", at: nil, allDay: nil, timeZone: "America/Los_Angeles")])
        route.hold = .beforeAnswer
        let time = StubBackgroundTime()
        let surroundings = Surroundings()
        let results = makeResults(file: temporaryResultsFile(), route: route, time: time, surroundings: surroundings)
        let submission = Submission(results: results, transcript: "add milk")
        await waitUntil { route.isHolding }
        time.expireAll()
        surroundings.inForeground = true
        route.hold = .none
        route.release()
        await waitUntil { submission.isFinished }
        XCTAssertEqual(route.calls.count, 2)
        XCTAssertEqual(route.applied, 1)
        XCTAssertEqual(results.cards.first?.kind, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertTrue(results.pendingRequests.isEmpty)
    }

    func testARealNotDoneWithTheTimeIntactIsRecordedAtOnce() async {
        let route = HeldRoute(answers: [.notDone(transcript: "what's the weather")])
        let results = makeResults(file: temporaryResultsFile(), route: route, time: StubBackgroundTime(), surroundings: Surroundings())
        await results.submit(transcript: "what's the weather", listenMs: 900)
        XCTAssertEqual(results.cards.first?.kind, .notDone)
        XCTAssertTrue(results.pendingRequests.isEmpty)
    }

    func testOpeningWhileARequestIsStillOnItsWayDoesNotSendItTwice() async {
        let route = HeldRoute(answers: [.done(text: "Added Milk", at: nil, allDay: nil, timeZone: "America/Los_Angeles")])
        route.hold = .beforeAnswer
        let results = makeResults(file: temporaryResultsFile(), route: route, time: StubBackgroundTime(), surroundings: Surroundings())
        let submission = Submission(results: results, transcript: "add milk")
        await waitUntil { route.isHolding }
        await results.resume()
        XCTAssertEqual(route.calls.count, 1)
        route.release()
        await waitUntil { submission.isFinished }
        await results.resume()
        XCTAssertEqual(route.calls.count, 1)
        XCTAssertEqual(route.applied, 1)
    }
}

// MARK: - Exactly once with the real router and the Reminders tools

/// POST /voice/jess answering from a list; the outcome report can hang, as when iOS stops Midas
/// after the ops are written.
private final class ReportHangingAPI: JessRouting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [JessRouteReply]
    private var sentRequests: [JessRouteRequest] = []
    private var hangingReports: [CheckedContinuation<Void, Never>] = []
    let hangsReports: Bool

    init(answers: [JessRouteReply], hangsReports: Bool) {
        self.answers = answers
        self.hangsReports = hangsReports
    }

    var requests: [JessRouteRequest] {
        lock.withLock { sentRequests }
    }

    var hangingCount: Int {
        lock.withLock { hangingReports.count }
    }

    func route(_ request: JessRouteRequest) async -> JessRouteReply {
        lock.withLock {
            sentRequests.append(request)
            return answers.isEmpty ? .unreachable : answers.removeFirst()
        }
    }

    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async {
        guard hangsReports else {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock {
                hangingReports.append(continuation)
            }
        }
    }

    func releaseReports() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let current = hangingReports
            hangingReports = []
            return current
        }
        for continuation in waiting {
            continuation.resume()
        }
    }
}

/// The records both "processes" share, as the phone's store would.
@MainActor
private final class SharedRecords {
    var records: [String: JSONValue] = [:]
    var writes = 0
}

@MainActor
private func makeRealRouter(api: ReportHangingAPI, shared: SharedRecords) -> JessRouter {
    func sidekicks() -> [JessSidekickSource] {
        [JessSidekickSource(id: "reminders", name: "Reminders", version: "v5", agent: .object([:]))]
    }
    func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
        let source = try String(contentsOf: backgroundRepoRoot.appending(path: "sidekicks/\(sidekickId)/tools.js"), encoding: .utf8)
        return try SidekickToolsEngine(source: source)
    }
    func storedRecords(sidekickId: String) -> [LocalRecord] {
        var found: [LocalRecord] = []
        for (key, value) in shared.records {
            found.append(LocalRecord(sidekickId: sidekickId, key: key, value: value))
        }
        return found
    }
    func apply(sidekickId: String, ops: [SidekickToolOp]) throws {
        shared.writes += 1
        for op in ops {
            switch op {
            case .set(let key, let value):
                shared.records[key] = value
            case .delete(let key):
                shared.records[key] = nil
            }
        }
    }
    func now() -> Date {
        laterTime
    }
    func timeZone() -> TimeZone {
        tokyoZone
    }
    func app() -> VoiceParseApp {
        VoiceParseApp(version: "0.1.0", build: "5", ios: "26.1", device: "iPhone17,1")
    }
    return JessRouter(dependencies: JessRouterDependencies(sidekicks: sidekicks, engine: engine, records: storedRecords, apply: apply, api: api, now: now, timeZone: timeZone, app: app))
}

@MainActor
private func makeResults(file: URL, router: JessRouter) -> JessResults {
    func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        await router.route(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone, onApplied: onApplied)
    }
    func isSignedIn() -> Bool {
        true
    }
    func isInForeground() -> Bool {
        false
    }
    func now() -> Date {
        saidTime
    }
    func timeZone() -> TimeZone {
        laZone
    }
    let dependencies = JessResultsDependencies(route: routeCall, backgroundTime: StubBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    return JessResults(file: JessResultsFile(fileURL: file), dependencies: dependencies)
}

@MainActor
final class JessRealRouterExactlyOnceTests: XCTestCase {
    func testStoppedAfterTheWriteTheNextOpenAddsNothingMore() async throws {
        let file = temporaryResultsFile()
        let shared = SharedRecords()
        let firstAPI = ReportHangingAPI(answers: [.done(sidekickId: "reminders", tool: "reminders.add", input: try JSONDecoder().decode(JSONValue.self, from: Data(milkInput.utf8)), logId: "l1")], hangsReports: true)
        let first = makeResults(file: file, router: makeRealRouter(api: firstAPI, shared: shared))
        _ = Submission(results: first, transcript: "add milk")
        await waitUntil { firstAPI.hangingCount == 1 }
        XCTAssertEqual(shared.records.count, 1)
        XCTAssertEqual(shared.writes, 1)

        let secondAPI = ReportHangingAPI(answers: [.done(sidekickId: "reminders", tool: "reminders.add", input: try JSONDecoder().decode(JSONValue.self, from: Data(milkInput.utf8)), logId: "l2")], hangsReports: false)
        let second = makeResults(file: file, router: makeRealRouter(api: secondAPI, shared: shared))
        await second.resume()
        XCTAssertEqual(secondAPI.requests.count, 0, "not sent again")
        XCTAssertEqual(shared.writes, 1, "never applied twice")
        XCTAssertEqual(shared.records.count, 1)
        XCTAssertEqual(second.cards.first?.kind, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        firstAPI.releaseReports()
    }

    func testTheRouterSendsTheTimeAndZoneTheRequestWasSaidIn() async throws {
        let shared = SharedRecords()
        let api = ReportHangingAPI(answers: [.done(sidekickId: "reminders", tool: "reminders.add", input: try JSONDecoder().decode(JSONValue.self, from: Data(milkInput.utf8)), logId: "l1")], hangsReports: false)
        let router = makeRealRouter(api: api, shared: shared)
        var appliedResults: [JessResult] = []
        func recordApplied(_ result: JessResult) {
            appliedResults.append(result)
            XCTAssertEqual(shared.writes, 1, "called right after the write")
        }
        let result = await router.route(transcript: "add milk", listenMs: 700, saidAt: saidTime, timeZone: laZone, onApplied: recordApplied)
        XCTAssertEqual(api.requests.first?.now, ReminderRecord.formatDate(saidTime))
        XCTAssertEqual(api.requests.first?.timeZone, "America/Los_Angeles")
        XCTAssertEqual(result, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertEqual(appliedResults, [result])

        // Without them: now and here, as before
        let plainAPI = ReportHangingAPI(answers: [.notDone(reason: "question")], hangsReports: false)
        _ = await makeRealRouter(api: plainAPI, shared: shared).route(transcript: "what's the weather", listenMs: 700)
        XCTAssertEqual(plainAPI.requests.first?.now, ReminderRecord.formatDate(laterTime))
        XCTAssertEqual(plainAPI.requests.first?.timeZone, "Asia/Tokyo")
    }
}

// MARK: - No iOS notification for jess

final class JessNoNotificationTests: XCTestCase {
    /// Only the reminder booking may post a system notification; nothing of jess's does.
    func testOnlyReminderBookingPostsSystemNotifications() throws {
        let shellFolder = backgroundRepoRoot.appending(path: "shell/Midas")
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: shellFolder.path())
        var posting: [String] = []
        for fileName in fileNames.sorted() where fileName.hasSuffix(".swift") {
            let source = try String(contentsOf: shellFolder.appending(path: fileName), encoding: .utf8)
            if source.contains("UNNotificationRequest(") || source.contains("UNMutableNotificationContent(") {
                posting.append(fileName)
            }
        }
        XCTAssertEqual(posting, ["NotificationBooking.swift"])
        let jessFiles = ["JessResults.swift", "JessRouter.swift", "JessRouterAPI.swift", "JessGrowFollowUp.swift", "VoiceReminderFlow.swift", "VoiceCaptureView.swift"]
        for fileName in jessFiles {
            let source = try String(contentsOf: shellFolder.appending(path: fileName), encoding: .utf8)
            XCTAssertFalse(source.contains("UserNotifications"), fileName)
            XCTAssertFalse(source.contains("UNUserNotificationCenter"), fileName)
        }
    }
}

// MARK: - The result cards

@MainActor
final class JessResultCardTests: XCTestCase {
    private func emptyResults(file: URL = temporaryResultsFile(), route: HeldRoute = HeldRoute(answers: [])) -> JessResults {
        makeResults(file: file, route: route, time: StubBackgroundTime(), surroundings: Surroundings())
    }

    func testEachStateHasItsCoreAndWords() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = laZone
        let usLocale = Locale(identifier: "en_US")
        let done = JessResultCard(id: UUID(), kind: .done(text: "Added Call mom", at: "2026-10-21T16:00:00.000Z", allDay: false, timeZone: "America/Los_Angeles"), transcript: "remind me to call mom tomorrow at 9", createdAt: saidTime)
        XCTAssertEqual(done.orbState, .added)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(done), "Added Call mom")
        let doneBody = VoiceReminderCopy.cardBody(done, now: saidTime, calendar: calendar, locale: usLocale)
        XCTAssertEqual(doneBody.replacingOccurrences(of: "\u{202F}", with: " "), "Tomorrow, 9:00 AM")
        XCTAssertNil(VoiceReminderCopy.cardActionTitle(done))

        let notDone = JessResultCard(id: UUID(), kind: .notDone, transcript: "move dentist to friday", createdAt: saidTime)
        XCTAssertEqual(notDone.orbState, .failed)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(notDone), "Not Done")
        XCTAssertEqual(VoiceReminderCopy.cardBody(notDone, now: saidTime, calendar: calendar, locale: usLocale), "“move dentist to friday”")
        XCTAssertEqual(VoiceReminderCopy.cardActionTitle(notDone), "Try Again")

        let repair = JessResultCard(id: UUID(), kind: .sentToRepair(sidekickName: "Reminders"), transcript: "make the reminders bigger", createdAt: saidTime)
        XCTAssertEqual(repair.orbState, .added)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(repair), "Sent to Edit")
        XCTAssertEqual(VoiceReminderCopy.cardBody(repair, now: saidTime, calendar: calendar, locale: usLocale), "Reminders")
        XCTAssertNil(VoiceReminderCopy.cardActionTitle(repair))

        let working = JessResultCard(id: UUID(), kind: .working, transcript: "add milk", createdAt: saidTime)
        XCTAssertEqual(working.orbState, .thinking)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(working), "Working…")
        XCTAssertNil(VoiceReminderCopy.cardActionTitle(working))

        // DESIGN.md §5a: green and red are the core's flat colours
        XCTAssertEqual(JessOrbPalette.light.coreColor(for: done.orbState), JessOrbColor(hex: 0x00873A))
        XCTAssertEqual(JessOrbPalette.light.coreColor(for: notDone.orbState), JessOrbColor(hex: 0xE00000))
    }

    func testResultsStackNewestFirstAndStayOnDiskUntilDismissed() async {
        let file = temporaryResultsFile()
        let results = emptyResults(file: file)
        results.present(.done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil))
        results.present(.notDone(transcript: "share my list with Sam"))
        results.present(.sentToRepair(sidekickName: "Reminders"))
        var kinds: [JessResultCard.Kind] = []
        for card in results.cards {
            kinds.append(card.kind)
        }
        XCTAssertEqual(kinds, [.sentToRepair(sidekickName: "Reminders"), .notDone, .done(text: "Added Milk", at: nil, allDay: false, timeZone: nil)])

        // Nothing leaves by itself
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(results.cards.count, 3)

        // A result that finished while Midas was closed shows on the next open
        let reopened = emptyResults(file: file)
        XCTAssertEqual(reopened.cards, results.cards)

        let notDoneId = reopened.cards[1].id
        reopened.dismiss(cardId: notDoneId)
        XCTAssertEqual(reopened.cards.count, 2)
        XCTAssertEqual(emptyResults(file: file).cards.count, 2, "the dismiss is kept")
    }

    func testAWorkingCardCannotBeDismissed() async {
        let route = HeldRoute(answers: [])
        route.hold = .beforeAnswer
        let results = emptyResults(route: route)
        _ = Submission(results: results, transcript: "add milk")
        await waitUntil { route.isHolding }
        let workingId = results.cards[0].id
        results.dismiss(cardId: workingId)
        XCTAssertEqual(results.cards.count, 1)
        route.release()
    }

    func testTryAgainSendsTheSameWordsAndTheCardShowsTheNewResultAtTheTop() async {
        let route = HeldRoute(answers: [.notDone(transcript: "move dentist to friday"), .done(text: "Moved Dentist", at: nil, allDay: nil, timeZone: "America/Los_Angeles")])
        let results = emptyResults(route: route)
        await results.submit(transcript: "move dentist to friday", listenMs: 900)
        results.present(.done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil))
        let notDoneCard = results.cards[1]
        XCTAssertEqual(notDoneCard.kind, .notDone)

        route.hold = .beforeAnswer
        results.retry(cardId: notDoneCard.id)
        XCTAssertEqual(results.cards[1].kind, .working)
        await waitUntil { route.isHolding }
        route.release()
        await waitUntil { results.cards.first?.id == notDoneCard.id }

        XCTAssertEqual(route.calls.count, 2)
        XCTAssertEqual(route.calls.last?.transcript, "move dentist to friday")
        XCTAssertEqual(results.cards.count, 2)
        XCTAssertEqual(results.cards.first?.kind, .done(text: "Moved Dentist", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
    }

    func testTheGrowFollowUpShowsItsResultAsACard() async {
        let results = emptyResults()
        let followUp = JessGrowFollowUp(api: OnePendingAPI(), present: results.present)
        await followUp.check()
        XCTAssertEqual(results.cards.first?.kind, .done(text: "Added Call the bank", at: nil, allDay: false, timeZone: nil))
        let services = try? String(contentsOf: backgroundRepoRoot.appending(path: "shell/Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertEqual(services?.contains("JessGrowFollowUp(api: jessAPI, present: jessResults.present)"), true)
    }

    func testTheCardAndTheStackRenderInBothModes() {
        let kinds: [JessResultCard.Kind] = [.working, .done(text: "Added Milk", at: nil, allDay: false, timeZone: nil), .notDone, .sentToRepair(sidekickName: "Reminders")]
        func ignore() {}
        for scheme in [ColorScheme.light, .dark] {
            for kind in kinds {
                let card = JessResultCard(id: UUID(), kind: kind, transcript: "add milk", createdAt: saidTime)
                let view = JessResultCardView(card: card, onRetry: ignore, onDismiss: ignore).frame(width: 393).environment(\.colorScheme, scheme)
                XCTAssertNotNil(ImageRenderer(content: view).uiImage, "\(kind) in \(scheme)")
            }
        }
    }

    func testTheHomePageShowsTheCardsAndFinishesStoppedRequestsOnOpen() throws {
        let app = try String(contentsOf: backgroundRepoRoot.appending(path: "shell/Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("JessResultCardStack(results: jessResults)"))
        XCTAssertTrue(app.contains("await ShellServices.shared.jessResults.resume()"))
        XCTAssertFalse(app.contains("notDoneCard"), "the separate Not Done card is replaced")
    }
}

/// GET /voice/jess/pending with one finished request.
private final class OnePendingAPI: JessPendingAPI, @unchecked Sendable {
    func pending() async -> [JessPendingItem]? {
        [JessPendingItem(id: "p1", sidekickId: "reminders", state: "done", text: "Added Call the bank", transcript: "add call the bank and flag it")]
    }

    func markShown(id: String) async {}
}

// MARK: - jess for everyone: the built-in tile

/// The widget is not redrawn in tests.
@Sendable
private func skipWidgetReload() {}

private final class ListedSidekicks: SidekickDirectoryFetching, @unchecked Sendable {
    let listings: [SidekickListing]

    init(listings: [SidekickListing]) {
        self.listings = listings
    }

    func fetchSidekicks() async throws -> [SidekickEntry] {
        var entries: [SidekickEntry] = []
        for listing in listings {
            entries.append(listing.entry)
        }
        return entries
    }

    func fetchListings() async throws -> [SidekickListing] {
        listings
    }
}

@MainActor
final class JessTileTests: XCTestCase {
    // The backend's JESS_LISTING (backend/src/jess-sidekick.ts) first, then a web Sidekick
    private let catalog = ##"{"sidekicks":[{"id":"jess","name":"jess","icon":{"symbol":"circle.circle.fill","background":"#000000"},"reads":[],"version":"built-in","builtIn":true},{"id":"reminders","name":"Reminders","icon":{"symbol":"checklist","background":"#FF9500"},"reads":[],"version":"v5","agent":{"description":"Reminders"}}]}"##

    private func directory() async throws -> SidekickDirectory {
        let listings = try RemoteSidekickDirectoryFetcher.listings(from: Data(catalog.utf8))
        let writer = SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: skipWidgetReload)
        let cacheURL = temporaryResultsFile().deletingLastPathComponent().appending(path: "directory.json")
        let directory = SidekickDirectory(cacheFileURL: cacheURL, fetcher: ListedSidekicks(listings: listings), sharedListWriter: writer)
        await directory.refresh()
        return directory
    }

    func testTheBuiltInListingIsATileWithNoToolsFirstOnTheGrid() async throws {
        let directory = try await directory()
        var ids: [String] = []
        for entry in SidekickHomeLayout.tiles(from: directory.entries) {
            ids.append(entry.id)
        }
        XCTAssertEqual(ids, ["jess", "reminders"])
        let jess = try XCTUnwrap(directory.entry(withId: "jess"))
        XCTAssertTrue(JessSidekick.isJess(jess))
        XCTAssertEqual(jess.version, "built-in")
        XCTAssertNil(directory.agent(forSidekickId: "jess"), "no tools: jess is never offered to itself")
        XCTAssertNil(directory.types(forSidekickId: "jess"))
        XCTAssertNotNil(directory.agent(forSidekickId: "reminders"))
    }

    func testOpeningJessShowsTheListeningScreenNotAPage() async throws {
        let router = SidekickRouter(directory: try await directory())
        var listeningOpened = 0
        func openListening() {
            listeningOpened += 1
        }
        router.openJess = openListening
        router.open(sidekickId: "jess")
        XCTAssertEqual(listeningOpened, 1)
        XCTAssertTrue(router.path.isEmpty, "no web page, nothing to repair")
        router.open(sidekickId: "reminders")
        XCTAssertEqual(router.path.first?.id, "reminders")
        XCTAssertEqual(listeningOpened, 1)
    }

    func testTheShellOpensTheSameScreenAsTheActionButton() throws {
        let services = try String(contentsOf: backgroundRepoRoot.appending(path: "shell/Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertTrue(services.contains("var openJess: @MainActor () -> Void = MidasApp.openVoiceReminder"))
        let app = try String(contentsOf: backgroundRepoRoot.appending(path: "shell/Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("SidekickHomeGrid(entries: directory.entries, onOpenJess: voice.request)"))
    }

    func testTheTileRendersInBothModes() throws {
        let jess = SidekickEntry(id: "jess", name: "jess", symbolName: "circle.circle.fill", backgroundHex: "#000000", version: "built-in")
        for scheme in [ColorScheme.light, .dark] {
            let view = SidekickHomeTile(sidekick: jess).environment(\.colorScheme, scheme)
            XCTAssertNotNil(ImageRenderer(content: view).uiImage)
        }
    }
}
