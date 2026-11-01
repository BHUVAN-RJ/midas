import CryptoKit
import WebKit
import XCTest
@testable import Midas

// Work log entries are links (founder, 2026-10-31; docs/mockups/jess-worklog-links-2026-10-31.html):
// a done card remembers the records its tool changed (new, edited, deleted, with the old value),
// a tap opens that Sidekick over jess at the first change, "Already Deleted" when it is gone, and
// the page gets the change once through the store channel and marks it (shell/sdk/midas-store.js).

private let linkTestsRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let linkTestsZone = TimeZone(identifier: "America/Los_Angeles")!
private let linkTestsNow = ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!

private func linkJSON(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func remindersFile(_ fileName: String) throws -> String {
    try String(contentsOf: linkTestsRoot.appending(path: "sidekicks/reminders/\(fileName)"), encoding: .utf8)
}

/// Answers POST /voice/jess from a list.
private final class LinkScriptedAPI: JessRouting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [JessRouteReply]

    init(answers: [JessRouteReply]) {
        self.answers = answers
    }

    func route(_ request: JessRouteRequest) async -> JessRouteReply {
        lock.withLock {
            answers.isEmpty ? .unreachable : answers.removeFirst()
        }
    }

    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async {}
}

/// The router with the real Reminders tools.js over an in-memory record set.
@MainActor
private final class LinkRouterHarness {
    var records: [String: JSONValue] = [:]
    private(set) var router: JessRouter!

    init(answers: [JessRouteReply]) throws {
        let manifest = try linkJSON(try remindersFile("manifest.json"))
        let agent = try XCTUnwrap(manifest["agent"])
        let source = JessSidekickSource(id: "reminders", name: "Reminders", version: "v5", agent: agent)
        let toolsSource = try remindersFile("tools.js")
        let api = LinkScriptedAPI(answers: answers)
        func sidekicks() -> [JessSidekickSource] {
            [source]
        }
        func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
            try SidekickToolsEngine(source: toolsSource)
        }
        func storedRecords(sidekickId: String) -> [LocalRecord] {
            var found: [LocalRecord] = []
            for (key, value) in self.records {
                found.append(LocalRecord(sidekickId: sidekickId, key: key, value: value))
            }
            return found
        }
        func apply(sidekickId: String, ops: [SidekickToolOp]) throws {
            for op in ops {
                switch op {
                case .set(let key, let value):
                    self.records[key] = value
                case .delete(let key):
                    self.records[key] = nil
                }
            }
        }
        func now() -> Date {
            linkTestsNow
        }
        func timeZone() -> TimeZone {
            linkTestsZone
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "4", ios: "26.1", device: "iPhone17,1")
        }
        let dependencies = JessRouterDependencies(sidekicks: sidekicks, engine: engine, records: storedRecords, apply: apply, api: api, now: now, timeZone: timeZone, app: app)
        router = JessRouter(dependencies: dependencies)
    }

    /// Routes one sentence inside a route context and gives back what the router left in it.
    func route(_ transcript: String) async -> (JessResult, JessChangeLink?) {
        let context = JessRouteContext(requestId: UUID().uuidString)
        let jessRouter = router!
        func routeInContext() async -> JessResult {
            await jessRouter.route(transcript: transcript, listenMs: 900)
        }
        let result = await JessRouteContext.$current.withValue(context, operation: routeInContext)
        return (result, context.changeLink)
    }
}

/// Background time that is never cut short.
@MainActor
private struct LinkBackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

private struct LinkScriptPageLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class LinkPageWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}

@MainActor
final class JessWorklogLinkTests: XCTestCase {
    private var temporaryFiles: [URL] = []

    override func tearDown() {
        for fileURL in temporaryFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
        temporaryFiles = []
        super.tearDown()
    }

    private func temporaryFile(_ name: String) -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString).json")
        temporaryFiles.append(fileURL)
        return fileURL
    }

    // MARK: Which records changed

    func testASetOnANewKeyIsNewASetOnAnExistingKeyIsAnEditAndADeleteKeepsTheOldValue() throws {
        let oldDentist = try linkJSON(#"{"title":"Dentist","at":"2026-11-05T18:00:00.000Z"}"#)
        let batteries = try linkJSON(#"{"title":"Buy batteries"}"#)
        let before = [
            LocalRecord(sidekickId: "reminders", key: "reminder:dentist", value: oldDentist),
            LocalRecord(sidekickId: "reminders", key: "reminder:batteries", value: batteries),
        ]
        let ops: [SidekickToolOp] = [
            .set(key: "reminder:mom", value: try linkJSON(#"{"title":"Call Mom"}"#)),
            .set(key: "reminder:dentist", value: try linkJSON(#"{"title":"Dentist","at":"2026-11-06T23:00:00.000Z"}"#)),
            .delete(key: "reminder:batteries"),
        ]
        let link = try XCTUnwrap(JessChangeLink.make(sidekickId: "reminders", ops: ops, recordsBefore: before))
        XCTAssertEqual(link.sidekickId, "reminders")
        XCTAssertEqual(link.changes, [
            JessChange(key: "reminder:mom", op: .new),
            JessChange(key: "reminder:dentist", op: .edit, before: oldDentist),
            JessChange(key: "reminder:batteries", op: .delete, before: batteries),
        ])
        XCTAssertEqual(link.first?.key, "reminder:mom")
    }

    func testNoOpsMakeNoLinkAndAKeyWrittenTwiceKeepsItsFirstMeaning() throws {
        XCTAssertNil(JessChangeLink.make(sidekickId: "reminders", ops: [], recordsBefore: []))
        let ops: [SidekickToolOp] = [
            .set(key: "list:groceries", value: try linkJSON(#"{"name":"Groceries"}"#)),
            .set(key: "list:groceries", value: try linkJSON(#"{"name":"Groceries","color":"orange"}"#)),
        ]
        let link = try XCTUnwrap(JessChangeLink.make(sidekickId: "reminders", ops: ops, recordsBefore: []))
        XCTAssertEqual(link.changes, [JessChange(key: "list:groceries", op: .new)])
    }

    // MARK: Where a tap opens

    func testATapOpensAtTheRecordOrSaysAlreadyDeletedWhenItIsGone() throws {
        let value = try linkJSON(#"{"title":"Call Mom"}"#)
        let newLink = JessChangeLink(sidekickId: "reminders", changes: [JessChange(key: "reminder:mom", op: .new)])
        func present(_ key: String) -> JSONValue? {
            value
        }
        func absent(_ key: String) -> JSONValue? {
            nil
        }
        XCTAssertEqual(newLink.target(currentValue: present), JessLinkTarget(sidekickId: "reminders", focus: JessChange(key: "reminder:mom", op: .new), isGone: false))
        XCTAssertEqual(newLink.target(currentValue: absent), JessLinkTarget(sidekickId: "reminders", focus: nil, isGone: true))

        let editLink = JessChangeLink(sidekickId: "reminders", changes: [JessChange(key: "reminder:dentist", op: .edit, before: value)])
        XCTAssertTrue(editLink.target(currentValue: absent).isGone)
        XCTAssertEqual(editLink.target(currentValue: present).focus?.op, .edit)

        // A deleted record is expected to be gone: its old row with Undo; back again, it is marked as it is
        let deleteLink = JessChangeLink(sidekickId: "reminders", changes: [JessChange(key: "reminder:batteries", op: .delete, before: value)])
        XCTAssertEqual(deleteLink.target(currentValue: absent), JessLinkTarget(sidekickId: "reminders", focus: JessChange(key: "reminder:batteries", op: .delete, before: value), isGone: false))
        XCTAssertEqual(deleteLink.target(currentValue: present), JessLinkTarget(sidekickId: "reminders", focus: JessChange(key: "reminder:batteries", op: .new), isGone: false))
    }

    // MARK: Which cards are links

    func testOnlyADoneCardWithAChangeOpensAndOnlyWhileItsWordsShow() throws {
        let link = JessChangeLink(sidekickId: "reminders", changes: [JessChange(key: "reminder:mom", op: .new)])
        var done = JessResultCard(id: UUID(), kind: .done(text: "Added Call Mom", at: nil, allDay: false, timeZone: nil), transcript: "call mom", createdAt: linkTestsNow)
        XCTAssertFalse(done.opensChange)
        done.link = link
        XCTAssertTrue(done.opensChange)

        // Repair and grow stay as they are (founder, 2026-10-31); Not Done changed nothing
        var repair = JessResultCard(id: UUID(), kind: .sentToRepair(sidekickName: "Reminders", link: nil), transcript: "make it bigger", createdAt: linkTestsNow)
        repair.link = link
        XCTAssertFalse(repair.opensChange)
        var notDone = JessResultCard(id: UUID(), kind: .notDone, transcript: "order the lamp", createdAt: linkTestsNow)
        notDone.link = link
        XCTAssertFalse(notDone.opensChange)

        let slots = JessWorkdeskLayout.slots
        XCTAssertTrue(JessWorkdeskLayout.tapOpens(done, slot: slots[0]))
        XCTAssertTrue(JessWorkdeskLayout.tapOpens(done, slot: slots[1]))
        XCTAssertTrue(JessWorkdeskLayout.tapOpens(done, slot: slots[2]))
        // A tucked card shows only its edge
        XCTAssertFalse(JessWorkdeskLayout.tapOpens(done, slot: slots[3]))
        XCTAssertFalse(JessWorkdeskLayout.tapOpens(done, slot: JessWorkdeskLayout.exit))
    }

    func testACardFromBeforeLinksStillLoadsAndALinkSurvivesTheFile() throws {
        let olderCard = #"{"id":"6F1A7C2E-1D2B-4F43-9C7E-2B1B3C4D5E6F","kind":{"notDone":{}},"transcript":"call mom","createdAt":0}"#
        let decoded = try JSONDecoder().decode(JessResultCard.self, from: Data(olderCard.utf8))
        XCTAssertNil(decoded.link)

        var card = JessResultCard(id: UUID(), kind: .done(text: "Deleted Buy batteries", at: nil, allDay: false, timeZone: nil), transcript: "delete buy batteries", createdAt: linkTestsNow)
        card.link = JessChangeLink(sidekickId: "reminders", changes: [JessChange(key: "reminder:batteries", op: .delete, before: try linkJSON(#"{"title":"Buy batteries"}"#))])
        let roundTripped = try JSONDecoder().decode(JessResultCard.self, from: try JSONEncoder().encode(card))
        XCTAssertEqual(roundTripped, card)
    }

    // MARK: The router and the Workdesk keep the link

    func testTheRouterLinksAnAddToANewRecordAndACompleteToAnEditOfIt() async throws {
        let addInput = try linkJSON(#"{"title":"Call Dad","notes":null,"list":null,"when":{"date":"2026-10-21","time":"18:00","allDay":false,"at":"2026-10-22T01:00:00.000Z","repeat":null,"timeZone":"America/Los_Angeles"}}"#)
        let completeInput = try linkJSON(#"{"item":"call dad"}"#)
        let refusedInput = try linkJSON(#"{"item":"dentist"}"#)
        let harness = try LinkRouterHarness(answers: [
            .done(sidekickId: "reminders", tool: "reminders.add", input: addInput, logId: "log-1"),
            .done(sidekickId: "reminders", tool: "reminders.complete", input: completeInput, logId: "log-2"),
            .done(sidekickId: "reminders", tool: "reminders.complete", input: refusedInput, logId: "log-3"),
        ])

        let (added, addLink) = await harness.route("remind me to call dad tomorrow at 6pm")
        XCTAssertEqual(added, .done(text: "Added Call Dad", at: "2026-10-22T01:00:00.000Z", allDay: false, timeZone: "America/Los_Angeles"))
        let reminderKey = try XCTUnwrap(harness.records.keys.first)
        XCTAssertEqual(addLink, JessChangeLink(sidekickId: "reminders", changes: [JessChange(key: reminderKey, op: .new)]))

        let beforeComplete = harness.records[reminderKey]
        let (_, completeLink) = await harness.route("mark call dad as done")
        let change = try XCTUnwrap(completeLink?.first)
        XCTAssertEqual(change.key, reminderKey)
        XCTAssertEqual(change.op, .edit)
        XCTAssertEqual(change.before, beforeComplete)

        // A refusal changed nothing, so it links nowhere
        let (refused, refusedLink) = await harness.route("mark the dentist done")
        XCTAssertEqual(refused, .notDone(transcript: "mark the dentist done"))
        XCTAssertNil(refusedLink)
    }

    func testTheWorkdeskCardOfADoneTaskCarriesItsLinkAndANotDoneCardDoesNot() async throws {
        let link = JessChangeLink(sidekickId: "reminders", changes: [JessChange(key: "reminder:mom", op: .new)])
        var answerDone = true
        func route(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
            guard answerDone else {
                return .notDone(transcript: transcript)
            }
            let done = JessResult.done(text: "Added Call Mom", at: nil, allDay: nil, timeZone: "America/Los_Angeles")
            JessRouteContext.current?.changeLink = link
            onApplied(done)
            return done
        }
        func yes() -> Bool {
            true
        }
        func now() -> Date {
            linkTestsNow
        }
        func zone() -> TimeZone {
            linkTestsZone
        }
        let dependencies = JessResultsDependencies(route: route, backgroundTime: LinkBackgroundTime(), isSignedIn: yes, isInForeground: yes, now: now, timeZone: zone, foregroundRetryDelay: nil)
        let fileURL = temporaryFile("jess-links")
        let results = JessResults(file: JessResultsFile(fileURL: fileURL), dependencies: dependencies)

        await results.submit(transcript: "remind me to call mom", listenMs: 900)
        XCTAssertEqual(results.log.first?.link, link)
        XCTAssertTrue(try XCTUnwrap(results.log.first).opensChange)

        // Kept on disk with the log
        let reloaded = JessResults(file: JessResultsFile(fileURL: fileURL), dependencies: dependencies)
        XCTAssertEqual(reloaded.log.first?.link, link)

        answerDone = false
        await results.submit(transcript: "order the lamp", listenMs: 900)
        XCTAssertEqual(results.log.first?.kind, .notDone)
        XCTAssertNil(results.log.first?.link)
    }

    // MARK: The page gets the change once

    func testTheStoreChannelGivesTheFocusOnceAndOnlyToItsSidekick() throws {
        let channel = SidekickStoreChannel(store: LocalRecordStore(fileURL: temporaryFile("focus-records")))
        let before = try linkJSON(#"{"title":"Dentist"}"#)
        channel.setFocus(JessChange(key: "reminder:dentist", op: .edit, before: before), sidekickId: "reminders")
        let ask = Data(#"{"op":"focus"}"#.utf8)

        XCTAssertEqual(channel.handle(sidekickId: "hydration", requestBody: ask).body["focus"], .null)
        let first = channel.handle(sidekickId: "reminders", requestBody: ask)
        XCTAssertEqual(first.statusCode, 200)
        XCTAssertEqual(first.body["focus"], .object(["key": .string("reminder:dentist"), "op": .string("edit"), "before": before]))
        XCTAssertEqual(channel.handle(sidekickId: "reminders", requestBody: ask).body["focus"], .null)
    }

    func testThePastedHelperReadsTheFocusAndMarksTheRecordUnderTheRealCSP() async throws {
        let sdkURL = linkTestsRoot.appending(path: "shell/sdk/midas-store.js")
        let script = try String(contentsOf: sdkURL, encoding: .utf8)
        let digest = SHA256.hash(data: Data(script.utf8))
        let scriptHash = "'sha256-\(Data(digest).base64EncodedString())'"
        let html = "<!doctype html><html><body><div style=\"height:3000px\"></div><div data-key=\"reminder:mom\">Call Mom</div><div style=\"height:3000px\"></div><script>\(script)</script></body></html>"
        let channel = SidekickStoreChannel(store: LocalRecordStore(fileURL: temporaryFile("mark-records")))
        channel.setFocus(JessChange(key: "reminder:mom", op: .new), sidekickId: "reminders")
        let loader = LinkScriptPageLoader(html: html, scriptHashes: [scriptHash])
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        webView.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let finished = expectation(description: "page loaded")
        let waiter = LinkPageWaiter(finished: finished)
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: "reminders")))
        await fulfillment(of: [finished], timeout: 10)

        let checkScript = """
        const focus = await store.focus();
        const row = document.querySelector('[data-key="reminder:mom"]');
        let animations = 0;
        for (let tries = 0; tries < 50 && animations === 0; tries += 1) {
          await new Promise(function waitABit(resolve) { setTimeout(resolve, 20); });
          animations = row.getAnimations().length;
        }
        const rowTop = row.getBoundingClientRect().top;
        return JSON.stringify({ key: focus.key, op: focus.op, animations: animations, onScreen: rowTop > 0 && rowTop < window.innerHeight });
        """
        let summary = try await webView.callAsyncJavaScript(checkScript, contentWorld: .page) as? String
        XCTAssertEqual(summary, #"{"key":"reminder:mom","op":"new","animations":1,"onScreen":true}"#)

        // Asked once: the page's own later call gets the same answer, the shell has nothing left
        let again = try await webView.callAsyncJavaScript("const focus = await store.focus(); return focus.key;", contentWorld: .page) as? String
        XCTAssertEqual(again, "reminder:mom")
        XCTAssertEqual(channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"focus"}"#.utf8)).body["focus"], .null)
        _ = waiter
    }
}
