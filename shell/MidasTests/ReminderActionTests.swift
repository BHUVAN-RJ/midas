import XCTest
@testable import Midas

final class ReminderActionTests: XCTestCase {
    private let calendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
    private let now = ReminderRecord.parseDate(.string("2026-10-08T22:30:00-07:00"))!
    private let oneTime: JSONValue = .object(["at": .string("2026-10-08T22:00:00-07:00"), "title": .string("t")])
    private let daily: JSONValue = .object(["at": .string("2026-10-08T22:00:00-07:00"), "title": .string("t"), "repeat": .object(["every": .string("day")])])

    private func snoozedUntil(_ value: JSONValue) -> Date? {
        ReminderRecord.parseDate(value["snoozedUntil"])
    }

    func testSnoozeLengths() {
        let tenMinutes = ReminderAction.snoozeTenMinutes.apply(to: oneTime, now: now, calendar: calendar)
        let oneHour = ReminderAction.snoozeOneHour.apply(to: oneTime, now: now, calendar: calendar)
        XCTAssertEqual(snoozedUntil(tenMinutes), now.addingTimeInterval(600))
        XCTAssertEqual(snoozedUntil(oneHour), now.addingTimeInterval(3600))
    }

    func testSnoozeUntilTomorrowIsNineTheNextMorningPhoneTime() {
        let snoozed = ReminderAction.snoozeUntilTomorrow.apply(to: oneTime, now: now, calendar: calendar)
        XCTAssertEqual(snoozedUntil(snoozed), ReminderRecord.parseDate(.string("2026-10-09T09:00:00-07:00")))
    }

    func testDoneCompletesAOneTimeReminder() {
        let snoozed = ReminderAction.snoozeOneHour.apply(to: oneTime, now: now, calendar: calendar)
        let done = ReminderAction.done.apply(to: snoozed, now: now, calendar: calendar)
        XCTAssertEqual(done["done"], .bool(true))
        XCTAssertNil(done["snoozedUntil"], "the snooze is removed, not set to null (rule: no null, 2026-10-15)")
        XCTAssertNil(done["lastDoneAt"])
    }

    func testDoneOnARepeatRecordsTheOccurrenceOnly() {
        let done = ReminderAction.done.apply(to: daily, now: now, calendar: calendar)
        XCTAssertNil(done["done"])
        XCTAssertEqual(ReminderRecord.parseDate(done["lastDoneAt"]), now)
    }

    func testActionsKeepTheSidekicksOwnFields() {
        let withExtra: JSONValue = .object(["at": .string("2026-10-08T22:00:00-07:00"), "title": .string("t"), "list": .string("groceries")])
        let snoozed = ReminderAction.snoozeTenMinutes.apply(to: withExtra, now: now, calendar: calendar)
        XCTAssertEqual(snoozed["list"], .string("groceries"))
        XCTAssertNil(ReminderRecord.validationError(snoozed))
    }
}
