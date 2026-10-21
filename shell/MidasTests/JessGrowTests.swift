import XCTest
@testable import Midas

// jess grows the Sidekick (founder 2026-10-21, docs/PRODUCT.md "jess grows the Sidekick"), on the
// phone: a "grow" reply shows "Sent to Repair"; the backend re-runs the request after the repair
// and the phone only pulls the records and shows the result once (the banner or the Not Done
// card). A "done" for a version the directory does not list yet runs only once the directory
// lists it, so RecordWriter stamps the ops with the version whose schemas the server checks.

private let growRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let growZone = TimeZone(identifier: "America/Los_Angeles")!
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
private let growNow = ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!

private func growJSON(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private final class GrowScriptedAPI: JessRouting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [JessRouteReply]
    private var sentOutcomes: [JessPhoneOutcome] = []

    init(answers: [JessRouteReply]) {
        self.answers = answers
    }

    var outcomes: [JessPhoneOutcome] {
        lock.withLock { sentOutcomes }
    }

    func route(_ request: JessRouteRequest) async -> JessRouteReply {
        lock.withLock {
            answers.isEmpty ? .unreachable : answers.removeFirst()
        }
    }

    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async {
        lock.withLock {
            sentOutcomes.append(outcome)
        }
    }
}

/// The router with the real Reminders tools.js and a directory that lists `listedVersion`.
@MainActor
private final class GrowRouterHarness {
    let api: GrowScriptedAPI
    var records: [String: JSONValue] = [:]
    var listedVersion = "v5"
    var versionAfterRefresh: String?
    var refreshes = 0
    private(set) var router: JessRouter!

    init(answers: [JessRouteReply]) {
        api = GrowScriptedAPI(answers: answers)
        router = JessRouter(dependencies: dependencies())
    }

    private func dependencies() -> JessRouterDependencies {
        func sidekicks() -> [JessSidekickSource] {
            [JessSidekickSource(id: "reminders", name: "Reminders", version: "v5", agent: .object([:]))]
        }
        func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
            let source = try String(contentsOf: growRepoRoot.appending(path: "sidekicks/\(sidekickId)/tools.js"), encoding: .utf8)
            return try SidekickToolsEngine(source: source)
        }
        func storedRecords(sidekickId: String) -> [LocalRecord] {
            var found: [LocalRecord] = []
            for (key, value) in records {
                found.append(LocalRecord(sidekickId: sidekickId, key: key, value: value))
            }
            return found
        }
        func apply(sidekickId: String, ops: [SidekickToolOp]) throws {
            for op in ops {
                switch op {
                case .set(let key, let value):
                    records[key] = value
                case .delete(let key):
                    records[key] = nil
                }
            }
        }
        func now() -> Date {
            growNow
        }
        func timeZone() -> TimeZone {
            growZone
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "4", ios: "26.1", device: "iPhone17,1")
        }
        func refreshDirectory() async {
            refreshes += 1
            if let versionAfterRefresh {
                listedVersion = versionAfterRefresh
            }
        }
        func directoryVersion(sidekickId: String) -> String? {
            listedVersion
        }
        return JessRouterDependencies(sidekicks: sidekicks, engine: engine, records: storedRecords, apply: apply, api: api, now: now, timeZone: timeZone, app: app, refreshDirectory: refreshDirectory, directoryVersion: directoryVersion)
    }
}

@MainActor
final class JessGrowRouterTests: XCTestCase {
    private let milk = #"{"title":"Milk","notes":null,"list":null,"when":null}"#

    func testAGrowReplyIsSentToRepairAndChangesNothing() async {
        let harness = GrowRouterHarness(answers: [.grow(sidekickId: "reminders", logId: "l1")])
        let result = await harness.router.route(transcript: "add milk and flag it", listenMs: 800)
        XCTAssertEqual(result, .sentToRepair(sidekickName: "Reminders"))
        XCTAssertTrue(harness.records.isEmpty)
        XCTAssertEqual(harness.api.outcomes, [])
    }

    func testTheServerSaysGrowWithTheSidekick() {
        let reply = RemoteJessRouter.reply(statusCode: 200, data: Data(#"{"status":"grow","sidekickId":"reminders","reportId":"r1","pendingId":"p1","logId":"l1"}"#.utf8))
        XCTAssertEqual(reply, .grow(sidekickId: "reminders", logId: "l1"))
        let withoutSidekick = RemoteJessRouter.reply(statusCode: 200, data: Data(#"{"status":"grow","logId":"l1"}"#.utf8))
        XCTAssertEqual(withoutSidekick, .unreachable)
    }

    func testANewerVersionRunsOnceTheDirectoryListsIt() async throws {
        let harness = GrowRouterHarness(answers: [.done(sidekickId: "reminders", version: "v6", tool: "reminders.add", input: try growJSON(milk), logId: "l1")])
        harness.versionAfterRefresh = "v6"
        let result = await harness.router.route(transcript: "add milk", listenMs: 800)
        XCTAssertEqual(result, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertEqual(harness.refreshes, 1)
        XCTAssertEqual(harness.records.count, 1)
        XCTAssertEqual(harness.api.outcomes, [.applied])
    }

    func testANewerVersionTheDirectoryDoesNotListWritesNothing() async throws {
        let harness = GrowRouterHarness(answers: [.done(sidekickId: "reminders", version: "v6", tool: "reminders.add", input: try growJSON(milk), logId: "l1")])
        let result = await harness.router.route(transcript: "add milk", listenMs: 800)
        XCTAssertEqual(result, .notDone(transcript: "add milk"))
        XCTAssertEqual(harness.refreshes, 1)
        XCTAssertTrue(harness.records.isEmpty)
        XCTAssertEqual(harness.api.outcomes, [.failed(reason: "version-changed")])
    }

    func testTheSameVersionDoesNotRefresh() async throws {
        let harness = GrowRouterHarness(answers: [.done(sidekickId: "reminders", version: "v5", tool: "reminders.add", input: try growJSON(milk), logId: "l1")])
        _ = await harness.router.route(transcript: "add milk", listenMs: 800)
        XCTAssertEqual(harness.refreshes, 0)
        XCTAssertEqual(harness.records.count, 1)
    }
}

/// GET /voice/jess/pending answers from a list; marks are kept.
private final class GrowPendingAPI: JessPendingAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [[JessPendingItem]?]
    private var marked: [String] = []
    private(set) var asked = 0

    init(answers: [[JessPendingItem]?]) {
        self.answers = answers
    }

    var shown: [String] {
        lock.withLock { marked }
    }

    func pending() async -> [JessPendingItem]? {
        lock.withLock {
            asked += 1
            return answers.isEmpty ? [] : answers.removeFirst()
        }
    }

    func markShown(id: String) async {
        lock.withLock {
            marked.append(id)
        }
    }
}

@MainActor
final class JessGrowFollowUpTests: XCTestCase {
    private let doneItem = JessPendingItem(id: "p1", sidekickId: "reminders", state: "done", text: "Added Call the bank", transcript: "add call the bank and flag it")
    private let failedItem = JessPendingItem(id: "p2", sidekickId: "reminders", state: "failed", text: nil, transcript: "share my groceries list with Sam")

    func testADoneRequestShowsItsLineAndAFailedOneTheCardEachMarkedShown() async {
        let api = GrowPendingAPI(answers: [[doneItem, failedItem]])
        var presented: [JessResult] = []
        func present(_ result: JessResult) {
            presented.append(result)
        }
        let followUp = JessGrowFollowUp(api: api, present: present)
        await followUp.check()
        XCTAssertEqual(presented, [.done(text: "Added Call the bank", at: nil, allDay: nil, timeZone: nil), .notDone(transcript: "share my groceries list with Sam")])
        XCTAssertEqual(api.shown, ["p1", "p2"])
    }

    func testNothingIsShownWhenTheServerCannotBeAsked() async {
        let api = GrowPendingAPI(answers: [nil])
        var presented: [JessResult] = []
        func present(_ result: JessResult) {
            presented.append(result)
        }
        await JessGrowFollowUp(api: api, present: present).check()
        XCTAssertEqual(presented, [])
        XCTAssertEqual(api.shown, [])
    }

    func testADoneWithoutALineShowsWhatWasSaid() {
        let noLine = JessPendingItem(id: "p3", sidekickId: "reminders", state: "done", text: nil, transcript: "add x")
        XCTAssertEqual(JessGrowFollowUp.result(for: noLine), .notDone(transcript: "add x"))
    }

    func testTheListDecodesAndAnErrorIsNil() {
        let data = Data(#"{"pending":[{"id":"p1","sidekickId":"reminders","state":"done","text":"Added Milk","transcript":"add milk"}]}"#.utf8)
        XCTAssertEqual(RemoteJessRouter.pendingItems(statusCode: 200, data: data), [JessPendingItem(id: "p1", sidekickId: "reminders", state: "done", text: "Added Milk", transcript: "add milk")])
        XCTAssertNil(RemoteJessRouter.pendingItems(statusCode: 401, data: data))
    }

    func testTheShellChecksAfterTheForegroundSync() throws {
        let app = try String(contentsOf: growRepoRoot.appending(path: "shell/Midas/MidasApp.swift"), encoding: .utf8)
        let sync = try XCTUnwrap(app.range(of: "await Self.syncIfSignedIn()"))
        let check = try XCTUnwrap(app.range(of: "await ShellServices.shared.jessGrowFollowUp.check()"))
        XCTAssertLessThan(sync.lowerBound, check.lowerBound)
    }
}
