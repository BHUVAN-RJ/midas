import CryptoKit
import WebKit
import XCTest
@testable import Midas

// Done conformance (unified data plan, section 5): the page's Done and the native Done, run on
// the same records, give identical JSON. The Reminders page's `markDoneChange` and the
// care-reminders page's Done are compared with `ReminderChange.donePatch`, the patch the
// notification buttons and both widgets write through `RecordWriter`.

private struct ConformanceBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class ConformancePageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

@MainActor
final class DoneConformanceTests: XCTestCase {
    private static let zoneName = "America/Los_Angeles"
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "conformance-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private var zoneCalendar: Calendar {
        ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: Self.zoneName)!)
    }

    private func bundleHTML(_ sidekickId: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appending(path: "sidekicks/\(sidekickId)/index.html"), encoding: .utf8)
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

    private func loadPage(_ sidekickId: String, store: LocalRecordStore) async throws -> WKWebView {
        let html = try bundleHTML(sidekickId)
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        let loader = ConformanceBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = ConformancePageWaiter()
        let finished = expectation(description: "\(sidekickId) page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        pageWaiters.append(waiter)
        return webView
    }

    private var pageWaiters: [ConformancePageWaiter] = []

    private func runScript(_ webView: WKWebView, _ script: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(script, contentWorld: .page)
        return try XCTUnwrap(result as? String, "the script returned no text")
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func date(_ text: String) -> Date {
        ReminderRecord.parseDate(.string(text))!
    }

    // MARK: Reminders

    /// The page builds the record from an item, then applies its Done; the native side applies
    /// the Done patch to the same record. Both results must be the same JSON.
    func testRemindersPageDoneEqualsTheNativeDone() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let webView = try await loadPage("reminders", store: store)
        let nowIso = "2026-10-15T17:05:00.000Z"
        let occurrenceIso = "2026-10-15T17:00:00.000Z"
        let cases: [(name: String, item: String)] = [
            ("one-time with a snooze", "{ id: 'a', title: 'Call Amma', notes: 'Say hi', list: 'personal', date: '2026-10-15', time: '10:00', repeat: null, timeZone: '\(Self.zoneName)', done: false, completedAt: null, snoozedUntil: '2026-10-15T17:10:00.000Z', lastDoneAt: null, createdAt: '2026-10-01T00:00:00.000Z', source: null }"),
            ("undated", "{ id: 'b', title: 'Milk', notes: '', list: null, date: null, time: null, repeat: null, timeZone: '\(Self.zoneName)', done: false, completedAt: null, snoozedUntil: null, lastDoneAt: null, createdAt: null, source: null }"),
            ("daily repeat done through yesterday", "{ id: 'c', title: 'Gym', notes: '', list: 'personal', date: '2026-10-01', time: '10:00', repeat: { every: 'day' }, timeZone: '\(Self.zoneName)', done: false, completedAt: null, snoozedUntil: '2026-10-15T17:10:00.000Z', lastDoneAt: '2026-10-14T17:02:00.000Z', doneThrough: '2026-10-14T17:00:00.000Z', createdAt: '2026-10-01T00:00:00.000Z', source: null }"),
        ]
        for testCase in cases {
            let script = """
            var item = \(testCase.item);
            var record = RemindersLogic.recordFromItem(item, { extra: 'kept by every writer' });
            var fresh = RemindersLogic.itemFromRecord('reminder:' + item.id, record);
            RemindersLogic.markDoneChange('\(occurrenceIso)', '\(nowIso)')(fresh);
            var done = RemindersLogic.recordFromItem(fresh, record);
            return JSON.stringify({ record: record, done: done });
            """
            let outcome = try json(try await runScript(webView, script))
            let record = try XCTUnwrap(outcome["record"])
            let pageDone = try XCTUnwrap(outcome["done"])
            let patch = ReminderChange.donePatch(for: record, part: .item, occurrence: date(occurrenceIso), now: date(nowIso))
            let nativeDone = JSONMergePatch.apply(patch, to: record)
            XCTAssertEqual(nativeDone, pageDone, "\(testCase.name): the page's Done and the native Done differ")
            XCTAssertEqual(pageDone["extra"], .string("kept by every writer"), "\(testCase.name): the page dropped a field it does not know")
        }
    }

    // MARK: care-reminders

    /// The care page's Done on a saved reminder (one-time, and a daily repeat whose occurrence
    /// today has passed) equals the native Done on the record as it was before, for the same
    /// occurrence and the same moment.
    func testCarePageDoneEqualsTheNativeDone() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let webView = try await loadPage("care-reminders", store: store)
        _ = try await runScript(webView, "await CareApp.whenReady(); return 'ready';")
        let today = zoneCalendar.startOfDay(for: Date())
        let dayParts = zoneCalendar.dateComponents([.year, .month, .day], from: today)
        let todayText = String(format: "%04d-%02d-%02d", dayParts.year!, dayParts.month!, dayParts.day!)
        let tomorrow = zoneCalendar.date(byAdding: .day, value: 1, to: today)!
        let tomorrowParts = zoneCalendar.dateComponents([.year, .month, .day], from: tomorrow)
        let tomorrowText = String(format: "%04d-%02d-%02d", tomorrowParts.year!, tomorrowParts.month!, tomorrowParts.day!)

        let createScript = """
        var oneTime = await CareApp.saveReminder({ title: 'Dentist', list: 'appointments', date: '\(tomorrowText)', time: '13:00', repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        var daily = await CareApp.saveReminder({ title: 'Pills', list: 'medicine', date: '\(todayText)', time: '00:01', repeatKey: 'daily', timeZone: '\(Self.zoneName)' });
        return JSON.stringify([oneTime, daily]);
        """
        let ids = try JSONDecoder().decode([String].self, from: Data(try await runScript(webView, createScript).utf8))
        let schedule = ReminderSchedule(calendar: zoneCalendar)

        for (index, itemId) in ids.enumerated() {
            let key = "reminder:\(itemId)"
            let before = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: key))
            _ = try await runScript(webView, "await CareApp.markDone('\(itemId)'); return 'done';")
            let pageDone = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: key))
            // The page used its own clock; the native side uses the same moment.
            let pageMoment = try XCTUnwrap(ReminderRecord.parseDate(pageDone["completedAt"] ?? pageDone["lastDoneAt"]), "the page wrote no Done time")
            let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: "care-reminders", key: key, value: before))
            let occurrence = schedule.latestOccurrence(of: record, after: .distantPast, notAfter: pageMoment) ?? record.at
            let nativeDone = JSONMergePatch.apply(ReminderChange.donePatch(for: before, part: .item, occurrence: occurrence, now: pageMoment), to: before)
            XCTAssertEqual(nativeDone, pageDone, "care item \(index): the page's Done and the native Done differ")
            if index == 0 {
                let alertDone = JSONMergePatch.apply(ReminderChange.donePatch(for: before, part: .alert(ruleId: "r1"), occurrence: occurrence, now: pageMoment), to: before)
                XCTAssertEqual(alertDone, pageDone, "Done on an early alert must complete the event exactly as the page does")
            }
        }
    }
}
