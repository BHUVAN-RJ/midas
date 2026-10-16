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

    func testOldAlertAndTimeSnoozesAreFoldedIntoTheItemsOwnEntries() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let eventDate = dateText(daysFromToday: 3)
        try store.set(sidekickId: Self.sidekickId, key: "reminder:old", value: .object([
            "kind": .string("care-item"), "at": .string("\(eventDate)T20:00:00.000Z"), "title": .string("Old"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(false), "list": .string("meetings"), "snoozedUntil": .string("\(eventDate)T20:30:00.000Z"),
        ]))
        // Snoozed and not done: carried. Another one done: its snooze is over.
        try store.set(sidekickId: Self.sidekickId, key: "reminder:old~r1", value: .object([
            "kind": .string("care-alert"), "at": .string("\(eventDate)T19:00:00.000Z"), "title": .string("Old in 1 hour"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(false), "alertOf": .string("old"), "rule": .string("r1"),
            "occurrenceAt": .string("\(eventDate)T20:00:00.000Z"), "snoozedUntil": .string("\(eventDate)T19:10:00.000Z"),
        ]))
        try store.set(sidekickId: Self.sidekickId, key: "reminder:old~r2", value: .object([
            "kind": .string("care-alert"), "at": .string("\(eventDate)T01:00:00.000Z"), "title": .string("Old tomorrow"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(true), "alertOf": .string("old"), "rule": .string("r2"),
            "occurrenceAt": .string("\(eventDate)T20:00:00.000Z"), "snoozedUntil": .string("\(eventDate)T01:10:00.000Z"),
        ]))
        try store.set(sidekickId: Self.sidekickId, key: "reminder:hourly", value: .object([
            "kind": .string("care-item"), "at": .string("2026-10-01T15:00:00.000Z"), "title": .string("Water"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(false), "list": .string("water"), "repeat": .object(["every": .string("day")]), "everyHours": .number(4),
        ]))
        try store.set(sidekickId: Self.sidekickId, key: "reminder:hourly@1200", value: .object([
            "kind": .string("care-slot"), "at": .string("2026-10-01T19:00:00.000Z"), "title": .string("Water"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(false), "repeat": .object(["every": .string("day")]), "slotOf": .string("hourly"),
            "time": .string("12:00"), "snoozedUntil": .string("2026-10-15T19:10:00.000Z"),
        ]))

        let webView = try await loadPage(store: store)
        _ = try await runScript(webView, "await CareApp.sync(); return 'synced';")

        XCTAssertEqual(reminderKeys(store, itemId: "old"), ["reminder:old"])
        XCTAssertEqual(reminderKeys(store, itemId: "hourly"), ["reminder:hourly"])
        let old = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:old"))
        XCTAssertEqual(old["snoozes"], .object(["~r1": .string("\(eventDate)T19:10:00.000Z")]), "the alert's own snooze was not carried, or a done one was")
        XCTAssertEqual(old["snoozedUntil"], .string("\(eventDate)T20:30:00.000Z"), "the item's own snooze must stay its own")
        XCTAssertEqual(old["done"], .bool(true), "Done on the old alert did not complete the event")
        let hourly = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:hourly"))
        XCTAssertEqual(hourly["snoozes"], .object(["@1200": .string("2026-10-15T19:10:00.000Z")]))
        XCTAssertNil(hourly["snoozedUntil"])
        let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: "reminder:hourly", value: hourly))
        XCTAssertEqual(record.snoozes["@1200"], ReminderRecord.parseDate(.string("2026-10-15T19:10:00.000Z")))
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
