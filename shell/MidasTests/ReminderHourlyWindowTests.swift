import XCTest
@testable import Midas

// Hydration plan N1 (founder, 2026-10-25; docs/briefs/hydration-sidekick.md section 2.2): an
// hourly reminder (`everyHours`) with `endTime: 'HH:MM'` runs from `at`'s time to `endTime`, not
// around the clock. 9:00 to 21:00 every 2 hours is 7 times and 7 slots; without `endTime` nothing
// changes.

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: losAngeles)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

final class ReminderHourlyWindowTests: XCTestCase {
    private let schedule = ReminderSchedule(calendar: calendarPT)

    private func waterValue(startHour: Int, endTime: String?) -> JSONValue {
        let at = ReminderRecord.formatDate(octoberPT(25, startHour))
        var endField = ""
        if let endTime {
            endField = #", "endTime": "\#(endTime)""#
        }
        return json(#"{ "title": "Drink water", "at": "\#(at)", "repeat": { "every": "day" }, "everyHours": 2, "timeZone": "America/Los_Angeles"\#(endField) }"#)
    }

    private func waterRecord(startHour: Int = 9, endTime: String?) -> ReminderRecord {
        return ReminderRecord.parse(sidekickId: "hydration", key: "reminder:water", value: waterValue(startHour: startHour, endTime: endTime))!
    }

    private func plannedBookings(_ record: ReminderRecord, now: Date) -> [PlannedBooking] {
        let expansion = ReminderExpansion(schedule: schedule)
        let planner = ReminderPlanner(schedule: schedule)
        let plan = planner.plan(records: expansion.expand(record, now: now), ledger: [:], previousBookings: [], now: now)
        return plan.bookings
    }

    func testNineToNineEveryTwoHoursIsSevenTimes() {
        let expansion = ReminderExpansion(schedule: schedule)
        let record = waterRecord(endTime: "21:00")
        XCTAssertEqual(expansion.timesOfDay(record), ["09:00", "11:00", "13:00", "15:00", "17:00", "19:00", "21:00"])
        XCTAssertEqual(expansion.hourlySlots(of: record).count, 6)
    }

    func testNineToNineEveryTwoHoursTakesSevenSlots() {
        let bookings = plannedBookings(waterRecord(endTime: "21:00"), now: octoberPT(25, 8))
        XCTAssertEqual(bookings.count, 7)
        for booking in bookings {
            XCTAssertEqual(booking.kind, .repeating)
        }
        var hours: Set<Int> = []
        for booking in bookings {
            hours.insert(calendarPT.component(.hour, from: booking.fireDate))
        }
        XCTAssertEqual(hours, [9, 11, 13, 15, 17, 19, 21])
    }

    func testWithoutEndTimeItIsAroundTheClockAsBefore() {
        let expansion = ReminderExpansion(schedule: schedule)
        let record = waterRecord(endTime: nil)
        XCTAssertEqual(expansion.timesOfDay(record).count, 12)
        XCTAssertEqual(expansion.timesOfDay(record).last, "07:00")
        XCTAssertEqual(plannedBookings(record, now: octoberPT(25, 8)).count, 12)
    }

    func testAWindowCanRunPastMidnight() {
        let expansion = ReminderExpansion(schedule: schedule)
        XCTAssertEqual(expansion.timesOfDay(waterRecord(startHour: 22, endTime: "02:00")), ["22:00", "00:00", "02:00"])
    }

    func testAnEndBetweenTimesStopsAtTheLastTimeBeforeIt() {
        let expansion = ReminderExpansion(schedule: schedule)
        XCTAssertEqual(expansion.timesOfDay(waterRecord(endTime: "14:30")), ["09:00", "11:00", "13:00"])
    }

    func testTheWidgetsHourlyTimesFollowTheWindow() {
        let expansion = ReminderExpansion(schedule: schedule)
        let stored = LocalRecord(sidekickId: "hydration", key: "reminder:water", value: waterValue(startHour: 9, endTime: "21:00"))
        var slotKeys: [String] = []
        for slotRecord in expansion.slotRecords(of: stored) {
            slotKeys.append(slotRecord.key)
        }
        XCTAssertEqual(slotKeys, ["reminder:water@1100", "reminder:water@1300", "reminder:water@1500", "reminder:water@1700",
                                  "reminder:water@1900", "reminder:water@2100"])
    }

    func testABadEndTimeIsRefused() {
        var value = waterValue(startHour: 9, endTime: "9pm")
        XCTAssertEqual(ReminderRecord.validationError(value), "reminder.endTime must be a time like 21:00")
        value = waterValue(startHour: 9, endTime: "24:00")
        XCTAssertEqual(ReminderRecord.validationError(value), "reminder.endTime must be a time like 21:00")
        value = waterValue(startHour: 9, endTime: "21:00")
        XCTAssertNil(ReminderRecord.validationError(value))
    }
}
