import CryptoKit
import WebKit
import XCTest
@testable import Midas

private struct ScriptPageLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class ScriptPageWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}

/// End to end from the Sidekick's side: the pasted helper (`shell/sdk/midas-store.js`) under the
/// real CSP, through the scheme handler, into the store, with reminder validation on.
@MainActor
final class MidasStoreScriptTests: XCTestCase {
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "script-records-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func helperScript() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let scriptURL = testsDirectory.deletingLastPathComponent().appending(path: "sdk/midas-store.js")
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }

    private func loadSidekickWithHelper(store: LocalRecordStore) async throws -> (WKWebView, ScriptPageWaiter) {
        let script = try helperScript()
        let digest = SHA256.hash(data: Data(script.utf8))
        let scriptHash = "'sha256-\(Data(digest).base64EncodedString())'"
        let html = "<!doctype html><html><body><script>\(script)</script></body></html>"
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = ScriptPageLoader(html: html, scriptHashes: [scriptHash])
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let finished = expectation(description: "page loaded")
        let waiter = ScriptPageWaiter(finished: finished)
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: "reminders")))
        await fulfillment(of: [finished], timeout: 10)
        return (webView, waiter)
    }

    func testHelperSetsGetsQueriesAndDeletes() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadSidekickWithHelper(store: store)
        let roundTripScript = """
        await store.set('reminder:1', { at: '2026-10-09T16:00:00.000Z', title: 'Call mom' });
        const fetched = await store.get('reminder:1');
        const listed = await store.query('reminder:');
        const missing = await store.get('reminder:none');
        return JSON.stringify({ title: fetched.title, count: listed.length, missing: missing });
        """
        let summary = try await webView.callAsyncJavaScript(roundTripScript, contentWorld: .page) as? String
        XCTAssertEqual(summary, #"{"title":"Call mom","count":1,"missing":null}"#)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1")?["title"]?.stringValue, "Call mom")

        _ = try await webView.callAsyncJavaScript("await store.delete('reminder:1'); return true;", contentWorld: .page)
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:1"))
        _ = waiter
    }

    func testBadReminderIsRejectedWithTheReason() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadSidekickWithHelper(store: store)
        let badWriteScript = """
        try { await store.set('reminder:bad', { at: 'someday', title: 'bad time' }); return 'accepted'; }
        catch (error) { return error.message; }
        """
        let outcome = try await webView.callAsyncJavaScript(badWriteScript, contentWorld: .page) as? String
        XCTAssertEqual(outcome, "reminder.at must be an ISO 8601 date or epoch milliseconds")
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:bad"))
        _ = waiter
    }
}
