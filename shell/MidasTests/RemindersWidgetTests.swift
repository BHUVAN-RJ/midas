import XCTest
@testable import Midas

// The Reminders widget (brief docs/briefs/widget-reminders.md, founder 2026-10-11): which
// reminders are in Today, their order, the first three, the count, the passed flag, circle
// colours, the shared file and the timeline dates.

private let pacificCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

/// A wall-clock moment in October 2026, Pacific time.
private func october(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return pacificCalendar.date(from: components)!
}

private func isoText(_ date: Date) -> JSONValue {
    .string(ReminderRecord.formatDate(date))
}

/// A `reminder:<id>` record of the Reminders Sidekick, as the Sidekick writes it.
private func reminderRecord(_ reminderId: String, title: String, at: Date, list: String? = nil,
                            extraFields: [String: JSONValue] = [:]) -> LocalRecord {
    var fields: [String: JSONValue] = [
        "at": isoText(at),
        "title": .string(title),
        "done": .bool(false),
        "timeZone": .string("America/Los_Angeles"),
    ]
    if let list {
        fields["list"] = .string(list)
    }
    for (fieldName, fieldValue) in extraFields {
        fields[fieldName] = fieldValue
    }
    return LocalRecord(sidekickId: "reminders", key: "reminder:" + reminderId, value: .object(fields))
}

private func listRecord(_ listId: String, color: String) -> LocalRecord {
    let fields: [String: JSONValue] = ["name": .string(listId), "color": .string(color)]
    return LocalRecord(sidekickId: "reminders", key: "list:" + listId, value: .object(fields))
}

private let dailyRepeat: JSONValue = .object(["every": .string("day")])

private func ids(_ reminders: [SharedReminder]) -> [String] {
    var reminderIds: [String] = []
    for reminder in reminders {
        reminderIds.append(reminder.id)
    }
    return reminderIds
}

private func rowIds(_ content: RemindersWidgetContent) -> [String] {
    guard case .reminders(_, let rows) = content else {
        return []
    }
    var reminderIds: [String] = []
    for row in rows {
        reminderIds.append(row.reminder.id)
    }
    return reminderIds
}

final class TodayReminderPlannerTests: XCTestCase {
    private let planner = TodayReminderPlanner(calendar: pacificCalendar)
    /// Sunday October 11 2026, 3:00 PM Pacific.
    private let now = october(11, 15)

    private func todayIds(_ records: [LocalRecord], lists: [LocalRecord] = [], at moment: Date? = nil) -> [String] {
        let todayReminders = planner.reminders(reminderRecords: records, listRecords: lists, now: moment ?? now)
        return ids(todayReminders)
    }

    // MARK: Membership

    func testLaterTodayIsInToday() {
        let records = [reminderRecord("call", title: "Call Amma", at: october(11, 18))]
        XCTAssertEqual(todayIds(records), ["call"])
    }

    func testPastDueTodayStaysInTodayUntilMidnight() {
        let records = [reminderRecord("reply", title: "Reply to a16z invite", at: october(11, 9))]
        XCTAssertEqual(todayIds(records), ["reply"])
        XCTAssertEqual(todayIds(records, at: october(11, 23, 59)), ["reply"])
        XCTAssertEqual(todayIds(records, at: october(12, 0, 1)), [])
    }

    func testYesterdayIsNotInToday() {
        let records = [reminderRecord("bill", title: "Pay electricity bill", at: october(10, 18))]
        XCTAssertEqual(todayIds(records), [])
    }

    func testTomorrowIsNotInToday() {
        let records = [reminderRecord("dentist", title: "Dentist", at: october(12, 10, 30))]
        XCTAssertEqual(todayIds(records), [])
    }

    func testUndatedIsNeverInToday() {
        // An undated reminder (no `at`) is never in Today.
        let undated = LocalRecord(sidekickId: "reminders", key: "reminder:haircut", value: .object(["title": .string("Book haircut")]))
        XCTAssertEqual(todayIds([undated]), [])
    }

    func testDoneIsNotInToday() {
        let records = [reminderRecord("gym", title: "Gym", at: october(11, 19), extraFields: ["done": .bool(true)])]
        XCTAssertEqual(todayIds(records), [])
    }

    func testDailyRepeatCountsWithTodaysOccurrence() throws {
        let records = [reminderRecord("gym", title: "Gym", at: october(1, 19, 30), extraFields: ["repeat": dailyRepeat])]
        let todayReminders = planner.reminders(reminderRecords: records, listRecords: [], now: now)
        XCTAssertEqual(ids(todayReminders), ["gym"])
        let gym = try XCTUnwrap(todayReminders.first)
        XCTAssertEqual(gym.at, october(11, 19, 30))
    }

    func testDailyRepeatMissedThisMorningIsInTodayAsPastDue() throws {
        let records = [reminderRecord("pills", title: "Pills", at: october(1, 9), extraFields: ["repeat": dailyRepeat])]
        let todayReminders = planner.reminders(reminderRecords: records, listRecords: [], now: now)
        let pills = try XCTUnwrap(todayReminders.first)
        XCTAssertEqual(pills.at, october(11, 9))
        XCTAssertTrue(pills.hasPassed(at: now))
    }

    func testDailyRepeatDoneForTodayLeavesToday() {
        let doneThisMorning = ["repeat": dailyRepeat, "lastDoneAt": isoText(october(11, 9, 5))]
        let records = [reminderRecord("pills", title: "Pills", at: october(1, 9), extraFields: doneThisMorning)]
        XCTAssertEqual(todayIds(records), [])
    }

    func testSnoozedFromYesterdayIntoTodayIsInToday() throws {
        let snoozed = ["snoozedUntil": isoText(october(11, 16))]
        let records = [reminderRecord("bill", title: "Pay electricity bill", at: october(10, 18), extraFields: snoozed)]
        let todayReminders = planner.reminders(reminderRecords: records, listRecords: [], now: now)
        let bill = try XCTUnwrap(todayReminders.first)
        XCTAssertEqual(bill.at, october(11, 16))
    }

    // MARK: Order, first three, count, passed

    private func fourToday() -> [LocalRecord] {
        return [
            reminderRecord("gym", title: "Gym", at: october(1, 19, 30), list: "personal", extraFields: ["repeat": dailyRepeat]),
            reminderRecord("call", title: "Call Amma", at: october(11, 18), list: "personal"),
            reminderRecord("reply", title: "Reply to a16z invite", at: october(11, 9), list: "midas"),
            reminderRecord("push", title: "Push reminders prototype", at: october(11, 14), list: "midas"),
        ]
    }

    func testSortedByTimeEarliestFirst() {
        XCTAssertEqual(todayIds(fourToday()), ["reply", "push", "call", "gym"])
    }

    // Timed reminders first, earliest first, then untimed ones (founder, 2026-10-11, docs/PRODUCT.md).
    // The all-day reminder shares reply's 9:00 moment, so only the allDay rule can put it last.
    func testUntimedComesAfterTimedReminders() {
        let allDay = reminderRecord("insurance", title: "Renew car insurance", at: october(11, 9), extraFields: ["allDay": .bool(true)])
        let records = fourToday() + [allDay]
        XCTAssertEqual(todayIds(records), ["reply", "push", "call", "gym", "insurance"])
    }

    func testAllDayNeverPassesDuringItsDay() throws {
        let allDay = reminderRecord("insurance", title: "Renew car insurance", at: october(11, 9), extraFields: ["allDay": .bool(true)])
        let todayReminders = planner.reminders(reminderRecords: [allDay], listRecords: [], now: now)
        let insurance = try XCTUnwrap(todayReminders.first)
        XCTAssertTrue(insurance.allDay)
        XCTAssertFalse(insurance.hasPassed(at: october(11, 23, 59)))
    }

    func testWidgetShowsFirstThreeAndCountsAll() {
        let days = planner.days(reminderRecords: fourToday(), listRecords: [], now: now)
        let file = SharedTodayReminders(days: days, savedAt: now)
        let content = RemindersWidgetLayout.content(file: file, now: now, calendar: pacificCalendar)
        guard case .reminders(let count, let rows) = content else {
            return XCTFail("expected rows, got \(content)")
        }
        XCTAssertEqual(count, 4)
        XCTAssertEqual(rowIds(content), ["reply", "push", "call"])
        XCTAssertEqual(rows.count, 3)
    }

    func testPassedFlagAtAGivenNow() {
        let days = planner.days(reminderRecords: fourToday(), listRecords: [], now: now)
        let file = SharedTodayReminders(days: days, savedAt: now)

        let atThree = RemindersWidgetLayout.content(file: file, now: now, calendar: pacificCalendar)
        guard case .reminders(_, let rowsAtThree) = atThree else {
            return XCTFail("expected rows")
        }
        XCTAssertEqual(rowsAtThree.map(\.hasPassed), [true, true, false])

        let atSix = RemindersWidgetLayout.content(file: file, now: october(11, 18), calendar: pacificCalendar)
        guard case .reminders(_, let rowsAtSix) = atSix else {
            return XCTFail("expected rows")
        }
        // 6:00 PM exactly counts as passed.
        XCTAssertEqual(rowsAtSix.map(\.hasPassed), [true, true, true])

        let atNoon = RemindersWidgetLayout.content(file: file, now: october(11, 12), calendar: pacificCalendar)
        guard case .reminders(_, let rowsAtNoon) = atNoon else {
            return XCTFail("expected rows")
        }
        XCTAssertEqual(rowsAtNoon.map(\.hasPassed), [true, false, false])
    }

    // MARK: Colours

    func testCircleTakesTheListColour() {
        let lists = [listRecord("personal", color: "blue"), listRecord("midas", color: "#ff9500"), listRecord("trips", color: "#0C8")]
        let records = [
            reminderRecord("call", title: "Call Amma", at: october(11, 18), list: "personal"),
            reminderRecord("push", title: "Push", at: october(11, 14), list: "midas"),
            reminderRecord("flight", title: "Flight", at: october(11, 20), list: "trips"),
        ]
        let todayReminders = planner.reminders(reminderRecords: records, listRecords: lists, now: now)
        var colorsById: [String: String] = [:]
        for reminder in todayReminders {
            colorsById[reminder.id] = reminder.colorHex
        }
        XCTAssertEqual(colorsById, ["call": "#007AFF", "push": "#FF9500", "flight": "#00CC88"])
    }

    func testNoListOrAMissingListFallsBackToBlue() {
        let lists = [listRecord("midas", color: "orange")]
        let records = [
            reminderRecord("loose", title: "Loose", at: october(11, 18)),
            reminderRecord("orphan", title: "Orphan", at: october(11, 19), list: "deleted-list"),
        ]
        let todayReminders = planner.reminders(reminderRecords: records, listRecords: lists, now: now)
        XCTAssertEqual(todayReminders.count, 2)
        for reminder in todayReminders {
            XCTAssertEqual(reminder.colorHex, "#007AFF")
        }
    }

    func testUnreadableListColourIsGreyAsInTheSidekick() {
        XCTAssertEqual(TodayReminderPlanner.normalizedColorHex("chartreuse"), "#8E8E93")
        XCTAssertEqual(TodayReminderPlanner.normalizedColorHex("#12345"), "#8E8E93")
        XCTAssertEqual(TodayReminderPlanner.normalizedColorHex(nil), "#8E8E93")
        XCTAssertEqual(TodayReminderPlanner.normalizedColorHex("#34c759ff"), "#34C759")
        XCTAssertEqual(TodayReminderPlanner.normalizedColorHex("Purple"), "#AF52DE")
    }

    // MARK: Tomorrow, for the midnight roll-over

    func testFileHoldsTodayAndTomorrowAndRollsOverAtMidnight() {
        let records = fourToday() + [reminderRecord("dentist", title: "Dentist", at: october(12, 10, 30), list: "personal")]
        let days = planner.days(reminderRecords: records, listRecords: [], now: now)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].dayStart, october(11, 0))
        XCTAssertEqual(days[1].dayStart, october(12, 0))
        XCTAssertEqual(ids(days[1].reminders), ["dentist", "gym"])

        let file = SharedTodayReminders(days: days, savedAt: now)
        let afterMidnight = RemindersWidgetLayout.content(file: file, now: october(12, 0), calendar: pacificCalendar)
        XCTAssertEqual(rowIds(afterMidnight), ["dentist", "gym"])
    }
}

final class RemindersWidgetLayoutTests: XCTestCase {
    private let now = october(11, 15)

    private func reminder(_ reminderId: String, at: Date, allDay: Bool = false) -> SharedReminder {
        SharedReminder(id: reminderId, title: reminderId, at: at, allDay: allDay, colorHex: "#007AFF")
    }

    private func file(today: [SharedReminder], tomorrow: [SharedReminder] = []) -> SharedTodayReminders {
        let days = [
            SharedRemindersDay(dayStart: october(11, 0), reminders: today),
            SharedRemindersDay(dayStart: october(12, 0), reminders: tomorrow),
        ]
        return SharedTodayReminders(days: days, savedAt: now)
    }

    func testNoFileShowsOpenMidas() {
        let content = RemindersWidgetLayout.content(file: nil, now: now, calendar: pacificCalendar)
        XCTAssertEqual(content, .empty)
    }

    func testAFileFromAnotherDayShowsOpenMidas() {
        let staleFile = file(today: [reminder("call", at: october(11, 18))])
        let content = RemindersWidgetLayout.content(file: staleFile, now: october(14, 9), calendar: pacificCalendar)
        XCTAssertEqual(content, .empty)
    }

    func testNothingLeftTodayShowsAllDone() {
        let emptyToday = file(today: [], tomorrow: [reminder("dentist", at: october(12, 10))])
        let content = RemindersWidgetLayout.content(file: emptyToday, now: now, calendar: pacificCalendar)
        XCTAssertEqual(content, .allDone)
    }

    func testTimelineHasEachTimeLaterTodayAndMidnight() {
        let todayReminders = [
            reminder("reply", at: october(11, 9)),
            reminder("call", at: october(11, 18)),
            reminder("gym", at: october(11, 19, 30)),
            reminder("also-gym", at: october(11, 19, 30)),
            reminder("insurance", at: october(11, 9), allDay: true),
        ]
        let dates = RemindersWidgetLayout.timelineDates(file: file(today: todayReminders), now: now, calendar: pacificCalendar)
        XCTAssertEqual(dates, [now, october(11, 18), october(11, 19, 30), october(12, 0)])
    }

    func testTimelineWithoutAFileIsNowAndMidnight() {
        let dates = RemindersWidgetLayout.timelineDates(file: nil, now: now, calendar: pacificCalendar)
        XCTAssertEqual(dates, [now, october(12, 0)])
    }

    func testTwelveHourTimes() {
        XCTAssertEqual(RemindersWidgetLayout.timeText(for: reminder("call", at: october(11, 18)), calendar: pacificCalendar), "6:00 PM")
        XCTAssertEqual(RemindersWidgetLayout.timeText(for: reminder("reply", at: october(11, 9)), calendar: pacificCalendar), "9:00 AM")
        XCTAssertEqual(RemindersWidgetLayout.timeText(for: reminder("late", at: october(11, 0, 5)), calendar: pacificCalendar), "12:05 AM")
        XCTAssertEqual(RemindersWidgetLayout.timeText(for: reminder("allday", at: october(11, 9), allDay: true), calendar: pacificCalendar), "")
    }

    func testWidgetWords() {
        XCTAssertEqual(RemindersWidgetCopy.displayName, "Reminders")
        XCTAssertEqual(RemindersWidgetCopy.description, "Today's reminders.")
        XCTAssertEqual(RemindersWidgetCopy.header, "Today")
        XCTAssertEqual(RemindersWidgetCopy.allDone, "All done")
        XCTAssertEqual(RemindersWidgetCopy.empty, "Open Midas")
        XCTAssertEqual(RemindersWidgetShared.kind, "com.bhuvanrj.midas.reminders")
    }

    func testTapOpensTheRemindersSidekick() {
        let link = MidasLink.openSidekick(id: RemindersWidgetShared.sidekickId)
        XCTAssertEqual(link.url.absoluteString, "midas://open/reminders")
    }

    // MARK: The shared file

    func testFileRoundTrip() throws {
        let original = file(today: [reminder("call", at: october(11, 18)), reminder("insurance", at: october(11, 9), allDay: true)])
        let decoded = try XCTUnwrap(SharedTodayReminders.decoded(from: try original.encoded()))
        XCTAssertEqual(decoded, original)
    }

    func testUnknownFormatVersionIsIgnored() throws {
        let original = file(today: [reminder("call", at: october(11, 18))])
        let encoded = try original.encoded()
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields["formatVersion"] = 99
        let futureData = try JSONSerialization.data(withJSONObject: fields)
        XCTAssertNil(SharedTodayReminders.decoded(from: futureData))
        XCTAssertNil(SharedTodayReminders.decoded(from: Data("not json".utf8)))
    }

    func testReaderReturnsNilWithoutAFile() {
        XCTAssertNil(SharedTodayRemindersReader.read(from: nil))
        let missingURL = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).json")
        XCTAssertNil(SharedTodayRemindersReader.read(from: missingURL))
    }
}

/// Counts widget reloads so a test can tell whether the publisher asked WidgetKit to redraw.
@MainActor
private final class WidgetReloadCounter {
    var count = 0

    func increment() {
        count += 1
    }
}

@MainActor
final class RemindersWidgetPublisherTests: XCTestCase {
    private var sharedFileURL: URL!
    private var storeFileURL: URL!
    private var reloads: WidgetReloadCounter!
    private var available = true

    override func setUp() async throws {
        let uniqueName = UUID().uuidString
        sharedFileURL = FileManager.default.temporaryDirectory.appending(path: "widget-reminders-\(uniqueName).json")
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "records-\(uniqueName).json")
        reloads = WidgetReloadCounter()
        available = true
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: sharedFileURL)
        try? FileManager.default.removeItem(at: storeFileURL)
    }

    private func makePublisher(store: LocalRecordStore, fileURL: URL?) -> RemindersWidgetPublisher {
        let counter = reloads!
        let fixedNow = october(11, 15)
        return RemindersWidgetPublisher(fileURL: fileURL, store: store,
                                        isAvailable: { self.available },
                                        now: { fixedNow },
                                        calendar: { pacificCalendar },
                                        reloadWidget: counter.increment)
    }

    private func readFile() throws -> SharedTodayReminders {
        let data = try Data(contentsOf: sharedFileURL)
        return try XCTUnwrap(SharedTodayReminders.decoded(from: data))
    }

    private func storeReminder(_ store: LocalRecordStore, _ record: LocalRecord) throws {
        try store.set(sidekickId: record.sidekickId, key: record.key, value: record.value)
    }

    func testPublishWritesTodayAndReloads() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        try storeReminder(store, reminderRecord("call", title: "Call Amma", at: october(11, 18)))
        let publisher = makePublisher(store: store, fileURL: sharedFileURL)

        publisher.publish()

        let savedFile = try readFile()
        XCTAssertEqual(ids(savedFile.reminders(on: october(11, 15), calendar: pacificCalendar) ?? []), ["call"])
        XCTAssertEqual(reloads.count, 1)
    }

    func testAReminderOrListChangeRepublishes() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let publisher = makePublisher(store: store, fileURL: sharedFileURL)
        publisher.startWatchingStore()

        try storeReminder(store, reminderRecord("call", title: "Call Amma", at: october(11, 18), list: "personal"))
        XCTAssertEqual(reloads.count, 1)
        XCTAssertEqual(try readFile().days[0].reminders.first?.colorHex, "#007AFF")

        let orangeList = listRecord("personal", color: "orange")
        try store.set(sidekickId: "reminders", key: orangeList.key, value: orangeList.value)
        XCTAssertEqual(reloads.count, 2)
        XCTAssertEqual(try readFile().days[0].reminders.first?.colorHex, "#FF9500")

        // Another Sidekick's records, or other keys of this one, leave the widget alone.
        try store.set(sidekickId: "groceries", key: "reminder:milk", value: reminderRecord("milk", title: "Milk", at: october(11, 17)).value)
        try store.set(sidekickId: "reminders", key: "settings:self", value: .object([:]))
        XCTAssertEqual(reloads.count, 2)
    }

    func testUnavailableRemovesTheFile() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let publisher = makePublisher(store: store, fileURL: sharedFileURL)
        publisher.publish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedFileURL.path))

        available = false
        publisher.publish()

        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedFileURL.path))
        XCTAssertEqual(reloads.count, 2)
    }

    func testDoesNothingWithoutAnAppGroup() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let publisher = makePublisher(store: store, fileURL: nil)
        publisher.publish()
        XCTAssertEqual(reloads.count, 0)
    }
}
