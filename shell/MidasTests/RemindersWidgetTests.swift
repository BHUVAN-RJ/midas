import XCTest
@testable import Midas

// Which reminders are in Today, for the Sidekick widget's `when: 'today'` source (first written for
// the native Reminders widget, brief docs/briefs/widget-reminders.md, founder 2026-10-11; that
// widget was removed on 2026-10-26 and Reminders makes its own with the widget builder): their
// order, the passed flag, circle colours and the midnight roll-over.

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

    // MARK: Order, passed

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

    /// Whether each of the first three of Today has passed at `moment`.
    private func firstThreePassed(at moment: Date) -> [Bool] {
        let todayReminders = planner.reminders(reminderRecords: fourToday(), listRecords: [], now: now)
        var passedFlags: [Bool] = []
        for reminder in todayReminders.prefix(3) {
            passedFlags.append(reminder.hasPassed(at: moment))
        }
        return passedFlags
    }

    func testPassedFlagAtAGivenNow() {
        XCTAssertEqual(firstThreePassed(at: now), [true, true, false])
        // 6:00 PM exactly counts as passed.
        XCTAssertEqual(firstThreePassed(at: october(11, 18)), [true, true, true])
        XCTAssertEqual(firstThreePassed(at: october(11, 12)), [true, false, false])
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

    // MARK: Midnight roll-over

    func testTodayRollsOverAtMidnight() {
        let records = fourToday() + [reminderRecord("dentist", title: "Dentist", at: october(12, 10, 30), list: "personal")]
        XCTAssertEqual(todayIds(records, at: october(12, 0)), ["dentist", "gym"])
    }
}
