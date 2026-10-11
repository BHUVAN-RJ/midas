import CryptoKit
import WebKit
import XCTest
@testable import Midas

private struct RemindersBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class RemindersPageWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}

/// The real reminders Sidekick (`sidekicks/reminders/index.html`) in a real WKWebView, under the
/// real CSP, writing through the scheme handler into the local store with reminder validation on.
/// Proves the page's records are the ones the notification engine accepts, and that what the
/// shell writes back from a notification tap survives an edit made in the page.
@MainActor
final class RemindersSidekickTests: XCTestCase {
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "reminders-sidekick-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func bundleHTML() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = repositoryRoot.appending(path: "sidekicks/reminders/index.html")
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

    private func loadRemindersSidekick(store: LocalRecordStore) async throws -> (WKWebView, RemindersPageWaiter) {
        let html = try bundleHTML()
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = RemindersBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let finished = expectation(description: "reminders page loaded")
        let waiter = RemindersPageWaiter(finished: finished)
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: "reminders")))
        await fulfillment(of: [finished], timeout: 10)
        return (webView, waiter)
    }

    /// JavaScript that builds a full item in the page's own shape.
    private static let makeItemScript = """
    function makeTestItem(fields) {
      var item = { title: 'Untitled', notes: '', list: null, date: null, time: null, repeat: null,
                   timeZone: 'America/Los_Angeles', done: false, completedAt: null, snoozedUntil: null,
                   lastDoneAt: null, createdAt: '2026-10-01T00:00:00.000Z', source: null };
      Object.assign(item, fields);
      return item;
    }
    async function saveTestItem(item) {
      var key = RemindersLogic.recordKey(item);
      var existing = await store.get(key);
      await store.set(key, RemindersLogic.recordFromItem(item, existing));
      return key;
    }
    """

    func testPageRunsUnderTheRealContentSecurityPolicy() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadRemindersSidekick(store: store)
        // textContent, not innerText: innerText needs layout and this web view has no window.
        // The page renders after its first async store read, so poll for up to 3 s. Script and
        // style elements are skipped: the inline script's own source is text inside body.
        let probe = """
        if (typeof RemindersLogic !== 'object' || typeof store !== 'object') { return 'script did not run'; }
        function renderedText() {
          var text = '';
          var children = document.body.children;
          for (var index = 0; index < children.length; index += 1) {
            var tag = children[index].tagName;
            if (tag !== 'SCRIPT' && tag !== 'STYLE') { text += children[index].textContent; }
          }
          return text.trim();
        }
        for (var attempt = 0; attempt < 30; attempt += 1) {
          if (renderedText().length > 0) { return 'rendered'; }
          await new Promise(function waitBriefly(resolve) { setTimeout(resolve, 100); });
        }
        return 'rendered nothing';
        """
        let outcome = try await webView.callAsyncJavaScript(probe, contentWorld: .page) as? String
        XCTAssertEqual(outcome, "rendered", "the page's inline script did not run, or rendered nothing")
        _ = waiter
    }

    func testEveryRepeatOptionAndAllDayAreAcceptedByTheNotificationEngine() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadRemindersSidekick(store: store)
        let writeScript = Self.makeItemScript + """
        var options = ['never', 'daily', 'weekdays', 'weekends', 'weekly', 'monthly'];
        var failures = [];
        for (var index = 0; index < options.length; index += 1) {
          var option = options[index];
          var item = makeTestItem({ id: 'repeat-' + option, title: 'Repeat ' + option, date: '2026-10-12',
                                    time: '18:00', repeat: RemindersLogic.repeatForOption(option) });
          try { await saveTestItem(item); } catch (error) { failures.push(option + ': ' + error.message); }
        }
        var allDay = makeTestItem({ id: 'all-day', title: 'All day', date: '2026-10-20' });
        try { await saveTestItem(allDay); } catch (error) { failures.push('all-day: ' + error.message); }
        var undated = makeTestItem({ id: 'undated', title: 'Milk', list: 'groceries' });
        try { await saveTestItem(undated); } catch (error) { failures.push('undated: ' + error.message); }
        return JSON.stringify(failures);
        """
        let failures = try await webView.callAsyncJavaScript(writeScript, contentWorld: .page) as? String
        XCTAssertEqual(failures, "[]")

        let repeatKeys = ["never", "daily", "weekdays", "weekends", "weekly", "monthly"]
        for option in repeatKeys {
            let key = "reminder:repeat-\(option)"
            let value = try XCTUnwrap(store.get(sidekickId: "reminders", key: key), "\(key) was not stored")
            XCTAssertNotNil(ReminderRecord.parse(sidekickId: "reminders", key: key, value: value), "\(key) does not parse")
        }
        let allDayValue = try XCTUnwrap(store.get(sidekickId: "reminders", key: "reminder:all-day"))
        XCTAssertNotNil(ReminderRecord.parse(sidekickId: "reminders", key: "reminder:all-day", value: allDayValue))
        XCTAssertNotNil(store.get(sidekickId: "reminders", key: "task:undated"))
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:undated"), "an undated item must not be a reminder: record")

        _ = try await webView.callAsyncJavaScript("await store.delete('reminder:repeat-daily'); return true;", contentWorld: .page)
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:repeat-daily"))
        _ = waiter
    }

    func testDoneTappedOnTheNotificationSurvivesAnEditInThePage() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadRemindersSidekick(store: store)
        let createScript = Self.makeItemScript + """
        await saveTestItem(makeTestItem({ id: 'gym', title: 'Gym', date: '2026-10-01', time: '19:30',
                                          repeat: RemindersLogic.repeatForOption('daily') }));
        await saveTestItem(makeTestItem({ id: 'bill', title: 'Pay bill', date: '2026-10-12', time: '09:00' }));
        return true;
        """
        _ = try await webView.callAsyncJavaScript(createScript, contentWorld: .page)

        // The shell's Done button, exactly as the notification engine applies it.
        let tapTime = Date(timeIntervalSince1970: 1_791_590_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for key in ["reminder:gym", "reminder:bill"] {
            let stored = try XCTUnwrap(store.get(sidekickId: "reminders", key: key))
            let afterDone = ReminderAction.done.apply(to: stored, now: tapTime, calendar: calendar)
            try store.set(sidekickId: "reminders", key: key, value: afterDone)
        }

        let editScript = """
        var keys = ['reminder:gym', 'reminder:bill'];
        for (var index = 0; index < keys.length; index += 1) {
          var existing = await store.get(keys[index]);
          var item = RemindersLogic.itemFromRecord(keys[index], existing);
          item.title = item.title + ' (edited)';
          await store.set(keys[index], RemindersLogic.recordFromItem(item, existing));
        }
        return true;
        """
        _ = try await webView.callAsyncJavaScript(editScript, contentWorld: .page)

        let gym = try XCTUnwrap(store.get(sidekickId: "reminders", key: "reminder:gym"))
        XCTAssertEqual(gym["title"]?.stringValue, "Gym (edited)")
        XCTAssertNotNil(gym["lastDoneAt"]?.stringValue, "the page dropped lastDoneAt written by the shell")
        let bill = try XCTUnwrap(store.get(sidekickId: "reminders", key: "reminder:bill"))
        XCTAssertEqual(bill["title"]?.stringValue, "Pay bill (edited)")
        XCTAssertEqual(bill["done"], .bool(true), "the page dropped done written by the shell")
        _ = waiter
    }
}
