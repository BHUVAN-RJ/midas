import CryptoKit
import WebKit
import XCTest
@testable import Midas

/// Serves one fixed page for any Sidekick id.
private struct AnySidekickBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class PageLoadWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}

/// The real path a Sidekick uses: plain fetch POST from the page to its own origin, answered by
/// the shell's scheme handler on the phone. Proves the POST body reaches native code (WebKit bug
/// 191362 once dropped it) and that a Sidekick cannot reach another Sidekick's store.
@MainActor
final class LocalChannelWebViewTests: XCTestCase {
    private let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
    private var storeFileURL: URL!

    private static let trustedScript = """
    window.violations = [];
    document.addEventListener('securitypolicyviolation', function recordViolation(event) {
      window.violations.push(event.violatedDirective + ' ' + event.blockedURI);
    });
    """
    private static let pageHTML = "<!doctype html><html><body><script>\(trustedScript)</script></body></html>"

    override func setUp() {
        super.setUp()
        let temporaryDirectory = FileManager.default.temporaryDirectory
        storeFileURL = temporaryDirectory.appending(path: "webview-records-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private static func cspHash(of scriptText: String) -> String {
        let digest = SHA256.hash(data: Data(scriptText.utf8))
        return "'sha256-\(Data(digest).base64EncodedString())'"
    }

    private func loadSidekick(sidekickId: String, channel: SidekickStoreChannel?) async throws -> (WKWebView, PageLoadWaiter) {
        let loader = AnySidekickBundleLoader(html: Self.pageHTML, scriptHashes: [Self.cspHash(of: Self.trustedScript)])
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let finished = expectation(description: "page loaded")
        let waiter = PageLoadWaiter(finished: finished)
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        return (webView, waiter)
    }

    private func postToStore(from webView: WKWebView, url: String, body: String) async throws -> String? {
        let fetchScript = """
        try {
          const response = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body });
          return await response.text();
        } catch (error) { return 'blocked'; }
        """
        let arguments: [String: Any] = ["url": url, "body": body]
        return try await webView.callAsyncJavaScript(fetchScript, arguments: arguments, contentWorld: .page) as? String
    }

    func testFetchPostReachesTheShellAndIsStored() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let channel = SidekickStoreChannel(store: store)
        let (webView, waiter) = try await loadSidekick(sidekickId: "reminders", channel: channel)
        let setBody = #"{"op":"set","key":"note:1","value":{"text":"offline works"}}"#
        let setReply = try await postToStore(from: webView, url: "sidekick://reminders/_midas/store", body: setBody)
        XCTAssertEqual(setReply, #"{"ok":true}"#)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "note:1")?["text"]?.stringValue, "offline works")

        let getBody = #"{"op":"get","key":"note:1"}"#
        let getReply = try await postToStore(from: webView, url: "sidekick://reminders/_midas/store", body: getBody)
        XCTAssertTrue(getReply?.contains("offline works") == true, "get reply: \(getReply ?? "nil")")
        _ = waiter
    }

    private static func parseReply(_ reply: String?) -> [String: Any]? {
        guard let replyData = reply?.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: replyData) as? [String: Any]
    }

    /// A body several times 16,384 bytes must reach the shell whole, whether WebKit hands it over
    /// as httpBody or as httpBodyStream (read in 16,384-byte chunks). Records are capped at 64 KB (docs/PRODUCT.md section 5, 2026-10-10), so a 200,000-character
    /// value must come back as the size refusal: that refusal is only reachable if the whole body
    /// arrived and parsed as JSON (a truncated body gives "body is not JSON").
    func testLargeBodyArrivesWhole() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let channel = SidekickStoreChannel(store: store)
        let (webView, waiter) = try await loadSidekick(sidekickId: "reminders", channel: channel)

        let overLimitText = String(repeating: "a", count: 200_000)
        let overLimitBody = #"{"op":"set","key":"note:big","value":""# + overLimitText + #""}"#
        let overLimitReply = try await postToStore(from: webView, url: "sidekick://reminders/_midas/store", body: overLimitBody)
        let parsedOverLimitReply = Self.parseReply(overLimitReply)
        XCTAssertEqual(parsedOverLimitReply?["ok"] as? Bool, false, "reply: \(overLimitReply ?? "nil")")
        let overLimitError = parsedOverLimitReply?["error"] as? String
        XCTAssertTrue(overLimitError?.contains("65536") == true, "reply: \(overLimitReply ?? "nil")")
        XCTAssertNil(store.get(sidekickId: "reminders", key: "note:big"))

        // About 60,000 bytes: under the cap, and still several 16,384-byte chunks long.
        let underLimitText = String(repeating: "b", count: 60_000)
        let underLimitBody = #"{"op":"set","key":"note:large","value":""# + underLimitText + #""}"#
        let underLimitReply = try await postToStore(from: webView, url: "sidekick://reminders/_midas/store", body: underLimitBody)
        XCTAssertEqual(underLimitReply, #"{"ok":true}"#)
        let storedText = store.get(sidekickId: "reminders", key: "note:large")?.stringValue
        XCTAssertEqual(storedText?.count, 60_000)
        XCTAssertEqual(storedText, underLimitText)
        _ = waiter
    }

    func testSidekickCannotReachAnotherSidekicksStore() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let channel = SidekickStoreChannel(store: store)
        let (webView, waiter) = try await loadSidekick(sidekickId: "calendar", channel: channel)
        let setBody = #"{"op":"set","key":"reminder:evil","value":{"title":"x"}}"#
        let reply = try await postToStore(from: webView, url: "sidekick://reminders/_midas/store", body: setBody)
        let violations = try await webView.evaluateJavaScript("window.violations.join('|')") as? String
        XCTAssertEqual(reply, "blocked")
        XCTAssertTrue(violations?.contains("connect-src") == true, "no CSP violation recorded: \(violations ?? "nil")")
        XCTAssertEqual(store.queryAllSidekicks(keyPrefix: ""), [])
        _ = waiter
    }

    func testStoreRouteIsClosedWithoutAChannel() async throws {
        let (webView, waiter) = try await loadSidekick(sidekickId: "reminders", channel: nil)
        let statusScript = """
        const response = await fetch('sidekick://reminders/_midas/store', { method: 'POST', body: '{}' });
        return response.status;
        """
        let status = try await webView.callAsyncJavaScript(statusScript, contentWorld: .page) as? Int
        XCTAssertEqual(status, 404)
        _ = waiter
    }

    func testPolicyAddsOnlyTheSidekicksOwnOriginToConnectSrc() {
        let policy = SidekickContentSecurityPolicy.policy(scriptHashes: [], platformOrigin: platformOrigin, sidekickOrigin: "sidekick://reminders")
        XCTAssertTrue(policy.contains("connect-src https://midas-api.midas-backend.workers.dev sidekick://reminders;"))
        let policyWithoutOrigin = SidekickContentSecurityPolicy.policy(scriptHashes: [], platformOrigin: platformOrigin)
        XCTAssertFalse(policyWithoutOrigin.contains("sidekick://"))
    }
}
