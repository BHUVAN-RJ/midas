import CryptoKit
import WebKit
import XCTest
@testable import Midas

// The care-reminders page after the unified data rework (phase 3, 2026-10-15): one record per
// reminder, carrying its list's early-alert rules (`alerts`) and its hourly repeat (`everyHours`)
// for the shell's engine to expand; no `~rule` or `@HHMM` records; the old ones folded in and
// removed. Real page, real WKWebView, real CSP, the shell's reminder check on.

private struct FieldsBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class FieldsPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

@MainActor
final class CareRemindersFieldsTests: XCTestCase {
    private static let sidekickId = "care-reminders"
    private static let zoneName = "America/Los_Angeles"
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "care-fields-\(UUID().uuidString).json")
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

    private func loadPage(store: LocalRecordStore) async throws -> (WKWebView, FieldsPageWaiter) {
        let html = try bundleHTML()
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = FieldsBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = FieldsPageWaiter()
        let finished = expectation(description: "care reminders page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: Self.sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        try await waitUntilReady(webView)
        return (webView, waiter)
    }

    private func reload(_ webView: WKWebView, waiter: FieldsPageWaiter) async throws {
        let finished = expectation(description: "care reminders page reloaded")
        waiter.finished = finished
        webView.reload()
        await fulfillment(of: [finished], timeout: 10)
        try await waitUntilReady(webView)
    }

    private func waitUntilReady(_ webView: WKWebView) async throws {
        let probe = """
        if (typeof CareApp !== 'object' || typeof CareLogic !== 'object' || typeof store !== 'object') { return 'script did not run'; }
        await CareApp.whenReady();
        return 'ready';
        """
        let outcome = try await webView.callAsyncJavaScript(probe, contentWorld: .page) as? String
        XCTAssertEqual(outcome, "ready")
    }

    private func runScript(_ webView: WKWebView, _ script: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(script, contentWorld: .page)
        return try XCTUnwrap(result as? String, "the script returned no text")
    }

    private var zoneCalendar: Calendar {
        ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: Self.zoneName)!)
    }

    private func dayFromToday(_ offset: Int) -> Date {
        let today = zoneCalendar.startOfDay(for: Date())
        return zoneCalendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func dateText(_ day: Date) -> String {
        let parts = zoneCalendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func moment(_ day: Date, hour: Int, minute: Int) -> Date {
        zoneCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func reminderKeys(_ store: LocalRecordStore, itemId: String) -> [String] {
        var keys: [String] = []
        for record in store.query(sidekickId: Self.sidekickId, keyPrefix: "reminder:\(itemId)") {
            keys.append(record.key)
        }
        return keys.sorted()
    }

    private func parsedItem(_ store: LocalRecordStore, itemId: String) throws -> ReminderRecord {
        let key = "reminder:\(itemId)"
        let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key), "no record \(key)")
        return try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value), "\(key) is not a valid reminder")
    }

    private func expand(_ record: ReminderRecord) -> [ReminderRecord] {
        ReminderExpansion(schedule: ReminderSchedule(calendar: zoneCalendar)).expand(record, now: Date())
    }

    private static let appointmentListScript = """
    var listId = await CareApp.saveList({ name: 'Test Appointments', icon: 'stethoscope', color: 'charcoal', alerts: [
      { id: 'a1', kind: 'daysBefore', days: 1, time: '18:00', text: null },
      { id: 'a2', kind: 'morningOf', time: '08:00', text: null },
      { id: 'a3', kind: 'before', minutes: 60, text: null } ] });
    """

    private func createAppointment(_ webView: WKWebView, dateText: String) async throws -> String {
        let script = Self.appointmentListScript + """
        var itemId = await CareApp.saveReminder({ title: 'Dentist', list: listId, date: '\(dateText)', time: '13:00',
                                                  repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return itemId;
        """
        return try await runScript(webView, script)
    }

    func testAnAppointmentIsOneRecordCarryingItsListsRulesAndTheEngineExpandsTheOldFourReminders() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let eventDay = dayFromToday(3)
        let itemId = try await createAppointment(webView, dateText: dateText(eventDay))
        XCTAssertEqual(reminderKeys(store, itemId: itemId), ["reminder:\(itemId)"], "early alerts must not be records of their own")

        let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
        XCTAssertNil(value["kind"], "kind is retired")
        XCTAssertNil(value["body"], "body is retired")
        let rules = try XCTUnwrap(value["alerts"]?.arrayValue)
        XCTAssertEqual(rules.map { $0["id"]?.stringValue }, ["a1", "a2", "a3"])
        XCTAssertEqual(rules.map { $0["kind"]?.stringValue }, ["daysBefore", "morningOf", "before"])
        XCTAssertNil(rules[0]["text"], "a rule without wording leaves text out instead of null")

        let item = try parsedItem(store, itemId: itemId)
        let expanded = expand(item)
        XCTAssertEqual(expanded.map(\.identity.reminderId), [itemId, "\(itemId)~a1", "\(itemId)~a2", "\(itemId)~a3"])
        let event = moment(eventDay, hour: 13, minute: 0)
        let dayBefore = zoneCalendar.date(byAdding: .day, value: -1, to: eventDay)!
        XCTAssertEqual(expanded[0].at, event)
        XCTAssertEqual(expanded[1].at, moment(dayBefore, hour: 18, minute: 0))
        XCTAssertEqual(expanded[2].at, moment(eventDay, hour: 8, minute: 0))
        XCTAssertEqual(expanded[3].at, event.addingTimeInterval(-3600))
        let clock = ReminderExpansion.formatTime(event, zone: TimeZone(identifier: Self.zoneName)!)
        XCTAssertEqual(expanded[1].title, "Dentist tomorrow at \(clock)")
        XCTAssertEqual(expanded[2].title, "Dentist today at \(clock)")
        XCTAssertEqual(expanded[3].title, "Dentist in 1 hour")
        _ = waiter
    }

    func testDoneWrittenByTheShellOnAnEarlyAlertCompletesTheEventAndThePageShowsIt() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let itemId = try await createAppointment(webView, dateText: dateText(dayFromToday(3)))
        let key = "reminder:\(itemId)"
        let stored = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        let item = try parsedItem(store, itemId: itemId)
        // Exactly what the engine writes for Done on the day-before alert's notification.
        let afterDone = ReminderAction.done.apply(to: stored, part: .alert(ruleId: "a1"), occurrence: item.at, now: Date(), calendar: zoneCalendar)
        try store.set(sidekickId: Self.sidekickId, key: key, value: afterDone)

        try await reload(webView, waiter: waiter)
        let shown = try await runScript(webView, "return String(CareApp.state().items['\(itemId)'].done);")
        XCTAssertEqual(shown, "true", "the page does not show the event as done")
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: key)?["done"], .bool(true))
        XCTAssertEqual(expand(try parsedItem(store, itemId: itemId)).count, 1, "a done event books no more alerts")
    }

    func testEditingAListRuleRewritesTheRulesOnItsReminders() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let eventDay = dayFromToday(4)
        let script = """
        var listId = await CareApp.saveList({ name: 'Calls', icon: 'phone', color: 'teal', alerts: [
          { id: 'e1', kind: 'before', minutes: 60, text: null } ] });
        var first = await CareApp.saveReminder({ title: 'Mum', list: listId, date: '\(dateText(eventDay))', time: '10:00',
                                                 repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        var second = await CareApp.saveReminder({ title: 'Bank', list: listId, date: '\(dateText(eventDay))', time: '15:30',
                                                  repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        await CareApp.saveList({ id: listId, name: 'Calls', icon: 'phone', color: 'teal', alerts: [
          { id: 'e1', kind: 'before', minutes: 30, text: null } ] });
        return JSON.stringify([first, second]);
        """
        let ids = try JSONDecoder().decode([String].self, from: Data(try await runScript(webView, script).utf8))
        let expected: [(String, Date, String)] = [
            (ids[0], moment(eventDay, hour: 10, minute: 0), "Mum in 30 min"),
            (ids[1], moment(eventDay, hour: 15, minute: 30), "Bank in 30 min"),
        ]
        for (itemId, event, title) in expected {
            let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
            XCTAssertEqual(value["alerts"]?.arrayValue?.first?["minutes"], .number(30), "the rule on \(title) did not change")
            let alert = try XCTUnwrap(expand(try parsedItem(store, itemId: itemId)).last)
            XCTAssertEqual(alert.at, event.addingTimeInterval(-1800), "the alert of \(title) did not move")
            XCTAssertEqual(alert.title, title)
        }
        _ = waiter
    }

    func testAnHourlyReminderIsOneRecordWithEveryHoursAndNoRules() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let date = dateText(dayFromToday(1))
        // Appointments starts with three early alerts; an hourly reminder there gets none.
        let script = """
        var itemId = await CareApp.saveReminder({ title: 'Drops', list: 'appointments', date: '\(date)', time: '08:00',
                                                  repeatKey: 'every3h', timeZone: '\(Self.zoneName)' });
        return itemId;
        """
        let itemId = try await runScript(webView, script)
        XCTAssertEqual(reminderKeys(store, itemId: itemId), ["reminder:\(itemId)"], "hourly times must not be records of their own")
        let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
        XCTAssertEqual(value["everyHours"], .number(3))
        XCTAssertEqual(value["repeat"], .object(["every": .string("day")]))
        XCTAssertNil(value["alerts"], "an hourly reminder carries no early alerts")
        let expanded = expand(try parsedItem(store, itemId: itemId))
        XCTAssertEqual(expanded.count, 8)
        var times: Set<String> = []
        for slot in expanded {
            times.insert(ReminderExpansion.wallTime(of: slot.at, in: TimeZone(identifier: Self.zoneName)!))
        }
        XCTAssertEqual(times, ["08:00", "11:00", "14:00", "17:00", "20:00", "23:00", "02:00", "05:00"])

        // Back to Never: the field goes, and so do the times.
        _ = try await runScript(webView, """
        await CareApp.saveReminder({ id: '\(itemId)', title: 'Drops', list: 'appointments', date: '\(date)', time: '08:00',
                                     repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return 'saved';
        """)
        let never = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
        XCTAssertNil(never["everyHours"])
        XCTAssertNil(never["repeat"])
        XCTAssertEqual(never["alerts"]?.arrayValue?.count, 3, "a one-time reminder in Appointments gets its three rules back")
        _ = waiter
    }

    func testDoneOnAnHourlyTimeIsReadBackFromSlotsDone() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        // Every 4 hours from midnight yesterday: 00, 04, 08, 12, 16, 20.
        let script = """
        var itemId = await CareApp.saveReminder({ title: 'Pills', list: 'medicine', date: '\(dateText(dayFromToday(-1)))', time: '00:00',
                                                  repeatKey: 'every4h', timeZone: '\(Self.zoneName)' });
        return itemId;
        """
        let itemId = try await runScript(webView, script)
        let now = Date()
        let latestHour = (zoneCalendar.component(.hour, from: now) / 4) * 4
        let latestOccurrence = moment(dayFromToday(0), hour: latestHour, minute: 0)
        let key = "reminder:\(itemId)"
        let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
        let part: ReminderExpansion.Part = latestHour == 0 ? .item : .slot(time: String(format: "%02d:00", latestHour))
        try store.set(sidekickId: Self.sidekickId, key: key, value: ReminderAction.done.apply(to: value, part: part, occurrence: latestOccurrence, now: now, calendar: zoneCalendar))

        _ = try await runScript(webView, "await CareApp.sync(); return 'synced';")
        let shown = try await runScript(webView, "var s = CareLogic.displayState(CareApp.state().items['\(itemId)'], Date.now(), '\(Self.zoneName)'); return JSON.stringify(s);")
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(shown.utf8)) as? [String: Any])
        XCTAssertNotEqual(state["state"] as? String, "overdue", "the page still shows the time just done as due: \(shown)")
        if latestHour != 0 {
            let marks = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key)?["slotsDone"])
            XCTAssertNotNil(marks[String(format: "%02d:00", latestHour)])
        }
        _ = waiter
    }

    // Upgrade on read: the only test here allowed old shapes (docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md).
    func testOldAlertAndTimeRecordsAreFoldedIntoTheItemAndRemoved() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let eventDate = dateText(dayFromToday(3))
        // Records not yet converted: an item, its early alert (tapped Done) and an hourly time of
        // another item (tapped Done).
        try store.set(sidekickId: Self.sidekickId, key: "reminder:old", value: .object([
            "kind": .string("care-item"), "at": .string("\(eventDate)T20:00:00.000Z"), "title": .string("Old"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(false), "list": .string("meetings"),
        ]))
        try store.set(sidekickId: Self.sidekickId, key: "reminder:old~r1", value: .object([
            "kind": .string("care-alert"), "at": .string("\(eventDate)T19:00:00.000Z"), "title": .string("Old in 1 hour"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(true), "alertOf": .string("old"), "rule": .string("r1"),
            "occurrenceAt": .string("\(eventDate)T20:00:00.000Z"),
        ]))
        try store.set(sidekickId: Self.sidekickId, key: "reminder:hourly", value: .object([
            "kind": .string("care-item"), "at": .string("2026-10-01T15:00:00.000Z"), "title": .string("Water"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(false), "list": .string("water"), "repeat": .object(["every": .string("day")]), "everyHours": .number(4),
        ]))
        try store.set(sidekickId: Self.sidekickId, key: "reminder:hourly@1200", value: .object([
            "kind": .string("care-slot"), "at": .string("2026-10-01T19:00:00.000Z"), "title": .string("Water"), "body": .string(""),
            "timeZone": .string(Self.zoneName), "done": .bool(false), "repeat": .object(["every": .string("day")]), "slotOf": .string("hourly"),
            "time": .string("12:00"), "lastDoneAt": .string("2026-10-14T19:03:00.000Z"),
        ]))

        let (webView, waiter) = try await loadPage(store: store)
        _ = try await runScript(webView, "await CareApp.sync(); return 'synced';")

        XCTAssertEqual(reminderKeys(store, itemId: "old"), ["reminder:old"], "the old alert record was not removed")
        XCTAssertEqual(reminderKeys(store, itemId: "hourly"), ["reminder:hourly"], "the old time record was not removed")
        let old = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:old"))
        XCTAssertEqual(old["done"], .bool(true), "Done on the old alert did not complete the event")
        XCTAssertNil(old["kind"])
        XCTAssertNil(old["body"])
        XCTAssertEqual(old["alerts"]?.arrayValue?.first?["id"], .string("r1"), "Meetings' rule was not copied onto the item")
        let hourly = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:hourly"))
        XCTAssertEqual(hourly["slotsDone"]?["12:00"], .string("2026-10-14T19:03:00.000Z"), "the time's Done was not folded in")
        XCTAssertEqual(hourly["everyHours"], .number(4))
        _ = waiter
    }

    func testDeleteAndUndoKeepOneRecordPerReminderAndTheWidgetsSelectByType() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let eventDay = dayFromToday(2)
        let createScript = """
        var listId = await CareApp.saveList({ name: 'Physio', icon: 'barbell', color: 'forest', alerts: [
          { id: 'd1', kind: 'before', minutes: 60, text: null } ] });
        var first = await CareApp.saveReminder({ title: 'Stretch', list: listId, date: '\(dateText(eventDay))', time: '09:00',
                                                 repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return JSON.stringify([listId, first]);
        """
        let ids = try JSONDecoder().decode([String].self, from: Data(try await runScript(webView, createScript).utf8))
        _ = try await runScript(webView, "await CareApp.deleteList('\(ids[0])'); return 'deleted';")
        XCTAssertEqual(reminderKeys(store, itemId: ids[1]), [])
        _ = try await runScript(webView, "await CareApp.undo(); return 'restored';")
        XCTAssertEqual(reminderKeys(store, itemId: ids[1]), ["reminder:\(ids[1])"])
        XCTAssertEqual(expand(try parsedItem(store, itemId: ids[1])).map(\.identity.reminderId), [ids[1], "\(ids[1])~d1"], "Undo lost the rule")

        let meds = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "widget:meds"))
        XCTAssertEqual(meds["version"], .number(2))
        XCTAssertEqual(meds["sources"]?["today"]?["where"]?["$type"], .string("care.item"))
        XCTAssertNil(meds["sources"]?["today"]?["where"]?["kind"], "the widget still selects by the retired kind field")
        _ = waiter
    }
}
