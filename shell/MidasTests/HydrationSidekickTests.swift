import CryptoKit
import WebKit
import XCTest
@testable import Midas

// The Water Sidekick (`sidekicks/hydration/`, docs/briefs/hydration-sidekick.md section 2.3) on the
// phone: the real page in a real WKWebView under the real CSP, writing through the scheme handler
// into a store whose write gate checks every record against the Sidekick's manifest and whose
// channel runs the shell's reminder and widget checks; and its tools.js in JavaScriptCore, with
// every op going through RecordWriter as jess's tools do.

private let hydrationRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
// Sunday Oct 25, 2026, 12:30 in Los Angeles
private let hydrationNowText = "2026-10-25T19:30:00.000Z"

private struct HydrationBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class HydrationPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

@MainActor
final class HydrationSidekickTests: XCTestCase {
    private static let sidekickId = "hydration"
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "hydration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    // MARK: Files and the store

    private func sidekickFile(_ fileName: String) throws -> String {
        try String(contentsOf: hydrationRepoRoot.appending(path: "sidekicks/hydration/\(fileName)"), encoding: .utf8)
    }

    private func manifest() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(try sidekickFile("manifest.json").utf8))
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// A store whose write gate checks every record against the real manifest types (and the
    /// shell's own types for `widget:`).
    private func makeGatedStore() throws -> LocalRecordStore {
        let engine = try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
        let types = try manifest()["types"]
        let store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        func typesFor(requestedSidekickId: String) -> JSONValue? {
            requestedSidekickId == Self.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: typesFor)
        return store
    }

    private var now: Date {
        ReminderRecord.parseDate(.string(hydrationNowText))!
    }

    /// The phone's local date of a moment, as the page and the tools name a day.
    private func dayKey(_ moment: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.year, .month, .day], from: moment)
        return String(format: "water:%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    // MARK: Loading the page

    /// The CSP hash of each inline script, computed the way the deploy script does.
    private func inlineScriptHashes(in html: String) -> [String] {
        var hashes: [String] = []
        var searchStart = html.startIndex
        while let openRange = html.range(of: "<script>", range: searchStart..<html.endIndex),
              let closeRange = html.range(of: "</script>", range: openRange.upperBound..<html.endIndex) {
            let scriptText = String(html[openRange.upperBound..<closeRange.lowerBound])
            let digest = SHA256.hash(data: Data(scriptText.utf8))
            hashes.append("'sha256-\(Data(digest).base64EncodedString())'")
            searchStart = closeRange.upperBound
        }
        return hashes
    }

    private func loadPage(store: LocalRecordStore, validators: [String: ReservedRecordValidator] = ShellServices.reservedRecordValidators) async throws -> (WKWebView, HydrationPageWaiter) {
        let html = try sidekickFile("index.html")
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = HydrationBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = HydrationPageWaiter()
        let finished = expectation(description: "water page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: Self.sidekickId)))
        // The first page of a run starts the web content process, which can take over ten seconds
        await fulfillment(of: [finished], timeout: 30)
        let probe = """
        if (typeof WaterApp !== 'object' || typeof WaterLogic !== 'object' || typeof store !== 'object') { return 'script did not run'; }
        await WaterApp.whenReady();
        return 'ready';
        """
        let outcome = try await webView.callAsyncJavaScript(probe, contentWorld: .page) as? String
        XCTAssertEqual(outcome, "ready", "the page's script did not run under the CSP")
        return (webView, waiter)
    }

    private func runScript(_ webView: WKWebView, _ script: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(script, contentWorld: .page)
        return try XCTUnwrap(result as? String, "the script returned no text")
    }

    /// textContent, not innerText: innerText needs layout and this web view has no window
    private func renderedText(_ webView: WKWebView) async throws -> String {
        try await runScript(webView, "return document.getElementById('main').textContent;")
    }

    private func start(_ webView: WKWebView, goalMl: Int, unit: String) async throws {
        _ = try await runScript(webView, "await WaterApp.start({ goalMl: \(goalMl), unit: '\(unit)' }); return 'started';")
    }

    private func buttonTitles(_ widget: JSONValue?) -> [String] {
        var titles: [String] = []
        collectButtonTitles(widget, into: &titles)
        return titles
    }

    private func collectButtonTitles(_ value: JSONValue?, into titles: inout [String]) {
        guard let value else {
            return
        }
        switch value {
        case .object(let fields):
            if case .string(let title)? = fields["button"] {
                titles.append(title)
            }
            for key in fields.keys.sorted() {
                collectButtonTitles(fields[key], into: &titles)
            }
        case .array(let elements):
            for element in elements {
                collectButtonTitles(element, into: &titles)
            }
        default:
            return
        }
    }

    // MARK: The page

    func testFirstOpenRunsUnderTheRealContentSecurityPolicyAndWritesNothing() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)
        let rendered = try await renderedText(webView)
        XCTAssertTrue(rendered.contains("Daily Goal"), rendered)
        XCTAssertTrue(rendered.contains("Start"), rendered)
        XCTAssertTrue(rendered.contains("2,500 ml"), "the goal wheel does not start at 2,500 ml: \(rendered)")
        XCTAssertEqual(store.query(sidekickId: Self.sidekickId, keyPrefix: ""), [], "first open wrote records before Start")
        _ = waiter
    }

    func testStartWritesTypedSettingsTheReminderAndTheOneTideWidget() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)
        try await start(webView, goalMl: 3000, unit: "l")

        let settings = store.get(sidekickId: Self.sidekickId, key: "settings:main")
        XCTAssertEqual(settings?["$type"], .string("hydration.settings"))
        XCTAssertEqual(settings?["goalMl"], .number(3000))
        XCTAssertEqual(settings?["unit"], .string("l"))
        XCTAssertEqual(settings?["presetsMl"], .array([.number(250), .number(500), .number(750)]))
        XCTAssertEqual(settings?["remindersOn"], .bool(true))
        XCTAssertEqual(settings?["remindStart"], .string("09:00"))
        XCTAssertEqual(settings?["remindEnd"], .string("21:00"))
        XCTAssertEqual(settings?["everyHours"], .number(2))

        let reminderValue = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:water"))
        XCTAssertEqual(reminderValue["$type"], .string("hydration.reminder"))
        XCTAssertNotNil(ReminderRecord.parse(sidekickId: Self.sidekickId, key: "reminder:water", value: reminderValue), "the engine cannot read reminder:water")
        XCTAssertEqual(reminderValue["everyHours"], .number(2))
        XCTAssertEqual(reminderValue["endTime"], .string("21:00"))
        XCTAssertEqual(reminderValue["done"], .bool(false))
        XCTAssertEqual(reminderValue["listen"], try json(#"{"key":"water:{today}","field":"ml","goal":"settings:main.goalMl","dayGoalField":"goalMl","quietMinutes":45}"#))

        // One Water widget (founder, 2026-10-27, docs/PRODUCT.md "One Water widget")
        for key in ["widget:today"] {
            let widget = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key), "\(key) was not written")
            XCTAssertEqual(widget["$type"], .string("midas.widget"), key)
            XCTAssertNil(SidekickWidgetDescription.validationError(widget), key)
            // Sand by day, the night Tide in dark mode (founder, 2026-10-27: light and dark for every widget)
            XCTAssertEqual(widget["background"], .object(["light": .string("#F4EEE3"), "dark": .string("#0E1A1E")]), "\(key) is not the Tide widget")
        }
        XCTAssertNil(store.get(sidekickId: Self.sidekickId, key: "widget:week"), "widget:week is retired")
        // Walked large, medium, small (keys sorted): three, three, one
        XCTAssertEqual(buttonTitles(store.get(sidekickId: Self.sidekickId, key: "widget:today")),
                       ["+0.25 L", "+0.5 L", "+0.75 L", "+0.25 L", "+0.5 L", "+0.75 L", "+0.25 L"])

        let rendered = try await renderedText(webView)
        XCTAssertTrue(rendered.contains("of 3 L"), rendered)
        XCTAssertTrue(rendered.contains("+0.25 L"), rendered)
        _ = waiter
    }

    func testAShellThatRefusesTheTidePiecesGetsThePlainWidget() async throws {
        let store = try makeGatedStore()
        func refuseFill(_ value: JSONValue) -> String? {
            let text = String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self)
            if text.contains("\"fill\"") {
                return "small: unknown piece fill"
            }
            return SidekickWidgetDescription.validationError(value)
        }
        var validators = ShellServices.reservedRecordValidators
        validators[SidekickWidgetShared.recordPrefix] = refuseFill
        let (webView, waiter) = try await loadPage(store: store, validators: validators)
        try await start(webView, goalMl: 2500, unit: "ml")
        for key in ["widget:today"] {
            let widget = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key), "no plain \(key)")
            XCTAssertNil(SidekickWidgetDescription.validationError(widget), key)
            XCTAssertNil(widget["background"], "\(key) is not the plain one")
            XCTAssertNotNil(widget["medium"]?["hstack"]?.arrayValue?.first?["ring"], "\(key) has no ring")
        }
        XCTAssertNil(store.get(sidekickId: Self.sidekickId, key: "widget:week"), "widget:week is retired")
        XCTAssertNotNil(store.get(sidekickId: Self.sidekickId, key: "settings:main"), "the page stopped when a widget was refused")
        _ = waiter
    }

    func testLoggingAddsToTodayAndUndoTakesItBack() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)
        try await start(webView, goalMl: 2500, unit: "ml")
        let key = try await runScript(webView, "await WaterApp.log(250); return WaterLogic.dayKey(Date.now());")
        XCTAssertEqual(key, dayKey(Date()))
        let logged = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        XCTAssertEqual(logged["$type"], .string("hydration.day"))
        XCTAssertEqual(logged["ml"], .number(250))
        XCTAssertEqual(logged["goalMl"], .number(2500))
        XCTAssertEqual(logged["entries"]?.arrayValue?.count, 1)
        let rendered = try await renderedText(webView)
        XCTAssertTrue(rendered.contains("Added 250 ml"), rendered)
        XCTAssertTrue(rendered.contains("Undo"), rendered)

        _ = try await runScript(webView, "await WaterApp.undo(); return 'undone';")
        let undone = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        XCTAssertEqual(undone["ml"], .number(0))
        XCTAssertEqual(undone["entries"], .array([]))
        _ = waiter
    }

    func testAWidgetTapStartsTheDayThroughTheWriterAndShowsAsFromWidget() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)
        try await start(webView, goalMl: 2500, unit: "ml")
        let key = dayKey(Date())
        // What the shell writes for a widget increment on a day with no record yet
        try RecordWriter(store: store).update(sidekickId: Self.sidekickId, key: key, patch: try json(#"{"ml":500}"#))
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: key)?["$type"], .string("hydration.day"))

        let rendered = try await runScript(webView, "await WaterApp.refresh(); WaterApp.show('log'); return document.getElementById('main').textContent;")
        XCTAssertTrue(rendered.contains("From widget"), rendered)
        XCTAssertTrue(rendered.contains("500 ml"), rendered)

        _ = try await runScript(webView, "await WaterApp.log(250); return 'logged';")
        let day = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        XCTAssertEqual(day["ml"], .number(750), "the page wrote over the widget's ml")
        _ = waiter
    }

    func testChangingTheUnitRewritesSettingsAndWidgets() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)
        try await start(webView, goalMl: 2500, unit: "ml")
        _ = try await runScript(webView, "await WaterApp.setUnit('oz'); return 'changed';")
        let settings = store.get(sidekickId: Self.sidekickId, key: "settings:main")
        XCTAssertEqual(settings?["unit"], .string("oz"))
        XCTAssertEqual(settings?["presetsMl"], .array([.number(237), .number(473), .number(710)]))
        // Walked large, medium, small (keys sorted): three, three, one
        XCTAssertEqual(buttonTitles(store.get(sidekickId: Self.sidekickId, key: "widget:today")),
                       ["+8 oz", "+16 oz", "+24 oz", "+8 oz", "+16 oz", "+24 oz", "+8 oz"])
        _ = waiter
    }

    func testTheBundleUsesNoBrowserStorage() throws {
        let html = try sidekickFile("index.html")
        XCTAssertFalse(html.contains("localStorage"))
        XCTAssertFalse(html.contains("indexedDB"))
        XCTAssertFalse(html.contains("sessionStorage"))
    }

    // MARK: The tools in JavaScriptCore

    private func seededToolsStore(unit: String = "ml") throws -> LocalRecordStore {
        let store = try makeGatedStore()
        let settings = try json(#"{"goalMl":2500,"unit":"\#(unit)","presetsMl":[250,500,750],"remindStart":"09:00","remindEnd":"21:00","everyHours":2,"remindersOn":true,"createdAt":"2026-10-01T00:00:00.000Z"}"#)
        try store.set(sidekickId: Self.sidekickId, key: "settings:main", value: settings)
        return store
    }

    private func toolsEngine() throws -> SidekickToolsEngine {
        try SidekickToolsEngine(source: try sidekickFile("tools.js"))
    }

    func testToolsLoadInJavaScriptCoreWithAHandlerForEveryTool() throws {
        guard case .array(let tools)? = try manifest()["agent"]?["tools"] else {
            return XCTFail("no agent tools in manifest.json")
        }
        var verbs: [String] = []
        for tool in tools {
            if case .string(let name)? = tool["name"] {
                verbs.append(String(name.dropFirst("hydration.".count)))
            }
        }
        XCTAssertEqual(try toolsEngine().handlerNames(), verbs.sorted())
        XCTAssertEqual(verbs.sorted(), ["log", "set_goal", "set_reminders", "set_unit", "today", "undo"])
    }

    func testLogRunsInJavaScriptCoreAndItsRecordPassesTheWriteGate() throws {
        let store = try seededToolsStore()
        let engine = try toolsEngine()
        let records = store.query(sidekickId: Self.sidekickId, keyPrefix: "")
        let result = try engine.run(verb: "log", input: try json(#"{"amount":500,"unit":"ml"}"#), records: records, now: now)
        XCTAssertEqual(result.text, "Added 500 ml")
        guard case .changes(let ops) = result.outcome else {
            return XCTFail("expected changes, got \(result.outcome)")
        }
        try RecordWriter(store: store).apply(sidekickId: Self.sidekickId, ops: ops)
        let day = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: dayKey(now)))
        XCTAssertEqual(day["$type"], .string("hydration.day"))
        XCTAssertEqual(day["ml"], .number(500))
        XCTAssertEqual(day["entries"]?.arrayValue?.first?["at"], .string(hydrationNowText))

        let undo = try engine.run(verb: "undo", input: .object([:]), records: store.query(sidekickId: Self.sidekickId, keyPrefix: ""), now: now)
        XCTAssertEqual(undo.text, "Removed 500 ml")
        guard case .changes(let undoOps) = undo.outcome else {
            return XCTFail("expected changes, got \(undo.outcome)")
        }
        try RecordWriter(store: store).apply(sidekickId: Self.sidekickId, ops: undoOps)
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: dayKey(now))?["ml"], .number(0))
    }

    func testSetRemindersWritesAReminderTheEngineReads() throws {
        let store = try seededToolsStore()
        let engine = try toolsEngine()
        let input = try json(#"{"on":null,"from":"08:00","to":"20:00","everyHours":3}"#)
        let result = try engine.run(verb: "set_reminders", input: input, records: store.query(sidekickId: Self.sidekickId, keyPrefix: ""), now: now)
        guard case .changes(let ops) = result.outcome else {
            return XCTFail("expected changes, got \(result.outcome)")
        }
        try RecordWriter(store: store).apply(sidekickId: Self.sidekickId, ops: ops)
        let reminderValue = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:water"))
        XCTAssertNotNil(ReminderRecord.parse(sidekickId: Self.sidekickId, key: "reminder:water", value: reminderValue))
        XCTAssertEqual(reminderValue["$type"], .string("hydration.reminder"))
        XCTAssertEqual(reminderValue["endTime"], .string("20:00"))
        XCTAssertEqual(reminderValue["everyHours"], .number(3))
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "settings:main")?["remindStart"], .string("08:00"))

        let off = try engine.run(verb: "set_reminders", input: try json(#"{"on":false,"from":null,"to":null,"everyHours":null}"#), records: store.query(sidekickId: Self.sidekickId, keyPrefix: ""), now: now)
        XCTAssertEqual(off.text, "Reminders off")
        guard case .changes(let offOps) = off.outcome else {
            return XCTFail("expected changes, got \(off.outcome)")
        }
        try RecordWriter(store: store).apply(sidekickId: Self.sidekickId, ops: offOps)
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "reminder:water")?["done"], .bool(true))
    }

    func testARefusalChangesNothing() throws {
        let store = try seededToolsStore()
        let before = store.query(sidekickId: Self.sidekickId, keyPrefix: "")
        let engine = try toolsEngine()
        let undo = try engine.run(verb: "undo", input: .object([:]), records: before, now: now)
        XCTAssertEqual(undo.outcome, .refused(reason: "nothing-to-undo"))
        let tooMuch = try engine.run(verb: "log", input: try json(#"{"amount":9,"unit":"l"}"#), records: before, now: now)
        XCTAssertEqual(tooMuch.outcome, .refused(reason: "amount-not-offered"))
        XCTAssertEqual(store.query(sidekickId: Self.sidekickId, keyPrefix: ""), before)
    }

    func testContextGivesTheGoalAndTodayInThePersonsUnit() throws {
        let store = try seededToolsStore(unit: "l")
        let context = try toolsEngine().context(records: store.query(sidekickId: Self.sidekickId, keyPrefix: ""), now: now)
        XCTAssertEqual(context["unit"], .string("L"))
        XCTAssertEqual(context["goal"], .string("2.5 L"))
        XCTAssertEqual(context["today"], .string("0 L"))
    }
}
