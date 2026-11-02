import CryptoKit
import WebKit
import XCTest
@testable import Midas

private struct TodoBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class TodoPageWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}

/// The real To-Do Sidekick (`sidekicks/todo/index.html`) in a real WKWebView, under the real CSP
/// (which has `form-action 'none'`), writing through the scheme handler into the local store with
/// reminder validation on. Founder, 2026-11-02: a new to-do typed in the row was not saved. A typed
/// to-do is saved however the row ends: Return, the keyboard's Go (a form submit), tapping away or
/// closing the keyboard (blur), and it is saved once.
@MainActor
final class TodoSidekickTests: XCTestCase {
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "todo-sidekick-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func bundleHTML() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = repositoryRoot.appending(path: "sidekicks/todo/index.html")
        return try String(contentsOf: bundleURL, encoding: .utf8)
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

    private func loadTodoSidekick(store: LocalRecordStore) async throws -> (WKWebView, TodoPageWaiter) {
        let html = try bundleHTML()
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = TodoBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let finished = expectation(description: "to-do page loaded")
        let waiter = TodoPageWaiter(finished: finished)
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: "todo")))
        await fulfillment(of: [finished], timeout: 10)
        return (webView, waiter)
    }

    /// Opens the "New To-Do" row on Today (one to-do already there, as on the founder's screen),
    /// types `title`, then ends the row the way `ending` names. Returns how many stored to-dos
    /// carry that title, or an error text.
    private func typeNewTodo(in webView: WKWebView, title: String, ending: String) async throws -> String? {
        let script = """
        function pause(milliseconds) {
          return new Promise(function waitBriefly(resolve) { setTimeout(resolve, milliseconds); });
        }
        for (var attempt = 0; attempt < 30 && !state.loaded; attempt += 1) { await pause(100); }
        if (!state.loaded) { return 'page did not load'; }
        var seed = Logic.todoFromEntry('Submit app', { when: todayKey() }, state, todayKey(), Date.now());
        await saveTodo(seed);
        render();
        var addRow = document.querySelector('[data-action="inline-add"]');
        if (!addRow) { return 'no New To-Do row'; }
        addRow.click();
        var input = document.getElementById('inlineInput');
        if (!input) { return 'tapping New To-Do opened no row'; }
        input.focus();
        input.value = title;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        if (ending === 'return') {
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
        } else if (ending === 'go') {
          document.getElementById('inlineForm').requestSubmit();
        } else if (ending === 'tapAway') {
          // A web view with no window never truly focuses, so blur() fires nothing here; send the
          // blur event the phone sends when the row loses focus
          input.dispatchEvent(new FocusEvent('blur'));
        } else if (ending === 'returnThenTapAway') {
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
          input.dispatchEvent(new FocusEvent('blur'));
        } else if (ending === 'tapNewToDoAgain') {
          document.querySelector('[data-action="inline-add"]').click();
        } else if (ending === 'redraw') {
          render();
        }
        await pause(400);
        var records = await store.query('reminder:');
        var matches = 0;
        for (var index = 0; index < records.length; index += 1) {
          if (records[index].value.title === title) { matches += 1; }
        }
        return String(matches);
        """
        return try await webView.callAsyncJavaScript(script, arguments: ["title": title, "ending": ending], contentWorld: .page) as? String
    }

    func testPageRunsUnderTheRealContentSecurityPolicy() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadTodoSidekick(store: store)
        let probe = """
        if (typeof TodoLogic !== 'object' || typeof store !== 'object') { return 'script did not run'; }
        for (var attempt = 0; attempt < 30; attempt += 1) {
          if (state.loaded && document.getElementById('scroller').textContent.trim().length > 0) { return 'rendered'; }
          await new Promise(function waitBriefly(resolve) { setTimeout(resolve, 100); });
        }
        return 'rendered nothing';
        """
        let outcome = try await webView.callAsyncJavaScript(probe, contentWorld: .page) as? String
        XCTAssertEqual(outcome, "rendered", "the page's inline script did not run, or rendered nothing")
        _ = waiter
    }

    func testANewToDoTypedInTheRowIsSavedOnReturn() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadTodoSidekick(store: store)
        let saved = try await typeNewTodo(in: webView, title: "Buy milk", ending: "return")
        XCTAssertEqual(saved, "1")
        _ = waiter
    }

    func testANewToDoTypedInTheRowIsSavedOnTheKeyboardsGoKey() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadTodoSidekick(store: store)
        let saved = try await typeNewTodo(in: webView, title: "Call mom", ending: "go")
        XCTAssertEqual(saved, "1", "a form submit under form-action 'none' must still save")
        _ = waiter
    }

    func testANewToDoTypedInTheRowIsSavedWhenTappingAwayOrClosingTheKeyboard() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadTodoSidekick(store: store)
        let saved = try await typeNewTodo(in: webView, title: "Pay rent", ending: "tapAway")
        XCTAssertEqual(saved, "1", "typed text was thrown away when the row lost focus")
        _ = waiter
    }

    func testANewToDoTypedInTheRowIsSavedWhenNewToDoIsTappedAgain() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadTodoSidekick(store: store)
        let saved = try await typeNewTodo(in: webView, title: "Water plants", ending: "tapNewToDoAgain")
        XCTAssertEqual(saved, "1", "a second New To-Do threw away the row being typed")
        _ = waiter
    }

    func testANewToDoTypedInTheRowSurvivesARedraw() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadTodoSidekick(store: store)
        let saved = try await typeNewTodo(in: webView, title: "Gym", ending: "redraw")
        XCTAssertEqual(saved, "1", "a redraw (back on screen, a new day) threw away the row being typed")
        _ = waiter
    }

    func testReturnThenTappingAwaySavesTheToDoOnce() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadTodoSidekick(store: store)
        let saved = try await typeNewTodo(in: webView, title: "Book flights", ending: "returnThenTapAway")
        XCTAssertEqual(saved, "1", "one typed to-do was saved twice")
        _ = waiter
    }
}
