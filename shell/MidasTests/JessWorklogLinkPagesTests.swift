import CryptoKit
import WebKit
import XCTest
@testable import Midas

// Work log entries are links (founder, 2026-10-31): each base Sidekick page, opened with a focus
// from a jess card, draws the record's row with its data-key in view and the SDK marks it. Real
// page, real WKWebView, real CSP; the record is made by the Sidekick's own tools.js, as jess does.

private struct WorklogPageLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class WorklogPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

private let worklogRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
final class JessWorklogLinkPagesTests: XCTestCase {
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "worklog-pages-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func sidekickFile(_ sidekickId: String, _ fileName: String) throws -> String {
        try String(contentsOf: worklogRepoRoot.appending(path: "sidekicks/\(sidekickId)/\(fileName)"), encoding: .utf8)
    }

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

    private func load(_ webView: WKWebView, waiter: WorklogPageWaiter, sidekickId: String, reload: Bool) async {
        let finished = expectation(description: "\(sidekickId) page loaded")
        waiter.finished = finished
        if reload {
            webView.reload()
        } else {
            webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        }
        await fulfillment(of: [finished], timeout: 10)
    }

    private func pause(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// Runs one of the Sidekick's own tools on the store's records and writes its ops; returns the
    /// first key it set.
    private func runTool(_ sidekickId: String, verb: String, input: String, store: LocalRecordStore) throws -> String {
        let engine = try SidekickToolsEngine(source: try sidekickFile(sidekickId, "tools.js"))
        let inputValue = try JSONDecoder().decode(JSONValue.self, from: Data(input.utf8))
        let records = store.query(sidekickId: sidekickId, keyPrefix: "")
        let result = try engine.run(verb: verb, input: inputValue, records: records, now: Date())
        guard case .changes(let ops) = result.outcome else {
            XCTFail("\(sidekickId).\(verb) refused: \(result.outcome)")
            return ""
        }
        var firstKey = ""
        for op in ops {
            switch op {
            case .set(let key, let value):
                try store.set(sidekickId: sidekickId, key: key, value: value)
                if firstKey.isEmpty {
                    firstKey = key
                }
            case .delete(let key):
                try store.delete(sidekickId: sidekickId, key: key)
            }
        }
        return firstKey
    }

    /// Waits up to 3 s for the keyed element to be drawn, marked and on screen.
    private func markedState(_ webView: WKWebView, key: String) async throws -> String? {
        let checkScript = """
        for (let tries = 0; tries < 150; tries += 1) {
          const element = document.querySelector('[data-key="' + CSS.escape(key) + '"]');
          if (element && element.getAnimations().length > 0) {
            const box = element.getBoundingClientRect();
            const onScreen = box.bottom > 0 && box.top < window.innerHeight;
            return onScreen ? 'marked on screen' : 'marked off screen';
          }
          await new Promise(function waitABit(resolve) { setTimeout(resolve, 20); });
        }
        const drawn = document.querySelector('[data-key="' + CSS.escape(key) + '"]');
        return drawn ? 'drawn, not marked' : 'not drawn';
        """
        return try await webView.callAsyncJavaScript(checkScript, arguments: ["key": key], contentWorld: .page) as? String
    }

    /// The page first opens empty (a first run sets itself up), the tool makes the record, then the
    /// page opens again with the focus, as after a tap on the jess card.
    private func openAtNewRecord(sidekickId: String, setUp: String?, verb: String, input: String) async throws -> String? {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let channel = SidekickStoreChannel(store: store)
        let html = try sidekickFile(sidekickId, "index.html")
        let loader = WorklogPageLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        webView.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let waiter = WorklogPageWaiter()
        webView.navigationDelegate = waiter
        await load(webView, waiter: waiter, sidekickId: sidekickId, reload: false)
        if let setUp {
            _ = try await webView.callAsyncJavaScript(setUp, contentWorld: .page)
        }
        await pause(milliseconds: 400)

        let key = try runTool(sidekickId, verb: verb, input: input, store: store)
        XCTAssertFalse(key.isEmpty)
        channel.setFocus(JessChange(key: key, op: .new), sidekickId: sidekickId)
        await load(webView, waiter: waiter, sidekickId: sidekickId, reload: true)
        let state = try await markedState(webView, key: key)
        _ = waiter
        return state
    }

    func testRemindersOpensAtTheReminderJessAddedAndMarksIt() async throws {
        // Twenty more reminders first, so the new one starts off screen and the page's own
        // scroller has to bring it into view
        let store = LocalRecordStore(fileURL: storeFileURL)
        for number in 1...20 {
            _ = try runTool("reminders", verb: "add", input: #"{"title":"Earlier \#(number)","notes":null,"list":null,"when":null}"#, store: store)
        }
        let state = try await openAtNewRecord(sidekickId: "reminders", setUp: nil, verb: "add", input: #"{"title":"Zebra crossing","notes":null,"list":null,"when":null}"#)
        XCTAssertEqual(state, "marked on screen")
    }

    func testWaterOpensTheLogAtTheDrinkJessLoggedAndMarksIt() async throws {
        let start = "await WaterApp.whenReady(); await WaterApp.start({ goalMl: 2000, unit: 'ml' }); return true;"
        let state = try await openAtNewRecord(sidekickId: "hydration", setUp: start, verb: "log", input: #"{"amount":500,"unit":"ml"}"#)
        XCTAssertEqual(state, "marked on screen")
    }

    func testCareRemindersOpensTheListHoldingTheReminderAndMarksIt() async throws {
        let ready = "await CareApp.whenReady(); return true;"
        let state = try await openAtNewRecord(sidekickId: "care-reminders", setUp: ready, verb: "add", input: #"{"title":"Give Mom her pills","list":"Appointments","when":null,"everyHours":null}"#)
        XCTAssertEqual(state, "marked on screen")
    }
}
