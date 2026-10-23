import XCTest
@testable import Midas

// Founder decisions 2026-10-21 on the jess router review, on the phone: the intent, the App
// Shortcut and the control are titled "Ask jess" (Siri phrases and the ids a configured Action
// button points at unchanged); the phone sends each Sidekick's id and records summary only, and
// the server reads the tools; a "done" names the version it was checked against, and the phone
// runs that version's tools.js, loading it when it is not the one it had.

private let askRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let askZone = TimeZone(identifier: "America/Los_Angeles")!
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
private let askNow = ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!

private func askRepoFile(_ path: String) throws -> String {
    try String(contentsOf: askRepoRoot.appending(path: path), encoding: .utf8)
}

private func askJSON(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

final class AskJessTitleTests: XCTestCase {
    func testTheIntentIsTitledAskJess() {
        XCTAssertEqual(String(localized: StartVoiceReminderIntent.title), "Ask jess")
    }

    func testTheShortcutAndTheControlSayAskJessAndKeepTheirPhrasesAndIds() throws {
        let shortcuts = try askRepoFile("shell/Midas/MidasShortcuts.swift")
        XCTAssertTrue(shortcuts.contains(#"shortTitle: "Ask jess""#))
        XCTAssertTrue(shortcuts.contains(#""New reminder in \(.applicationName)","#))
        XCTAssertTrue(shortcuts.contains(#""Add a reminder in \(.applicationName)","#))
        XCTAssertTrue(shortcuts.contains(#""\(.applicationName) new reminder","#))
        XCTAssertTrue(shortcuts.contains("intent: StartVoiceReminderIntent()"))

        let control = try askRepoFile("shell/MidasWidgets/VoiceReminderControl.swift")
        XCTAssertTrue(control.contains(#"Label("Ask jess", image: JessSymbols.control)"#))
        XCTAssertTrue(control.contains(#".displayName("Ask jess")"#))
        XCTAssertTrue(control.contains(#"static let kind = "com.bhuvanrj.midas.new-reminder""#))

        for path in ["shell/Midas/MidasShortcuts.swift", "shell/MidasWidgets/VoiceReminderControl.swift"] {
            let source = try askRepoFile(path)
            XCTAssertFalse(source.contains(#""New Reminder""#), path)
        }
        let intent = try askRepoFile("shell/Shared/StartVoiceReminderIntent.swift")
        XCTAssertTrue(intent.contains(#"static let title: LocalizedStringResource = "Ask jess""#))
    }
}

/// Answers POST /voice/jess from a list and keeps what was reported.
private final class AskScriptedAPI: JessRouting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [JessRouteReply]
    private var sentRequests: [JessRouteRequest] = []
    private var sentOutcomes: [JessPhoneOutcome] = []

    init(answers: [JessRouteReply]) {
        self.answers = answers
    }

    var requests: [JessRouteRequest] {
        lock.withLock { sentRequests }
    }

    var outcomes: [JessPhoneOutcome] {
        lock.withLock { sentOutcomes }
    }

    func route(_ request: JessRouteRequest) async -> JessRouteReply {
        lock.withLock {
            sentRequests.append(request)
            return answers.isEmpty ? .unreachable : answers.removeFirst()
        }
    }

    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async {
        lock.withLock {
            sentOutcomes.append(outcome)
        }
    }
}

private struct AskToolsMissing: Error {}

/// The router with the real Reminders tools.js; versions in `missingVersions` fail to load.
@MainActor
private final class AskRouterHarness {
    let api: AskScriptedAPI
    var records: [String: JSONValue] = [:]
    var engineLoads: [String] = []
    var missingVersions: Set<String> = []
    private(set) var router: JessRouter!

    init(answers: [JessRouteReply]) {
        api = AskScriptedAPI(answers: answers)
        router = JessRouter(dependencies: dependencies())
    }

    private func dependencies() -> JessRouterDependencies {
        func sidekicks() -> [JessSidekickSource] {
            [JessSidekickSource(id: "reminders", name: "Reminders", version: "v5", agent: .object([:]))]
        }
        func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
            engineLoads.append(sidekickId + "@" + version)
            if missingVersions.contains(version) {
                throw AskToolsMissing()
            }
            return try SidekickToolsEngine(source: try askRepoFile("sidekicks/\(sidekickId)/tools.js"))
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
            askNow
        }
        func timeZone() -> TimeZone {
            askZone
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "4", ios: "26.1", device: "iPhone17,1")
        }
        return JessRouterDependencies(sidekicks: sidekicks, engine: engine, records: storedRecords, apply: apply, api: api, now: now, timeZone: timeZone, app: app)
    }
}

@MainActor
final class JessServerToolsTests: XCTestCase {
    private let milk = #"{"title":"Milk","notes":null,"list":null,"when":null}"#

    func testThePhoneSendsOnlyEachSidekicksIdAndRecordsSummary() async throws {
        let harness = AskRouterHarness(answers: [.notDone(reason: "question")])
        _ = await harness.router.route(transcript: "what's due", listenMs: 800)
        let request = try XCTUnwrap(harness.api.requests.first)
        let encoded = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let sidekicks = try XCTUnwrap(body["sidekicks"] as? [[String: Any]])
        XCTAssertEqual(sidekicks.count, 1)
        XCTAssertEqual(sidekicks[0].keys.sorted(), ["context", "id"])
        XCTAssertEqual(sidekicks[0]["id"] as? String, "reminders")
    }

    func testADoneForTheVersionThePhoneHasRunsWithoutLoadingAgain() async throws {
        let harness = AskRouterHarness(answers: [.done(sidekickId: "reminders", version: "v5", tool: "reminders.add", input: try askJSON(milk), logId: "l1")])
        let result = await harness.router.route(transcript: "add milk", listenMs: 800)
        XCTAssertEqual(result, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertEqual(harness.engineLoads, ["reminders@v5"])
        XCTAssertEqual(harness.api.outcomes, [.applied])
    }

    func testADoneForANewerVersionRunsThatVersionsTools() async throws {
        let harness = AskRouterHarness(answers: [.done(sidekickId: "reminders", version: "v6", tool: "reminders.add", input: try askJSON(milk), logId: "l1")])
        let result = await harness.router.route(transcript: "add milk", listenMs: 800)
        XCTAssertEqual(result, .done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles"))
        XCTAssertEqual(harness.engineLoads, ["reminders@v5", "reminders@v6"])
        XCTAssertEqual(harness.records.count, 1)
    }

    func testANewerVersionWhoseToolsCannotLoadChangesNothingAndIsReported() async throws {
        let harness = AskRouterHarness(answers: [.done(sidekickId: "reminders", version: "v6", tool: "reminders.add", input: try askJSON(milk), logId: "l1")])
        harness.missingVersions = ["v6"]
        let result = await harness.router.route(transcript: "add milk", listenMs: 800)
        XCTAssertEqual(result, .notDone(transcript: "add milk"))
        XCTAssertTrue(harness.records.isEmpty)
        XCTAssertEqual(harness.api.outcomes, [.failed(reason: "version-changed")])
    }

    func testTheReplyCarriesTheVersionWhenTheServerSendsIt() throws {
        let withVersion = RemoteJessRouter.reply(statusCode: 200, data: Data(#"{"status":"done","sidekickId":"reminders","version":"u9","tool":"reminders.complete","input":{"item":"Call Mom"},"logId":"l1"}"#.utf8))
        XCTAssertEqual(withVersion, .done(sidekickId: "reminders", version: "u9", tool: "reminders.complete", input: try askJSON(#"{"item":"Call Mom"}"#), logId: "l1"))
        let without = RemoteJessRouter.reply(statusCode: 200, data: Data(#"{"status":"done","sidekickId":"reminders","tool":"reminders.complete","input":{"item":"Call Mom"},"logId":"l1"}"#.utf8))
        XCTAssertEqual(without, .done(sidekickId: "reminders", version: nil, tool: "reminders.complete", input: try askJSON(#"{"item":"Call Mom"}"#), logId: "l1"))
    }
}
