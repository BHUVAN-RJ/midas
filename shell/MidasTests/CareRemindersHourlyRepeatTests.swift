import CryptoKit
import WebKit
import XCTest
@testable import Midas

private struct HourlyRepeatBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class HourlyRepeatPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

/// Change 2 to the care-reminders Sidekick (founder, 2026-10-12): Repeat offers Every 2, 3 and
/// 4 Hours, around the clock from the reminder's Time. The engine has no hourly repeat, so each
/// time is its own daily-repeat `reminder:` record; the page shows them as one reminder.
/// Real page, real WKWebView, real CSP, real record validation.
@MainActor
final class CareRemindersHourlyRepeatTests: XCTestCase {
    private static let sidekickId = "care-reminders"
    private static let zoneName = "America/Los_Angeles"
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "care-hourly-\(UUID().uuidString).json")
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

    private func loadPage(store: LocalRecordStore) async throws -> (WKWebView, HourlyRepeatPageWaiter) {
        let html = try bundleHTML()
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = HourlyRepeatBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = HourlyRepeatPageWaiter()
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

    private var zoneCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.zoneName)!
        return calendar
    }

    private func dateText(daysFromToday offset: Int) -> String {
        let calendar = zoneCalendar
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: offset, to: today)!
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// The moment a wall-clock date and time names in Los Angeles.
    private func instant(daysFromToday offset: Int, hour: Int, minute: Int) -> Date {
        let calendar = zoneCalendar
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: offset, to: today)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func reminderKeys(_ store: LocalRecordStore, itemId: String) -> [String] {
        var keys: [String] = []
        for record in store.query(sidekickId: Self.sidekickId, keyPrefix: "reminder:\(itemId)") {
            keys.append(record.key)
        }
        return keys.sorted()
    }

    private func wallClockText(_ date: Date) -> String {
        let parts = zoneCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    private func saveScript(title: String, list: String, date: String, time: String, repeatKey: String) -> String {
        """
        var itemId = await CareApp.saveReminder({ title: '\(title)', list: '\(list)', date: '\(date)', time: '\(time)',
                                                  repeatKey: '\(repeatKey)', timeZone: '\(Self.zoneName)' });
        return itemId;
        """
    }

    func testEveryTwoThreeAndFourHoursWriteOneValidDailyRecordPerWallClockTime() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let start = instant(daysFromToday: 1, hour: 8, minute: 0)
        let cases: [(repeatKey: String, hours: Int)] = [("every2h", 2), ("every3h", 3), ("every4h", 4)]
        for testCase in cases {
            let itemId = try await runScript(webView, saveScript(title: "Pills", list: "medicine", date: dateText(daysFromToday: 1),
                                                                 time: "08:00", repeatKey: testCase.repeatKey))
            let keys = reminderKeys(store, itemId: itemId)
            XCTAssertEqual(keys.count, 24 / testCase.hours, "\(testCase.repeatKey) wrote \(keys)")
            var expectedTimes: [String] = []
            for slot in 0..<(24 / testCase.hours) {
                expectedTimes.append(String(format: "%02d:00", (8 + slot * testCase.hours) % 24))
            }
            var writtenTimes: [String] = []
            for key in keys {
                let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
                let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value), "\(key) is not a valid reminder")
                XCTAssertEqual(record.repeatRule, RepeatRule(frequency: .day, interval: 1, weekdays: [], until: nil), "\(key) is not a daily repeat")
                XCTAssertEqual(record.timeZone?.identifier, Self.zoneName, "\(key) has no time zone")
                XCTAssertEqual(record.title, "Pills")
                XCTAssertFalse(record.done)
                // The first occurrence is the next time it falls on or after the reminder's Date and Time
                XCTAssertGreaterThanOrEqual(record.at, start, "\(key) starts before the reminder")
                XCTAssertLessThan(record.at, start.addingTimeInterval(24 * 3600), "\(key) starts a day late")
                writtenTimes.append(wallClockText(record.at))
            }
            XCTAssertEqual(writtenTimes.sorted(), expectedTimes.sorted(), "\(testCase.repeatKey) times are wrong")
        }
        _ = waiter
    }

    func testEveryThreeHoursFromEightIsTheFoundersEightTimes() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let itemId = try await runScript(webView, saveScript(title: "Pills", list: "medicine", date: dateText(daysFromToday: 1),
                                                             time: "08:00", repeatKey: "every3h"))
        var writtenTimes: [String] = []
        for key in reminderKeys(store, itemId: itemId) {
            let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
            let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value))
            writtenTimes.append(wallClockText(record.at))
        }
        XCTAssertEqual(Set(writtenTimes), ["08:00", "11:00", "14:00", "17:00", "20:00", "23:00", "02:00", "05:00"])
        _ = waiter
    }

    func testAnHourlyReminderShowsAsOneRowAtItsNextTime() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let script = """
        var itemId = await CareApp.saveReminder({ title: 'Water', list: 'water', date: '\(dateText(daysFromToday: 1))', time: '09:00',
                                                  repeatKey: 'every2h', timeZone: '\(Self.zoneName)' });
        document.querySelector('[data-action="open-list"][data-id="water"]').click();
        var rows = document.querySelectorAll('#main .rows .row');
        var detail = rows.length > 0 ? rows[0].querySelector('.d').textContent : '';
        var item = CareApp.state().items[itemId];
        var expectedWhen = CareLogic.whenText(\(Int(instant(daysFromToday: 1, hour: 9, minute: 0).timeIntervalSince1970 * 1000)),
                                              Date.now(), CareLogic.deviceTimeZone());
        return JSON.stringify({ rows: rows.length, itemRows: document.querySelectorAll('.row[data-id="' + itemId + '"]').length,
                                items: Object.keys(CareApp.state().items).length, detail: detail, expectedWhen: expectedWhen,
                                repeat: item.repeat });
        """
        let outcome = try await runScript(webView, script)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(outcome.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["rows"] as? Int, 1, "the list shows more than one row for one hourly reminder")
        XCTAssertEqual(parsed["itemRows"] as? Int, 1)
        XCTAssertEqual(parsed["items"] as? Int, 1, "the page reads the time records as reminders of their own")
        // The first time is the reminder's own Date and Time, tomorrow 09:00 in Los Angeles
        let detail = parsed["detail"] as? String ?? ""
        let expectedWhen = try XCTUnwrap(parsed["expectedWhen"] as? String)
        XCTAssertEqual(detail.trimmingCharacters(in: .whitespaces), expectedWhen, "the row is not at its next time")
        let repeatValue = try XCTUnwrap(parsed["repeat"] as? [String: Any])
        XCTAssertEqual(repeatValue["every"] as? String, "hour")
        XCTAssertEqual(repeatValue["interval"] as? Int, 2)
        _ = waiter
    }

    func testTheEditSheetShowsTheHourlyChoiceAndTheThreeNewOptions() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let script = """
        var itemId = await CareApp.saveReminder({ title: 'Water', list: 'water', date: '\(dateText(daysFromToday: 1))', time: '09:00',
                                                  repeatKey: 'every4h', timeZone: '\(Self.zoneName)' });
        document.querySelector('[data-action="open-list"][data-id="water"]').click();
        document.querySelector('.row[data-id="' + itemId + '"]').click();
        var select = document.querySelector('#sheets select[data-field="repeatKey"]');
        var labels = [];
        for (var index = 0; index < select.options.length; index += 1) {
          labels.push(select.options[index].textContent);
        }
        var fields = [];
        var fieldElements = document.querySelectorAll('#sheets [data-field]');
        for (var fieldIndex = 0; fieldIndex < fieldElements.length; fieldIndex += 1) {
          fields.push(fieldElements[fieldIndex].getAttribute('data-field'));
        }
        return JSON.stringify({ selected: select.value, labels: labels, fields: fields });
        """
        let outcome = try await runScript(webView, script)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(outcome.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["selected"] as? String, "every4h", "editing loses the hourly choice")
        let labels = try XCTUnwrap(parsed["labels"] as? [String])
        XCTAssertEqual(Array(labels.suffix(3)), ["Every 2 Hours", "Every 3 Hours", "Every 4 Hours"])
        XCTAssertFalse(labels.contains("Custom"))
        XCTAssertEqual(parsed["fields"] as? [String], ["title", "date", "time", "repeatKey"], "the sheet gained fields")
        _ = waiter
    }

    func testSwitchingToNeverRemovesTheExtraRecords() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let date = dateText(daysFromToday: 2)
        let itemId = try await runScript(webView, saveScript(title: "Pills", list: "medicine", date: date, time: "08:00", repeatKey: "every3h"))
        XCTAssertEqual(reminderKeys(store, itemId: itemId).count, 8, "precondition: every 3 hours wrote 8 records")
        let editScript = """
        await CareApp.saveReminder({ id: '\(itemId)', title: 'Pills', list: 'medicine', date: '\(date)', time: '08:00',
                                     repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return 'saved';
        """
        _ = try await runScript(webView, editScript)
        XCTAssertEqual(reminderKeys(store, itemId: itemId), ["reminder:\(itemId)"])
        let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
        let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: "reminder:\(itemId)", value: value))
        XCTAssertNil(record.repeatRule, "the reminder still repeats after Never")
        XCTAssertNil(value["everyHours"], "the record still says it is hourly")
        _ = waiter
    }

    func testEditingTheTimeRewritesEveryRecord() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let date = dateText(daysFromToday: 2)
        let itemId = try await runScript(webView, saveScript(title: "Pills", list: "medicine", date: date, time: "08:00", repeatKey: "every4h"))
        let editScript = """
        await CareApp.saveReminder({ id: '\(itemId)', title: 'Tablets', list: 'medicine', date: '\(date)', time: '09:30',
                                     repeatKey: 'every4h', timeZone: '\(Self.zoneName)' });
        return 'saved';
        """
        _ = try await runScript(webView, editScript)
        let keys = reminderKeys(store, itemId: itemId)
        XCTAssertEqual(keys.count, 6)
        var writtenTimes: [String] = []
        for key in keys {
            let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key))
            let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: Self.sidekickId, key: key, value: value))
            XCTAssertEqual(record.title, "Tablets", "\(key) kept the old title")
            writtenTimes.append(wallClockText(record.at))
        }
        XCTAssertEqual(Set(writtenTimes), ["09:30", "13:30", "17:30", "21:30", "01:30", "05:30"])
        _ = waiter
    }

    func testDeletingAnHourlyReminderRemovesAllItsRecords() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let itemId = try await runScript(webView, saveScript(title: "Water", list: "water", date: dateText(daysFromToday: 1), time: "07:00", repeatKey: "every2h"))
        XCTAssertEqual(reminderKeys(store, itemId: itemId).count, 12, "precondition: every 2 hours wrote 12 records")
        let deleteScript = """
        document.querySelector('[data-action="open-list"][data-id="water"]').click();
        document.querySelector('.row[data-id="\(itemId)"]').click();
        document.querySelector('#sheets [data-action="delete-reminder"]').click();
        await CareApp.sync();
        return String(document.querySelectorAll('.row[data-id="\(itemId)"]').length);
        """
        let rowsLeft = try await runScript(webView, deleteScript)
        XCTAssertEqual(rowsLeft, "0")
        XCTAssertEqual(reminderKeys(store, itemId: itemId), [], "records left after Delete")
        _ = waiter
    }

    func testAnHourlyReminderInAListWithAlertsWritesNoEarlyAlerts() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let date = dateText(daysFromToday: 2)
        // Appointments starts with three early alerts: a daily reminder there gets them
        let dailyId = try await runScript(webView, saveScript(title: "Check", list: "appointments", date: date, time: "13:00", repeatKey: "daily"))
        let dailyAlerts = reminderKeys(store, itemId: dailyId).filter { $0.contains("~") }
        XCTAssertFalse(dailyAlerts.isEmpty, "precondition: a daily reminder in Appointments has early alerts")
        let hourlyId = try await runScript(webView, saveScript(title: "Drops", list: "appointments", date: date, time: "13:00", repeatKey: "every2h"))
        let hourlyKeys = reminderKeys(store, itemId: hourlyId)
        XCTAssertEqual(hourlyKeys.count, 12)
        XCTAssertEqual(hourlyKeys.filter { $0.contains("~") }, [], "early alerts were written for an hourly repeat")
        // Changing a daily reminder with alerts to hourly removes its alerts
        let editScript = """
        await CareApp.saveReminder({ id: '\(dailyId)', title: 'Check', list: 'appointments', date: '\(date)', time: '13:00',
                                     repeatKey: 'every3h', timeZone: '\(Self.zoneName)' });
        return 'saved';
        """
        _ = try await runScript(webView, editScript)
        let editedKeys = reminderKeys(store, itemId: dailyId)
        XCTAssertEqual(editedKeys.count, 8)
        XCTAssertEqual(editedKeys.filter { $0.contains("~") }, [], "the old early alerts stayed")
        _ = waiter
    }

    func testTheOver48CountIncludesEveryTimeRecord() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        let script = """
        var before = CareApp.bookings();
        await CareApp.saveReminder({ title: 'Water', list: 'water', date: '\(dateText(daysFromToday: 1))', time: '07:00',
                                     repeatKey: 'every2h', timeZone: '\(Self.zoneName)' });
        var afterTwo = CareApp.bookings();
        await CareApp.saveReminder({ title: 'Pills', list: 'medicine', date: '\(dateText(daysFromToday: 1))', time: '08:00',
                                     repeatKey: 'every4h', timeZone: '\(Self.zoneName)' });
        var afterFour = CareApp.bookings();
        return JSON.stringify([before, afterTwo, afterFour]);
        """
        let outcome = try await runScript(webView, script)
        let counts = try JSONDecoder().decode([Int].self, from: Data(outcome.utf8))
        XCTAssertEqual(counts, [0, 12, 18])
        // Four every-2-hours reminders (48) and one more is over 48: the list sheet warns
        let warnScript = """
        for (var index = 0; index < 3; index += 1) {
          await CareApp.saveReminder({ title: 'More', list: 'water', date: '\(dateText(daysFromToday: 1))', time: '07:00',
                                       repeatKey: 'every2h', timeZone: '\(Self.zoneName)' });
        }
        document.querySelector('[data-action="open-list"][data-id="water"]').click();
        document.querySelector('[data-action="edit-list"]').click();
        return document.querySelector('#sheets .warn') ? document.querySelector('#sheets .warn').textContent : 'no warning';
        """
        let warning = try await runScript(webView, warnScript)
        XCTAssertEqual(warning, "Over 48 alerts. Later ones may come late.")
        _ = waiter
    }

    func testDoneTappedOnOneTimesNotificationIsReadBack() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let (webView, waiter) = try await loadPage(store: store)
        // Every 4 hours from midnight yesterday: 00, 04, 08, 12, 16, 20
        let itemId = try await runScript(webView, saveScript(title: "Pills", list: "medicine", date: dateText(daysFromToday: -1),
                                                             time: "00:00", repeatKey: "every4h"))
        let now = Date()
        let currentHour = zoneCalendar.component(.hour, from: now)
        let latestHour = (currentHour / 4) * 4
        let latestOccurrence = instant(daysFromToday: 0, hour: latestHour, minute: 0)
        let key = latestHour == 0 ? "reminder:\(itemId)" : String(format: "reminder:\(itemId)@%02d00", latestHour)
        // What the shell's Done button writes on that time's record
        let value = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key), "no record for \(latestHour):00")
        try store.set(sidekickId: Self.sidekickId, key: key, value: ReminderAction.done.apply(to: value, now: now, calendar: zoneCalendar))
        _ = try await runScript(webView, "await CareApp.sync(); return 'synced';")
        let item = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)"))
        let doneThrough = try XCTUnwrap(item["doneThrough"]?.stringValue, "the page did not read back the Done")
        XCTAssertEqual(ReminderRecord.parseDate(.string(doneThrough)), latestOccurrence)
        _ = waiter
    }
}
