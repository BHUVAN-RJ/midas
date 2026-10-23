import CryptoKit
import WebKit
import XCTest
@testable import Midas

// The care-reminders page and per-alert snoozes (founder decision 2026-10-15): old alert and time
// records' snoozes are folded into the item's `snoozes`; the page's Done clears the alerts'
// snoozes exactly as the native Done does and leaves the times' alone; a reminder moved to a new
// time starts without snoozes. Real page, real WKWebView, real CSP, the shell's reminder check on.

private struct SnoozeBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class SnoozePageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

@MainActor
final class CareRemindersSnoozeTests: XCTestCase {
    private static let sidekickId = "care-reminders"
    private static let zoneName = "America/Los_Angeles"
    private var storeFileURL: URL!
    private var pageWaiters: [SnoozePageWaiter] = []

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "care-snooze-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func bundleHTML() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appending(path: "sidekicks/care-reminders/index.html"), encoding: .utf8)
    }

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

    private func loadPage(store: LocalRecordStore) async throws -> WKWebView {
        let html = try bundleHTML()
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = SnoozeBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = SnoozePageWaiter()
        let finished = expectation(description: "care reminders page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: Self.sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        pageWaiters.append(waiter)
        let ready = try await runScript(webView, "await CareApp.whenReady(); return 'ready';")
        XCTAssertEqual(ready, "ready")
        return webView
    }

    private func runScript(_ webView: WKWebView, _ script: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(script, contentWorld: .page)
        return try XCTUnwrap(result as? String, "the script returned no text")
    }

    private var zoneCalendar: Calendar {
        ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: Self.zoneName)!)
    }

    private func dateText(daysFromToday offset: Int) -> String {
        let today = zoneCalendar.startOfDay(for: Date())
        let day = zoneCalendar.date(byAdding: .day, value: offset, to: today)!
        let parts = zoneCalendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func reminderKeys(_ store: LocalRecordStore, itemId: String) -> [String] {
        var keys: [String] = []
        for record in store.query(sidekickId: Self.sidekickId, keyPrefix: "reminder:\(itemId)") {
            keys.append(record.key)
        }
        return keys.sorted()
    }

    private func createAppointment(_ webView: WKWebView, dateText: String) async throws -> String {
        let script = """
        var listId = await CareApp.saveList({ name: 'Snooze Appointments', icon: 'stethoscope', color: 'charcoal', alerts: [
          { id: 'a1', kind: 'daysBefore', days: 1, time: '18:00', text: null },
          { id: 'a2', kind: 'before', minutes: 60, text: null } ] });
        var itemId = await CareApp.saveReminder({ title: 'Dentist', list: listId, date: '\(dateText)', time: '13:00',
                                                  repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return itemId;
        """
        return try await runScript(webView, script)
    }

    func testThePagesDoneClearsTheAlertsSnoozesLikeTheNativeDoneAndKeepsATimes() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let webView = try await loadPage(store: store)
        let itemId = try await createAppointment(webView, dateText: dateText(daysFromToday: 2))
        let key = "reminder:\(itemId)"
        var value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        // What the shell writes for Snooze on each notification, and on the item itself.
        value = JSONMergePatch.apply(ReminderChange.snoozePatch(until: Date().addingTimeInterval(600), part: .alert(ruleId: "a1")), to: value)
        value = JSONMergePatch.apply(ReminderChange.snoozePatch(until: Date().addingTimeInterval(1200), part: .alert(ruleId: "a2")), to: value)
        value = JSONMergePatch.apply(ReminderChange.snoozePatch(until: Date().addingTimeInterval(1800), part: .slot(time: "13:00")), to: value)
        value = JSONMergePatch.apply(ReminderChange.snoozePatch(until: Date().addingTimeInterval(2400), part: .item), to: value)
        try store.set(sidekickId: Self.sidekickId, key: key, value: value)
        XCTAssertEqual(value["snoozes"]?.objectValue?.count, 3)

        _ = try await runScript(webView, "await CareApp.markDone('\(itemId)'); return 'done';")
        let pageDone = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        let pageMoment = try XCTUnwrap(ReminderRecord.parseDate(pageDone["completedAt"]), "the page wrote no Done time")
        let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value))
        let nativeDone = JSONMergePatch.apply(ReminderChange.donePatch(for: value, part: .alert(ruleId: "a1"), occurrence: record.at, now: pageMoment), to: value)
        XCTAssertEqual(nativeDone, pageDone, "the page's Done and the native Done differ on snoozes")
        XCTAssertNil(pageDone["snoozedUntil"])
        XCTAssertEqual(pageDone["snoozes"], value["snoozes"]?["@1300"].map { .object(["@1300": $0]) }, "the alerts' snoozes go, the time's stays")
    }

    func testAReminderMovedToANewTimeStartsWithoutSnoozes() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let webView = try await loadPage(store: store)
        let itemId = try await createAppointment(webView, dateText: dateText(daysFromToday: 2))
        let key = "reminder:\(itemId)"
        var value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        value = JSONMergePatch.apply(ReminderChange.snoozePatch(until: Date().addingTimeInterval(600), part: .alert(ruleId: "a1")), to: value)
        try store.set(sidekickId: Self.sidekickId, key: key, value: value)

        // The same reminder edited without a move keeps the snooze; moved, it loses it.
        let keepScript = """
        await CareApp.saveReminder({ id: '\(itemId)', title: 'Dentist again', date: '\(dateText(daysFromToday: 2))', time: '13:00',
                                     repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return 'saved';
        """
        _ = try await runScript(webView, keepScript)
        let kept = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        XCTAssertEqual(kept["snoozes"], value["snoozes"], "an edit that does not move the reminder must keep the shell's snoozes")
        XCTAssertEqual(kept["title"], .string("Dentist again"))

        let moveScript = """
        await CareApp.saveReminder({ id: '\(itemId)', title: 'Dentist again', date: '\(dateText(daysFromToday: 4))', time: '13:00',
                                     repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return 'saved';
        """
        _ = try await runScript(webView, moveScript)
        let moved = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        XCTAssertNil(moved["snoozes"], "a moved reminder starts again, without the old snoozes")
    }
}
