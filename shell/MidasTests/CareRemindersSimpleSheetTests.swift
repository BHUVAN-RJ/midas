import CryptoKit
import WebKit
import XCTest
@testable import Midas

private struct SimpleSheetBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class SimpleSheetPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

/// Change 1 to the care-reminders Sidekick (founder, 2026-10-12): Add Reminder has a title and
/// exactly Date, Time and Repeat; a reminder belongs to the list it was added in, shows that
/// list's icon and uses that list's alerts. Real page, real WKWebView, real CSP.
@MainActor
final class CareRemindersSimpleSheetTests: XCTestCase {
    private static let sidekickId = "care-reminders"
    private static let zoneName = "America/Los_Angeles"
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "care-simple-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func bundleHTML() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = repositoryRoot.appending(path: "sidekicks/care-reminders/index.html")
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

    private func loadPage(store: LocalRecordStore) async throws -> (WKWebView, SimpleSheetPageWaiter) {
        let html = try bundleHTML()
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = SimpleSheetBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = SimpleSheetPageWaiter()
        let finished = expectation(description: "care reminders page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: Self.sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        let ready = try await runScript(webView, "if (typeof CareApp !== 'object') { return 'script did not run'; } await CareApp.whenReady(); return 'ready';")
        XCTAssertEqual(ready, "ready")
        return (webView, waiter)
    }

    private func runScript(_ webView: WKWebView, _ script: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(script, contentWorld: .page)
        return try XCTUnwrap(result as? String, "the script returned no text")
    }

    private func dateText(daysFromToday offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.zoneName)!
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: offset, to: today)!
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func reminderKeys(_ store: LocalRecordStore, itemId: String) -> [String] {
        var keys: [String] = []
        for record in store.query(sidekickId: Self.sidekickId, keyPrefix: "reminder:\(itemId)") {
            keys.append(record.key)
        }
        return keys
    }

    func testAddReminderShowsOnlyTitleDateTimeAndRepeat() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let script = """
        var homeHasAdd = document.querySelector('#main [data-action="new-reminder"]') !== null;
        document.querySelector('[data-action="open-list"][data-id="appointments"]').click();
        document.querySelector('[data-action="new-reminder"]').click();
        var sheet = document.getElementById('sheets');
        var fields = [];
        var fieldElements = sheet.querySelectorAll('[data-field]');
        for (var index = 0; index < fieldElements.length; index += 1) {
          fields.push(fieldElements[index].getAttribute('data-field'));
        }
        var labels = [];
        var labelElements = sheet.querySelectorAll('.kv .row .grow');
        for (var labelIndex = 0; labelIndex < labelElements.length; labelIndex += 1) {
          labels.push(labelElements[labelIndex].textContent.trim());
        }
        var buttons = [];
        var buttonElements = sheet.querySelectorAll('.sheet-body [data-action]');
        for (var buttonIndex = 0; buttonIndex < buttonElements.length; buttonIndex += 1) {
          buttons.push(buttonElements[buttonIndex].getAttribute('data-action'));
        }
        return JSON.stringify({ homeHasAdd: homeHasAdd, fields: fields, labels: labels, buttons: buttons,
                                title: sheet.querySelector('.mid').textContent });
        """
        let outcome = try await runScript(webView, script)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(outcome.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["homeHasAdd"] as? Bool, false, "home offers a way to add a reminder outside a list")
        XCTAssertEqual(parsed["title"] as? String, "New Reminder")
        XCTAssertEqual(parsed["fields"] as? [String], ["title", "date", "time", "repeatKey"])
        XCTAssertEqual(parsed["labels"] as? [String], ["Date", "Time", "Repeat"])
        XCTAssertEqual(parsed["buttons"] as? [String], [], "the sheet body has extra controls (icons, list, alerts, times)")
        _ = waiter
    }

    func testAReminderShowsItsListsIconAndStoresNoIconOfItsOwn() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let script = """
        var itemId = await CareApp.saveReminder({ title: 'Dentist', list: 'water', date: '\(dateText(daysFromToday: 2))', time: '13:00',
                                                  repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        document.querySelector('[data-action="open-list"][data-id="water"]').click();
        var row = document.querySelector('.row[data-id="' + itemId + '"]');
        var used = row ? row.querySelector('.ichip use').getAttribute('href') : 'no row';
        return JSON.stringify([itemId, used]);
        """
        let outcome = try await runScript(webView, script)
        let parts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(outcome.utf8)) as? [String])
        XCTAssertEqual(parts[1], "#i-drop", "the row does not show the Water list's icon (a title suggestion would be the tooth)")
        let record = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(parts[0])"))
        XCTAssertNil(record["icon"], "the record still carries its own icon")
        XCTAssertNil(record["alertRules"], "the record still carries its own alerts")
        _ = waiter
    }

    func testAListWithNoAlertsWritesExactlyOneRecordPerReminder() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let script = """
        var listId = await CareApp.saveList({ name: 'Plain', icon: 'bell', color: 'stone', alerts: [] });
        var first = await CareApp.saveReminder({ title: 'Call', list: listId, date: '\(dateText(daysFromToday: 3))', time: '10:00',
                                                 repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        var second = await CareApp.saveReminder({ title: 'Pills', list: listId, date: '\(dateText(daysFromToday: 0))', time: '21:00',
                                                  repeatKey: 'daily', timeZone: '\(Self.zoneName)' });
        return JSON.stringify([first, second]);
        """
        let outcome = try await runScript(webView, script)
        let ids = try JSONDecoder().decode([String].self, from: Data(outcome.utf8))
        for itemId in ids {
            let key = "reminder:\(itemId)"
            XCTAssertEqual(reminderKeys(store, itemId: itemId), [key])
            let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
            XCTAssertNotNil(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value))
        }
        _ = waiter
    }

    // Upgrade on read: the only test here allowed old shapes (docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md).
    func testAnOldRecordWithItsOwnIconAlertsAndSeriesStillLoadsAndUsesItsListsAlerts() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let eventDate = dateText(daysFromToday: 3)
        // A record not yet converted (own icon, own alerts, a series id)
        let oldItem: JSONValue = .object([
            "kind": .string("care-item"), "at": .string("\(eventDate)T20:00:00.000Z"), "title": .string("Old"),
            "body": .string(""), "timeZone": .string(Self.zoneName), "done": .bool(false), "list": .string("meetings"),
            "icon": .string("tooth"), "seriesId": .string("s1"),
            "alertRules": .array([.object(["id": .string("own1"), "kind": .string("before"), "minutes": .number(15), "text": .null])]),
        ])
        try store.set(sidekickId: Self.sidekickId, key: "reminder:old", value: oldItem)
        let (webView, waiter) = try await loadPage(store: store)
        let rendered = try await runScript(webView, "return document.getElementById('main').textContent;")
        XCTAssertTrue(rendered.contains("Meetings"), "the page did not render with an old record present")
        // Meetings' starter alert is 1 h before (rule r1); the old own 15 min alert is not used
        XCTAssertEqual(reminderKeys(store, itemId: "old"), ["reminder:old"])
        let rules = store.get(sidekickId: Self.sidekickId, key: "reminder:old")?["alerts"]?.arrayValue ?? []
        XCTAssertEqual(rules.map { $0["id"]?.stringValue }, ["r1"], "Meetings' rule was not copied onto the item")
        _ = waiter
    }
}
