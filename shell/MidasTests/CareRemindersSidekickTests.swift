import CryptoKit
import WebKit
import XCTest
@testable import Midas

private struct CareRemindersBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class CareRemindersPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

/// The real care-reminders Sidekick (`sidekicks/care-reminders/index.html`) in a real WKWebView,
/// under the real CSP, writing through the scheme handler into the local store with reminder
/// validation on. Proves the records the page writes for lists with early-alert rules are the
/// ones the notification engine accepts, at the right moments and with the right wording, and
/// that Done written by the shell on one early alert completes the whole event.
@MainActor
final class CareRemindersSidekickTests: XCTestCase {
    private static let sidekickId = "care-reminders"
    private static let zoneName = "America/Los_Angeles"
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "care-reminders-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    // MARK: Loading the page

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

    private func loadPage(store: LocalRecordStore) async throws -> (WKWebView, CareRemindersPageWaiter) {
        let html = try bundleHTML()
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = CareRemindersBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = CareRemindersPageWaiter()
        let finished = expectation(description: "care reminders page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: Self.sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        try await waitUntilReady(webView)
        return (webView, waiter)
    }

    private func reload(_ webView: WKWebView, waiter: CareRemindersPageWaiter) async throws {
        let finished = expectation(description: "care reminders page reloaded")
        waiter.finished = finished
        webView.reload()
        await fulfillment(of: [finished], timeout: 10)
        try await waitUntilReady(webView)
    }

    /// Waits for the page's first load (starter lists, read-back of shell writes) to finish.
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

    // MARK: Helpers for dates in the reminders' zone

    private var zoneCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.zoneName)!
        return calendar
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

    private func storedDate(_ value: JSONValue?) -> Date? {
        ReminderRecord.parseDate(value?["at"])
    }

    /// Clock text as the page writes it in a notification title: "13:00" or "1:00 PM" by locale.
    private func normalizedClock(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        return spaced.lowercased()
    }

    private func reminderKeys(_ store: LocalRecordStore, itemId: String) -> [String] {
        var keys: [String] = []
        for record in store.query(sidekickId: Self.sidekickId, keyPrefix: "reminder:\(itemId)") {
            keys.append(record.key)
        }
        return keys
    }

    private static let appointmentListScript = """
    var listId = await CareApp.saveList({ name: 'Test Appointments', icon: 'stethoscope', color: 'charcoal', alerts: [
      { id: 'a1', kind: 'daysBefore', days: 1, time: '18:00', text: null },
      { id: 'a2', kind: 'morningOf', time: '08:00', text: null },
      { id: 'a3', kind: 'before', minutes: 60, text: null } ] });
    """

    private func createAppointment(_ webView: WKWebView, dateText: String) async throws -> String {
        let script = Self.appointmentListScript + """
        var ids = await CareApp.saveReminder({ title: 'Dentist', icon: 'tooth', list: listId, date: '\(dateText)', times: ['13:00'],
                                               repeatKey: 'never', timeZone: '\(Self.zoneName)', alertMode: 'list' });
        return ids[0];
        """
        return try await runScript(webView, script)
    }

    // MARK: Tests

    func testPageRunsUnderTheRealContentSecurityPolicyAndSeedsStarterLists() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        // textContent, not innerText: innerText needs layout and this web view has no window
        let rendered = try await runScript(webView, "return document.getElementById('main').textContent;")
        XCTAssertTrue(rendered.contains("Lists"), "the home screen did not render: \(rendered)")
        XCTAssertTrue(rendered.contains("Appointments"), "starter lists are not on the home screen: \(rendered)")
        let lists = store.query(sidekickId: Self.sidekickId, keyPrefix: "list:")
        var names: [String] = []
        for record in lists {
            names.append(record.value["name"]?.stringValue ?? "")
        }
        XCTAssertEqual(names.sorted(), ["Appointments", "Injections", "Medicine", "Meetings", "Water"])
        _ = waiter
    }

    func testAppointmentWithThreeRulesWritesFourRecordsTheEngineAccepts() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let eventDay = dayFromToday(3)
        let itemId = try await createAppointment(webView, dateText: dateText(eventDay))

        let keys = reminderKeys(store, itemId: itemId)
        XCTAssertEqual(keys, ["reminder:\(itemId)", "reminder:\(itemId)~a1", "reminder:\(itemId)~a2", "reminder:\(itemId)~a3"])
        var parsed: [String: ReminderRecord] = [:]
        for key in keys {
            let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
            parsed[key] = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value), "\(key) is not a valid reminder")
        }
        let event = moment(eventDay, hour: 13, minute: 0)
        let dayBefore = zoneCalendar.date(byAdding: .day, value: -1, to: eventDay)!
        XCTAssertEqual(parsed["reminder:\(itemId)"]?.at, event)
        XCTAssertEqual(parsed["reminder:\(itemId)~a1"]?.at, moment(dayBefore, hour: 18, minute: 0))
        XCTAssertEqual(parsed["reminder:\(itemId)~a2"]?.at, moment(eventDay, hour: 8, minute: 0))
        XCTAssertEqual(parsed["reminder:\(itemId)~a3"]?.at, event.addingTimeInterval(-3600))

        XCTAssertEqual(parsed["reminder:\(itemId)"]?.title, "Dentist")
        let clockChoices = ["13:00", "1:00 pm"]
        let dayBeforeTitle = normalizedClock(parsed["reminder:\(itemId)~a1"]?.title ?? "")
        let morningTitle = normalizedClock(parsed["reminder:\(itemId)~a2"]?.title ?? "")
        var dayBeforeMatches = false
        var morningMatches = false
        for clock in clockChoices {
            dayBeforeMatches = dayBeforeMatches || dayBeforeTitle == "dentist tomorrow at \(clock)"
            morningMatches = morningMatches || morningTitle == "dentist today at \(clock)"
        }
        XCTAssertTrue(dayBeforeMatches, "day-before wording is \(dayBeforeTitle)")
        XCTAssertTrue(morningMatches, "morning-of wording is \(morningTitle)")
        XCTAssertEqual(parsed["reminder:\(itemId)~a3"]?.title, "Dentist in 1 hour")
        XCTAssertEqual(parsed["reminder:\(itemId)~a1"]?.timeZone?.identifier, Self.zoneName)
        _ = waiter
    }

    func testAnAlertWhoseTimeHasAlreadyPassedIsSkipped() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let script = """
        var listId = await CareApp.saveList({ name: 'Soon', icon: 'bell', color: 'sky', alerts: [
          { id: 'p1', kind: 'before', minutes: 60, text: null },
          { id: 'p2', kind: 'daysBefore', days: 1, time: '18:00', text: null },
          { id: 'p3', kind: 'before', minutes: 10, text: null } ] });
        var soon = CareLogic.instantToWallClock(Date.now() + 30 * 60000, '\(Self.zoneName)');
        var ids = await CareApp.saveReminder({ title: 'Call', icon: 'phone', list: listId, date: soon.date, times: [soon.time],
                                               repeatKey: 'never', timeZone: '\(Self.zoneName)', alertMode: 'list' });
        return ids[0];
        """
        let itemId = try await runScript(webView, script)
        XCTAssertEqual(reminderKeys(store, itemId: itemId), ["reminder:\(itemId)", "reminder:\(itemId)~p3"],
                       "alerts 1 h before and the day before are already past and must not be written")
        _ = waiter
    }

    func testDoneWrittenByTheShellOnOneAlertCompletesTheEventAfterAReload() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let itemId = try await createAppointment(webView, dateText: dateText(dayFromToday(3)))
        XCTAssertEqual(reminderKeys(store, itemId: itemId).count, 4)

        // The shell's Done button on the day-before alert, exactly as the engine applies it
        let alertKey = "reminder:\(itemId)~a1"
        let stored = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: alertKey))
        let afterDone = ReminderAction.done.apply(to: stored, now: Date(), calendar: zoneCalendar)
        try store.set(sidekickId: Self.sidekickId, key: alertKey, value: afterDone)

        try await reload(webView, waiter: waiter)

        let item = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
        XCTAssertEqual(item["done"], .bool(true), "Done on an early alert did not complete the event")
        XCTAssertNil(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)~a2"), "the morning-of alert is still booked")
        XCTAssertNil(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)~a3"), "the 1 h alert is still booked")
    }

    func testDoneInThePageCompletesTheEventAndRemovesItsAlerts() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let itemId = try await createAppointment(webView, dateText: dateText(dayFromToday(3)))
        _ = try await runScript(webView, "await CareApp.markDone('\(itemId)'); return 'done';")
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)")?["done"], .bool(true))
        XCTAssertEqual(reminderKeys(store, itemId: itemId), ["reminder:\(itemId)"])

        _ = try await runScript(webView, "await CareApp.markNotDone('\(itemId)'); return 'undone';")
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)")?["done"], .bool(false))
        XCTAssertEqual(reminderKeys(store, itemId: itemId).count, 4, "Not Done did not book the alerts again")
        _ = waiter
    }

    func testEditingAListRuleRewritesTheAlertsOfItsReminders() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let eventDay = dayFromToday(4)
        let script = """
        var listId = await CareApp.saveList({ name: 'Calls', icon: 'phone', color: 'teal', alerts: [
          { id: 'e1', kind: 'before', minutes: 60, text: null } ] });
        var first = await CareApp.saveReminder({ title: 'Mum', icon: 'phone', list: listId, date: '\(dateText(eventDay))', times: ['10:00'],
                                                 repeatKey: 'never', timeZone: '\(Self.zoneName)', alertMode: 'list' });
        var second = await CareApp.saveReminder({ title: 'Bank', icon: 'phone', list: listId, date: '\(dateText(eventDay))', times: ['15:30'],
                                                  repeatKey: 'never', timeZone: '\(Self.zoneName)', alertMode: 'list' });
        await CareApp.saveList({ id: listId, name: 'Calls', icon: 'phone', color: 'teal', alerts: [
          { id: 'e1', kind: 'before', minutes: 30, text: null } ] });
        return JSON.stringify([first[0], second[0]]);
        """
        let idsText = try await runScript(webView, script)
        let ids = try JSONDecoder().decode([String].self, from: Data(idsText.utf8))
        let expected: [(String, Date, String)] = [
            (ids[0], moment(eventDay, hour: 10, minute: 0), "Mum in 30 min"),
            (ids[1], moment(eventDay, hour: 15, minute: 30), "Bank in 30 min"),
        ]
        for (itemId, event, title) in expected {
            let alert = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)~e1"))
            XCTAssertEqual(storedDate(alert), event.addingTimeInterval(-1800), "the alert of \(title) did not move")
            XCTAssertEqual(alert["title"]?.stringValue, title)
        }
        _ = waiter
    }

    func testDeletingAListRemovesItsRemindersAndUndoRestoresThem() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let eventDay = dayFromToday(2)
        let createScript = """
        var listId = await CareApp.saveList({ name: 'Physio', icon: 'barbell', color: 'forest', alerts: [
          { id: 'd1', kind: 'before', minutes: 60, text: null } ] });
        var first = await CareApp.saveReminder({ title: 'Stretch', icon: 'barbell', list: listId, date: '\(dateText(eventDay))', times: ['09:00'],
                                                 repeatKey: 'never', timeZone: '\(Self.zoneName)', alertMode: 'list' });
        var second = await CareApp.saveReminder({ title: 'Session', icon: 'barbell', list: listId, date: '\(dateText(eventDay))', times: ['17:00'],
                                                  repeatKey: 'never', timeZone: '\(Self.zoneName)', alertMode: 'list' });
        return JSON.stringify([listId, first[0], second[0]]);
        """
        let idsText = try await runScript(webView, createScript)
        let ids = try JSONDecoder().decode([String].self, from: Data(idsText.utf8))
        let listId = ids[0]
        let itemIds = [ids[1], ids[2]]

        _ = try await runScript(webView, "await CareApp.deleteList('\(listId)'); return 'deleted';")
        XCTAssertNil(store.get(sidekickId: Self.sidekickId, key: "list:\(listId)"))
        for itemId in itemIds {
            XCTAssertEqual(reminderKeys(store, itemId: itemId), [], "\(itemId) or its alerts survived the delete")
        }

        _ = try await runScript(webView, "await CareApp.undo(); return 'restored';")
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "list:\(listId)")?["name"]?.stringValue, "Physio")
        for itemId in itemIds {
            XCTAssertEqual(reminderKeys(store, itemId: itemId), ["reminder:\(itemId)", "reminder:\(itemId)~d1"], "Undo did not restore \(itemId)")
            let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
            XCTAssertNotNil(ReminderRecord.parse(sidekickId: Self.sidekickId, key: "reminder:\(itemId)", value: value))
        }
        _ = waiter
    }

    func testEveryTwoHoursFromEightToTenWritesEightDailyRepeats() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let today = dayFromToday(0)
        let script = """
        var listId = await CareApp.saveList({ name: 'Test Water', icon: 'drop', color: 'sky', alerts: [] });
        var times = CareLogic.timesEvery(2, '08:00', '22:00');
        var ids = await CareApp.saveReminder({ title: 'Water', icon: 'drop', list: listId, date: '\(dateText(today))', times: times,
                                               repeatKey: 'daily', timeZone: '\(Self.zoneName)', alertMode: 'list' });
        return JSON.stringify(ids);
        """
        let idsText = try await runScript(webView, script)
        let ids = try JSONDecoder().decode([String].self, from: Data(idsText.utf8))
        XCTAssertEqual(ids.count, 8)
        var hours: [Int] = []
        for itemId in ids {
            let key = "reminder:\(itemId)"
            XCTAssertEqual(reminderKeys(store, itemId: itemId), [key], "\(itemId) has records beyond its own")
            let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
            let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value))
            XCTAssertEqual(record.repeatRule?.frequency, .day)
            XCTAssertEqual(record.repeatRule?.interval, 1)
            XCTAssertNil(record.repeatRule?.until)
            hours.append(zoneCalendar.component(.hour, from: record.at))
        }
        XCTAssertEqual(hours.sorted(), [8, 10, 12, 14, 16, 18, 20, 22])
        _ = waiter
    }

    func testTheBundleUsesNoBrowserStorage() throws {
        let html = try bundleHTML()
        XCTAssertFalse(html.contains("localStorage"), "the bundle mentions localStorage")
        XCTAssertFalse(html.contains("indexedDB"), "the bundle mentions indexedDB")
        XCTAssertFalse(html.contains("sessionStorage"), "the bundle mentions sessionStorage")
    }
}
