import XCTest
@testable import Midas

// The jess router on the phone (founder, 2026-10-21, phase 4): the Listening screen's sentence goes
// to POST /voice/jess with each Sidekick that has tools (its id and records summary; the server
// reads the tools from the manifest); a "done" runs that Sidekick's own
// tools.js handler on the records the phone holds and writes its ops through the shell writer;
// a refusal, a failed write, a tool of another Sidekick or no answer changes nothing and is
// "Not Done" with what was said; a repair is "Sent to Repair". Every result is one card at the top
// of the home page, never the banner (founder, 2026-10-22; cards: JessBackgroundTests.swift).

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let pacificZone = TimeZone(identifier: "America/Los_Angeles")!
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
private let fixedNow = ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!
private let usLocale = Locale(identifier: "en_US")

private func sidekickFile(_ sidekickId: String, _ fileName: String) throws -> String {
    try String(contentsOf: repoRoot.appending(path: "sidekicks/\(sidekickId)/\(fileName)"), encoding: .utf8)
}

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func agentBlock(_ sidekickId: String) throws -> JSONValue {
    let manifest = try json(try sidekickFile(sidekickId, "manifest.json"))
    return try XCTUnwrap(manifest["agent"])
}

private func gregorian() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = pacificZone
    return calendar
}

/// Waits for something the flow does on the main actor after an await.
@MainActor
private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Stands in for POST /voice/jess: answers from a list and keeps what the phone sent and reported.
private final class ScriptedJessAPI: JessRouting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [JessRouteReply]
    private var sentRequests: [JessRouteRequest] = []
    private var sentOutcomes: [(logId: String, outcome: JessPhoneOutcome)] = []

    init(answers: [JessRouteReply]) {
        self.answers = answers
    }

    var requests: [JessRouteRequest] {
        lock.withLock { sentRequests }
    }

    var outcomes: [JessPhoneOutcome] {
        lock.withLock {
            var reported: [JessPhoneOutcome] = []
            for sent in sentOutcomes {
                reported.append(sent.outcome)
            }
            return reported
        }
    }

    var outcomeLogIds: [String] {
        lock.withLock {
            var logIds: [String] = []
            for sent in sentOutcomes {
                logIds.append(sent.logId)
            }
            return logIds
        }
    }

    func route(_ request: JessRouteRequest) async -> JessRouteReply {
        lock.withLock {
            sentRequests.append(request)
            return answers.isEmpty ? .unreachable : answers.removeFirst()
        }
    }

    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async {
        lock.withLock {
            sentOutcomes.append((logId, outcome))
        }
    }
}

private struct ToolsMissing: Error {}

/// The router with the real Reminders tools.js and an in-memory record store.
@MainActor
private final class RouterHarness {
    let api: ScriptedJessAPI
    var records: [String: [String: JSONValue]] = [:]
    var appliedOps: [SidekickToolOp] = []
    var refuseWrites = false
    var sources: [JessSidekickSource] = []
    var brokenSidekicks: Set<String> = []
    var engineLoads: [String] = []
    private(set) var router: JessRouter!

    init(answers: [JessRouteReply]) throws {
        api = ScriptedJessAPI(answers: answers)
        sources = [
            JessSidekickSource(id: "reminders", name: "Reminders", version: "v5", agent: try agentBlock("reminders")),
            JessSidekickSource(id: "care-reminders", name: "Care", version: "c2", agent: try agentBlock("care-reminders")),
        ]
        router = JessRouter(dependencies: dependencies())
    }

    private func dependencies() -> JessRouterDependencies {
        func sidekicks() -> [JessSidekickSource] {
            sources
        }
        func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
            engineLoads.append(sidekickId + "@" + version)
            if brokenSidekicks.contains(sidekickId) {
                throw ToolsMissing()
            }
            return try SidekickToolsEngine(source: try sidekickFile(sidekickId, "tools.js"))
        }
        func storedRecords(sidekickId: String) -> [LocalRecord] {
            var found: [LocalRecord] = []
            for (key, value) in records[sidekickId] ?? [:] {
                found.append(LocalRecord(sidekickId: sidekickId, key: key, value: value))
            }
            return found
        }
        func apply(sidekickId: String, ops: [SidekickToolOp]) throws {
            if refuseWrites {
                throw RecordRefusal(reason: "reminder:x: value is over 65536 bytes")
            }
            var sidekickRecords = records[sidekickId] ?? [:]
            for op in ops {
                appliedOps.append(op)
                switch op {
                case .set(let key, let value):
                    sidekickRecords[key] = value
                case .delete(let key):
                    sidekickRecords[key] = nil
                }
            }
            records[sidekickId] = sidekickRecords
        }
        func now() -> Date {
            fixedNow
        }
        func timeZone() -> TimeZone {
            pacificZone
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "4", ios: "26.1", device: "iPhone17,1")
        }
        return JessRouterDependencies(sidekicks: sidekicks, engine: engine, records: storedRecords, apply: apply, api: api, now: now, timeZone: timeZone, app: app)
    }
}

@MainActor
final class JessRouterTests: XCTestCase {
    func testAnAddThenACompleteRunThroughTheSidekicksOwnHandlersAndAreReported() async throws {
        let addInput = try json(#"{"title":"Call Dad","notes":null,"list":null,"when":{"date":"2026-10-21","time":"18:00","allDay":false,"at":"2026-10-22T01:00:00.000Z","repeat":null,"timeZone":"America/Los_Angeles"}}"#)
        let completeInput = try json(#"{"item":"call dad"}"#)
        let harness = try RouterHarness(answers: [
            .done(sidekickId: "reminders", tool: "reminders.add", input: addInput, logId: "log-1"),
            .done(sidekickId: "reminders", tool: "reminders.complete", input: completeInput, logId: "log-2"),
        ])

        let added = await harness.router.route(transcript: "remind me to call dad tomorrow at 6pm", listenMs: 2100)
        XCTAssertEqual(added, .done(text: "Added Call Dad", at: "2026-10-22T01:00:00.000Z", allDay: false, timeZone: "America/Los_Angeles"))
        let stored = try XCTUnwrap(harness.records["reminders"])
        XCTAssertEqual(stored.count, 1)
        let reminder = try XCTUnwrap(stored.values.first)
        XCTAssertEqual(reminder["$type"], .string("reminders.item"))
        XCTAssertEqual(reminder["at"], .string("2026-10-22T01:00:00.000Z"))
        XCTAssertEqual(reminder["title"], .string("Call Dad"))

        let completed = await harness.router.route(transcript: "mark call dad as done", listenMs: 1500)
        XCTAssertEqual(completed, .done(text: "Marked done: Call Dad", at: nil, allDay: nil, timeZone: "America/Los_Angeles"))
        XCTAssertEqual(harness.api.outcomes, [.applied, .applied])
        XCTAssertEqual(harness.api.outcomeLogIds, ["log-1", "log-2"])

        // The second request carried the reminder the first one added, in the Sidekick's own summary
        let second = harness.api.requests[1]
        XCTAssertEqual(second.transcript, "mark call dad as done")
        XCTAssertEqual(second.timeZone, "America/Los_Angeles")
        XCTAssertEqual(second.listenMs, 1500)
        XCTAssertEqual(second.now, "2026-10-20T17:00:00.000Z")
        var sentIds: [String] = []
        for sidekick in second.sidekicks {
            sentIds.append(sidekick.id)
        }
        XCTAssertEqual(sentIds, ["reminders", "care-reminders"])
        let summary = String(decoding: try JSONEncoder().encode(second.sidekicks[0].context), as: UTF8.self)
        XCTAssertTrue(summary.contains("Call Dad"), summary)
        // The phone sends only each Sidekick's id and records summary; the server reads the tools
        // (jess router review, founder 2026-10-21, item 5)
        let sentPayload = try JSONEncoder().encode(second.sidekicks[0])
        let sentObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: sentPayload) as? [String: Any])
        XCTAssertEqual(sentObject.keys.sorted(), ["context", "id"])
    }

    func testARefusalChangesNothingAndIsReportedWithItsReason() async throws {
        let harness = try RouterHarness(answers: [.done(sidekickId: "reminders", tool: "reminders.complete", input: try json(#"{"item":"dentist"}"#), logId: "log-1")])
        let result = await harness.router.route(transcript: "mark the dentist done", listenMs: 900)
        XCTAssertEqual(result, .notDone(transcript: "mark the dentist done"))
        XCTAssertTrue(harness.appliedOps.isEmpty)
        XCTAssertEqual(harness.api.outcomes, [.refused(reason: "not-found")])
    }

    func testAWriteTheShellRefusesIsNotDoneAndReportedAsFailed() async throws {
        let harness = try RouterHarness(answers: [.done(sidekickId: "reminders", tool: "reminders.add", input: try json(#"{"title":"Milk","notes":null,"list":null,"when":null}"#), logId: "log-1")])
        harness.refuseWrites = true
        let result = await harness.router.route(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(result, .notDone(transcript: "add milk"))
        XCTAssertNil(harness.records["reminders"])
        XCTAssertEqual(harness.api.outcomes, [.failed(reason: "write-refused: reminder:x: value is over 65536 bytes")])
    }

    func testAToolOfAnotherSidekickOrAnUnknownSidekickIsNotRun() async throws {
        let input = try json(#"{"title":"Milk","notes":null,"list":null,"when":null}"#)
        let harness = try RouterHarness(answers: [
            .done(sidekickId: "reminders", tool: "care-reminders.add", input: input, logId: "log-1"),
            .done(sidekickId: "notes", tool: "notes.add", input: input, logId: "log-2"),
        ])
        let crossed = await harness.router.route(transcript: "add milk", listenMs: 900)
        let unknown = await harness.router.route(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(crossed, .notDone(transcript: "add milk"))
        XCTAssertEqual(unknown, .notDone(transcript: "add milk"))
        XCTAssertTrue(harness.appliedOps.isEmpty)
        XCTAssertEqual(harness.api.outcomes, [.failed(reason: "unknown-tool"), .failed(reason: "unknown-tool")])
    }

    func testARepairIsSentToRepairWithTheSidekicksName() async throws {
        let harness = try RouterHarness(answers: [.repair(sidekickId: "care-reminders", logId: "log-1")])
        let result = await harness.router.route(transcript: "make the care colours bigger", listenMs: 900)
        XCTAssertEqual(result, .sentToRepair(sidekickName: "Care"))
        XCTAssertTrue(harness.appliedOps.isEmpty)
        XCTAssertTrue(harness.api.outcomes.isEmpty)
    }

    func testNotDoneAndNoAnswerChangeNothing() async throws {
        let harness = try RouterHarness(answers: [.notDone(reason: "question"), .unreachable])
        let question = await harness.router.route(transcript: "what's the weather", listenMs: 900)
        let offline = await harness.router.route(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(question, .notDone(transcript: "what's the weather"))
        XCTAssertEqual(offline, .cutOff(transcript: "add milk"))
        XCTAssertTrue(harness.appliedOps.isEmpty)
        XCTAssertTrue(harness.api.outcomes.isEmpty)
    }

    func testASidekickWhoseToolsCannotLoadIsLeftOutAndWithNoneLeftNothingIsSent() async throws {
        let harness = try RouterHarness(answers: [.notDone(reason: "no-tool-fits")])
        harness.brokenSidekicks = ["care-reminders"]
        _ = await harness.router.route(transcript: "add milk", listenMs: 900)
        var sentIds: [String] = []
        for sidekick in harness.api.requests[0].sidekicks {
            sentIds.append(sidekick.id)
        }
        XCTAssertEqual(sentIds, ["reminders"])
        XCTAssertEqual(harness.engineLoads, ["reminders@v5", "care-reminders@c2"])

        harness.brokenSidekicks = ["reminders", "care-reminders"]
        let result = await harness.router.route(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(result, .notDone(transcript: "add milk"))
        XCTAssertEqual(harness.api.requests.count, 1)
    }

    func testTheVerbIsReadOnlyFromTheNamedSidekicksTools() {
        XCTAssertEqual(JessRouter.verb(of: "reminders.add", sidekickId: "reminders"), "add")
        XCTAssertEqual(JessRouter.verb(of: "care-reminders.add_list_alert", sidekickId: "care-reminders"), "add_list_alert")
        XCTAssertNil(JessRouter.verb(of: "care-reminders.add", sidekickId: "reminders"))
        XCTAssertNil(JessRouter.verb(of: "reminders.", sidekickId: "reminders"))
        XCTAssertNil(JessRouter.verb(of: "remindersadd", sidekickId: "reminders"))
    }
}

// MARK: - POST /voice/jess on the wire

final class RemoteJessRouterTests: XCTestCase {
    private func reply(_ status: Int, _ body: String) -> JessRouteReply {
        RemoteJessRouter.reply(statusCode: status, data: Data(body.utf8))
    }

    func testReadsDoneRepairAndNotDone() throws {
        XCTAssertEqual(reply(200, #"{"status":"done","sidekickId":"reminders","tool":"reminders.complete","input":{"item":"Call Mom"},"logId":"l1"}"#), .done(sidekickId: "reminders", tool: "reminders.complete", input: try json(#"{"item":"Call Mom"}"#), logId: "l1"))
        XCTAssertEqual(reply(200, #"{"status":"repair","sidekickId":"reminders","reportId":"r1","logId":"l2"}"#), .repair(sidekickId: "reminders", logId: "l2", reportId: "r1"))
        XCTAssertEqual(reply(200, #"{"status":"not-done","reason":"question","transcript":"x"}"#), .notDone(reason: "question"))
    }

    func testAnythingElseIsUnreachable() {
        XCTAssertEqual(reply(500, #"{"status":"done"}"#), .unreachable)
        XCTAssertEqual(reply(401, #"{"error":"sign in"}"#), .unreachable)
        XCTAssertEqual(reply(200, "not json"), .unreachable)
        XCTAssertEqual(reply(200, #"{"status":"done","sidekickId":"reminders"}"#), .unreachable)
        XCTAssertEqual(reply(200, #"{"status":"repair"}"#), .unreachable)
    }

    func testTheRequestIsAnAuthorizedJSONPost() throws {
        let origin = try XCTUnwrap(URL(string: "https://staging.example.com"))
        let request = try RemoteJessRouter.urlRequest(platformOrigin: origin, path: "voice/jess", body: ["transcript": "add milk"], token: "t1")
        XCTAssertEqual(request.url?.absoluteString, "https://staging.example.com/voice/jess")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, RemoteJessRouter.requestTimeout)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self), #"{"transcript":"add milk"}"#)
    }
}

// MARK: - The Listening screen with the router, and the home page card's words

/// Stands in for the shared transcriber: the test says words and ends listening.
@MainActor
private final class SpokenWords: VoiceTranscribing {
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

/// Stands in for the old parse call; with the router set it must never be asked.
private final class UnusedParser: VoiceReminderParsing, @unchecked Sendable {
    private let lock = NSLock()
    private var askedCount = 0

    var asked: Int {
        lock.withLock { askedCount }
    }

    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        lock.withLock {
            askedCount += 1
        }
        return .unreachable
    }
}

@MainActor
private final class RoutedFlowHarness {
    let transcriber = SpokenWords()
    let parser = UnusedParser()
    var routed: [(transcript: String, listenMs: Int)] = []
    var saved: [VoiceResolvedReminder] = []
    private(set) var flow: VoiceReminderFlow!

    init() {
        flow = VoiceReminderFlow(dependencies: dependencies())
    }

    private func dependencies() -> VoiceReminderDependencies {
        func isSignedIn() -> Bool {
            true
        }
        func lists() -> [VoiceReminderList] {
            []
        }
        func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing {
            transcriber
        }
        func save(_ reminder: VoiceResolvedReminder) throws {
            saved.append(reminder)
        }
        func now() -> Date {
            fixedNow
        }
        func timeZone() -> TimeZone {
            pacificZone
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "4", ios: "26.1", device: "iPhone17,1")
        }
        func route(transcript: String, listenMs: Int) async {
            routed.append((transcript, listenMs))
        }
        var dependencies = VoiceReminderDependencies(isSignedIn: isSignedIn, lists: lists, makeTranscriber: makeTranscriber, api: parser, save: save, now: now, timeZone: timeZone, app: app)
        dependencies.route = route
        return dependencies
    }

    func speak(_ text: String) async {
        flow.request()
        await flow.startListening()
        transcriber.say(text)
        transcriber.end(.silence)
    }
}

@MainActor
final class JessRoutedFlowTests: XCTestCase {
    func testWhatWasSaidGoesOnceToTheRouterAndTheWorkdeskStaysOpenWithNoBanner() async {
        let harness = RoutedFlowHarness()
        await harness.speak("add bananas to groceries")
        await waitFor { harness.flow.phase == .ready }
        XCTAssertEqual(harness.flow.phase, .ready)
        XCTAssertTrue(harness.flow.isPresented, "the Workdesk stays open; Done closes it")
        XCTAssertEqual(harness.routed.count, 1)
        XCTAssertEqual(harness.routed.first?.transcript, "add bananas to groceries")
        XCTAssertEqual(harness.parser.asked, 0)
        XCTAssertTrue(harness.saved.isEmpty)
        // A jess result is a home page card, never the banner (founder, 2026-10-22)
        XCTAssertNil(harness.flow.banner)
    }

    func testTheWordsFollowTheWritingRules() {
        let calendar = gregorian()
        let markedDone = JessResultCard(id: UUID(), kind: .done(text: "Marked done: Call Mom", at: nil, allDay: false, timeZone: nil), transcript: "call mom is done", createdAt: fixedNow)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(markedDone), "Marked done: Call Mom")
        let deleted = JessResultCard(id: UUID(), kind: .done(text: "Deleted Dentist", at: nil, allDay: false, timeZone: nil), transcript: "delete dentist", createdAt: fixedNow)
        XCTAssertEqual(VoiceReminderCopy.cardBody(deleted, now: fixedNow, calendar: calendar, locale: usLocale), "")

        let repair = JessResultCard(id: UUID(), kind: .sentToRepair(sidekickName: "Reminders"), transcript: "make the reminders bigger", createdAt: fixedNow)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(repair), "Sent to Repair")
        XCTAssertEqual(VoiceReminderCopy.cardBody(repair, now: fixedNow, calendar: calendar, locale: usLocale), "Reminders")
        XCTAssertNil(VoiceReminderCopy.cardActionTitle(repair))

        // A time set by the tool reads like the reminder banner's
        let reminder = VoiceResolvedReminder(title: "Call Dad", notes: nil, list: nil, date: "2026-10-21", time: "18:00", allDay: false, at: "2026-10-22T01:00:00.000Z", repeat: nil, timeZone: pacificZone.identifier)
        let added = JessResultCard(id: UUID(), kind: .done(text: "Added Call Dad", at: "2026-10-22T01:00:00.000Z", allDay: false, timeZone: pacificZone.identifier), transcript: "remind me to call dad tomorrow at 6pm", createdAt: fixedNow)
        let expected = VoiceReminderCopy.whenText(for: reminder, now: fixedNow, calendar: calendar, locale: usLocale)
        XCTAssertNotNil(expected)
        let addedBody = VoiceReminderCopy.cardBody(added, now: fixedNow, calendar: calendar, locale: usLocale)
        XCTAssertEqual(addedBody, expected)
        XCTAssertTrue(addedBody.hasPrefix("Tomorrow"))

        let notDone = JessResultCard(id: UUID(), kind: .notDone, transcript: "move dentist to friday", createdAt: fixedNow)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(notDone), "Not Done")
        XCTAssertEqual(VoiceReminderCopy.cardBody(notDone, now: fixedNow, calendar: calendar, locale: usLocale), "“move dentist to friday”")
        XCTAssertEqual(VoiceReminderCopy.cardActionTitle(notDone), "Try Again")
        let working = JessResultCard(id: UUID(), kind: .working, transcript: "x", createdAt: fixedNow)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(working), "Working…")
    }
}
