import CryptoKit
import WebKit
import XCTest
@testable import Midas

/// Serves fixed HTML for one Sidekick id, as the platform would.
private struct StubBundleLoader: SidekickBundleLoading {
    let sidekickId: String
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId requestedId: String) async throws -> SidekickBundle {
        guard requestedId == sidekickId else {
            throw SidekickBundleError.notFound
        }
        return SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

/// Signals when the main frame finishes loading.
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation
    let navigationGuard: SidekickNavigationGuard

    init(finished: XCTestExpectation, sidekickId: String) {
        self.finished = finished
        self.navigationGuard = SidekickNavigationGuard(sidekickId: sidekickId)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        await navigationGuard.webView(webView, decidePolicyFor: navigationAction)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}

@MainActor
final class SidekickWebViewTests: XCTestCase {
    private let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!

    private static func cspHash(of scriptText: String) -> String {
        let digest = SHA256.hash(data: Data(scriptText.utf8))
        return "'sha256-\(Data(digest).base64EncodedString())'"
    }

    // The hashed script records CSP violations so the tests can tell a CSP block from a
    // network failure. The second script is not hashed and must never run.
    private static let trustedScript = """
    window.violations = [];
    document.addEventListener('securitypolicyviolation', function recordViolation(event) {
      window.violations.push(event.violatedDirective + ' ' + event.blockedURI);
    });
    window.trustedRan = true;
    """
    private static let pageHTML = """
    <!doctype html><html><body><p id="marker">hello</p>
    <script>\(trustedScript)</script>
    <script>window.untrustedRan = true;</script>
    </body></html>
    """

    private func loadStubSidekick(sidekickId: String = "hello", loaderId: String = "hello") async throws -> (WKWebView, LoadWaiter) {
        let loader = StubBundleLoader(sidekickId: loaderId, html: Self.pageHTML, scriptHashes: [Self.cspHash(of: Self.trustedScript)])
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin)
        let finished = expectation(description: "page loaded")
        let waiter = LoadWaiter(finished: finished, sidekickId: sidekickId)
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        return (webView, waiter)
    }

    func testPageLoadsOnItsOwnSidekickOrigin() async throws {
        let (webView, waiter) = try await loadStubSidekick()
        let origin = try await webView.evaluateJavaScript("window.location.origin") as? String
        let markerText = try await webView.evaluateJavaScript("document.getElementById('marker').textContent") as? String
        XCTAssertEqual(origin, "sidekick://hello")
        XCTAssertEqual(markerText, "hello")
        _ = waiter
    }

    func testOnlyDeployedScriptsRun() async throws {
        let (webView, waiter) = try await loadStubSidekick()
        let trustedRan = try await webView.evaluateJavaScript("window.trustedRan === true") as? Bool
        let untrustedRan = try await webView.evaluateJavaScript("window.untrustedRan === true") as? Bool
        XCTAssertEqual(trustedRan, true)
        XCTAssertEqual(untrustedRan, false)
        _ = waiter
    }

    func testFetchToAnyOtherOriginIsBlockedByCSP() async throws {
        let (webView, waiter) = try await loadStubSidekick()
        let fetchScript = """
        try { await fetch('https://example.com/'); return 'allowed'; } catch (error) { return 'blocked'; }
        """
        let outcome = try await webView.callAsyncJavaScript(fetchScript, contentWorld: .page) as? String
        let violations = try await webView.evaluateJavaScript("window.violations.join('|')") as? String
        XCTAssertEqual(outcome, "blocked")
        XCTAssertTrue(violations?.contains("connect-src") == true, "no CSP violation recorded: \(violations ?? "nil")")
        _ = waiter
    }

    func testFetchToPlatformOriginIsNotACSPViolation() async throws {
        let (webView, waiter) = try await loadStubSidekick()
        // Network or CORS may fail in a test run; only a CSP violation would fail this test.
        let fetchScript = """
        try { await fetch('https://midas-api.midas-backend.workers.dev/health'); } catch (error) {}
        return window.violations.join('|');
        """
        let violations = try await webView.callAsyncJavaScript(fetchScript, contentWorld: .page) as? String
        // The unhashed inline script's script-src-elem violation is expected; only connect-src counts here.
        XCTAssertNotNil(violations)
        XCTAssertFalse(violations?.contains("connect-src") ?? true, "platform fetch hit CSP: \(violations ?? "nil")")
        _ = waiter
    }

    func testNavigationAwayFromTheSidekickIsCancelled() async throws {
        let (webView, waiter) = try await loadStubSidekick()
        _ = try await webView.evaluateJavaScript("window.location.href = 'https://example.com/'; true")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(webView.url?.absoluteString, "sidekick://hello/")
        _ = waiter
    }

    func testUnknownSidekickGetsAnErrorPageNotABundle() async throws {
        let (webView, waiter) = try await loadStubSidekick(sidekickId: "missing", loaderId: "hello")
        let bodyText = try await webView.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertEqual(bodyText, "This Sidekick could not be loaded.")
        _ = waiter
    }
}
