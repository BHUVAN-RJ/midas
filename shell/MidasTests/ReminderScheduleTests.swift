import XCTest
@testable import Midas

/// The phone is in Los Angeles unless a test says otherwise. Expected times are written as
/// local wall-clock strings so a reader can check them against a calendar.
final class ReminderScheduleTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func schedule(in timeZone: TimeZone? = nil) -> ReminderSchedule {
        ReminderSchedule(calendar: ReminderSchedule.phoneCalendar(timeZone: timeZone ?? losAngeles))
    }

    private func date(_ isoText: String) -> Date {
        ReminderRecord.parseDate(.string(isoText))!
    }

    private func reminder(at isoText: String, repeat repeatRule: RepeatRule? = nil, timeZone: TimeZone? = nil) -> ReminderRecord {
        let identity = ReminderIdentity(sidekickId: "reminders", reminderId: "r")
        return ReminderRecord(identity: identity, at: date(isoText), title: "t", notes: "", repeatRule: repeatRule,
                              timeZone: timeZone, done: false, snoozedUntil: nil)
    }

    private func rule(_ frequency: RepeatFrequency, interval: Int = 1, weekdays: [Int] = [], until: String? = nil) -> RepeatRule {
        let untilDate = until.map(date)
        return RepeatRule(frequency: frequency, interval: interval, weekdays: weekdays, until: untilDate)
    }

    /// Formats dates as local "yyyy-MM-dd HH:mm EEE" in the given zone.
    private func localTimes(_ dates: [Date], in timeZone: TimeZone? = nil) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? losAngeles
        formatter.dateFormat = "yyyy-MM-dd HH:mm EEE"
        var formatted: [String] = []
        for occurrence in dates {
            formatted.append(formatter.string(from: occurrence))
        }
        return formatted
    }

    func testOneTimeReminderHasOneOccurrence() {
        let record = reminder(at: "2026-10-08T09:00:00-07:00")
        let beforeIt = schedule().occurrences(of: record, after: date("2026-10-08T08:00:00-07:00"), limit: 5)
        let afterIt = schedule().occurrences(of: record, after: date("2026-10-08T09:00:00-07:00"), limit: 5)
        XCTAssertEqual(beforeIt, [date("2026-10-08T09:00:00-07:00")])
        XCTAssertEqual(afterIt, [])
    }

    func testDailyKeepsNineOClockAcrossTheEndOfDaylightSaving() {
        // US daylight saving ends Sunday 2026-11-01.
        let record = reminder(at: "2026-10-30T09:00:00-07:00", repeat: rule(.day))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 4)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-30 09:00 Fri", "2026-10-31 09:00 Sat", "2026-11-01 09:00 Sun", "2026-11-02 09:00 Mon"])
        XCTAssertEqual(occurrences[2].timeIntervalSince(occurrences[1]), 25 * 3600)
    }

    func testDailyKeepsNineOClockAcrossTheStartOfDaylightSavingInNewYork() {
        // US daylight saving starts Sunday 2027-03-14.
        let record = reminder(at: "2027-03-13T09:00:00-05:00", repeat: rule(.day))
        let occurrences = schedule(in: newYork).occurrences(of: record, after: .distantPast, limit: 3)
        XCTAssertEqual(localTimes(occurrences, in: newYork), ["2027-03-13 09:00 Sat", "2027-03-14 09:00 Sun", "2027-03-15 09:00 Mon"])
        XCTAssertEqual(occurrences[1].timeIntervalSince(occurrences[0]), 23 * 3600)
    }

    func testEveryTwoDays() {
        let record = reminder(at: "2026-10-08T07:30:00-07:00", repeat: rule(.day, interval: 2))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 3)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-08 07:30 Thu", "2026-10-10 07:30 Sat", "2026-10-12 07:30 Mon"])
    }

    func testOccurrencesStartAfterTheLowerBound() {
        let record = reminder(at: "2026-10-08T07:30:00-07:00", repeat: rule(.day))
        let occurrences = schedule().occurrences(of: record, after: date("2026-10-20T08:00:00-07:00"), limit: 2)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-21 07:30 Wed", "2026-10-22 07:30 Thu"])
    }

    func testWeekdaysMondayWednesdayFriday() {
        // 2026-10-08 is a Thursday, so the first is Friday.
        let record = reminder(at: "2026-10-08T18:00:00-07:00", repeat: rule(.week, weekdays: [1, 3, 5]))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 4)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-09 18:00 Fri", "2026-10-12 18:00 Mon", "2026-10-14 18:00 Wed", "2026-10-16 18:00 Fri"])
    }

    func testWeeklyWithoutWeekdaysUsesTheStartDay() {
        let record = reminder(at: "2026-10-08T18:00:00-07:00", repeat: rule(.week))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 2)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-08 18:00 Thu", "2026-10-15 18:00 Thu"])
    }

    func testEveryTwoWeeksOnTuesday() {
        let record = reminder(at: "2026-10-06T10:00:00-07:00", repeat: rule(.week, interval: 2, weekdays: [2]))
        let occurrences = schedule().occurrences(of: record, after: date("2026-10-07T00:00:00-07:00"), limit: 2)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-20 10:00 Tue", "2026-11-03 10:00 Tue"])
    }

    func testMonthlyOnThe31stSkipsShortMonths() {
        let record = reminder(at: "2027-01-31T12:00:00-08:00", repeat: rule(.month))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 3)
        XCTAssertEqual(localTimes(occurrences), ["2027-01-31 12:00 Sun", "2027-03-31 12:00 Wed", "2027-05-31 12:00 Mon"])
    }

    func testEveryThreeMonthsCrossesTheYear() {
        let record = reminder(at: "2026-11-15T12:00:00-08:00", repeat: rule(.month, interval: 3))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 3)
        XCTAssertEqual(localTimes(occurrences), ["2026-11-15 12:00 Sun", "2027-02-15 12:00 Mon", "2027-05-15 12:00 Sat"])
    }

    func testYearlyOnFebruary29FiresInLeapYearsOnly() {
        let record = reminder(at: "2028-02-29T08:00:00-08:00", repeat: rule(.year))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 2)
        XCTAssertEqual(localTimes(occurrences), ["2028-02-29 08:00 Tue", "2032-02-29 08:00 Sun"])
    }

    func testUntilEndsTheRepeat() {
        let record = reminder(at: "2026-10-08T09:00:00-07:00", repeat: rule(.day, until: "2026-10-10T09:00:00-07:00"))
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 10)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-08 09:00 Thu", "2026-10-09 09:00 Fri", "2026-10-10 09:00 Sat"])
    }

    func testRepeatKeepsItsWallClockTimeWhenThePhoneMoves() {
        // Written as 9:00 in New York; the phone is now in Los Angeles: still 9:00, local.
        let record = reminder(at: "2026-10-08T09:00:00-04:00", repeat: rule(.day), timeZone: newYork)
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 2)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-08 09:00 Thu", "2026-10-09 09:00 Fri"])
    }

    func testOneTimeReminderIsAnExactMomentWhereverThePhoneIs() {
        let record = reminder(at: "2026-10-08T09:00:00-04:00", timeZone: newYork)
        let occurrences = schedule().occurrences(of: record, after: .distantPast, limit: 1)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-08 06:00 Thu"])
    }

    func testOldRepeatJumpsAheadInsteadOfWalkingYears() {
        let record = reminder(at: "2016-01-01T09:00:00-08:00", repeat: rule(.day))
        let startTime = Date()
        let occurrences = schedule().occurrences(of: record, after: date("2026-10-08T10:00:00-07:00"), limit: 1)
        XCTAssertLessThan(Date().timeIntervalSince(startTime), 0.05)
        XCTAssertEqual(localTimes(occurrences), ["2026-10-09 09:00 Fri"])
    }

    func testLatestOccurrenceFindsTheMostRecentPastOne() {
        let record = reminder(at: "2026-10-01T09:00:00-07:00", repeat: rule(.day))
        let latest = schedule().latestOccurrence(of: record, after: date("2026-10-03T00:00:00-07:00"), notAfter: date("2026-10-08T08:00:00-07:00"))
        XCTAssertEqual(latest, date("2026-10-07T09:00:00-07:00"))
        let nothing = schedule().latestOccurrence(of: record, after: date("2026-10-08T09:00:00-07:00"), notAfter: date("2026-10-09T08:00:00-07:00"))
        XCTAssertNil(nothing)
    }

    func testNativeRepeatComponentsOnlyForSimpleRepeats() {
        let daily = reminder(at: "2026-10-08T09:15:00-07:00", repeat: rule(.day))
        let weekdays = reminder(at: "2026-10-08T09:15:00-07:00", repeat: rule(.week, weekdays: [1, 3]))
        let monthly = reminder(at: "2026-10-08T09:15:00-07:00", repeat: rule(.month))
        let yearly = reminder(at: "2026-10-08T09:15:00-07:00", repeat: rule(.year))
        XCTAssertEqual(schedule().nativeRepeatComponents(of: daily), [DateComponents(hour: 9, minute: 15, second: 0)])
        XCTAssertEqual(schedule().nativeRepeatComponents(of: weekdays), [
            DateComponents(hour: 9, minute: 15, second: 0, weekday: 2),
            DateComponents(hour: 9, minute: 15, second: 0, weekday: 4),
        ])
        XCTAssertEqual(schedule().nativeRepeatComponents(of: monthly), [DateComponents(day: 8, hour: 9, minute: 15, second: 0)])
        XCTAssertEqual(schedule().nativeRepeatComponents(of: yearly), [DateComponents(month: 10, day: 8, hour: 9, minute: 15, second: 0)])

        let everyTwoDays = reminder(at: "2026-10-08T09:15:00-07:00", repeat: rule(.day, interval: 2))
        let ending = reminder(at: "2026-10-08T09:15:00-07:00", repeat: rule(.day, until: "2026-12-01T00:00:00-08:00"))
        let oneTime = reminder(at: "2026-10-08T09:15:00-07:00")
        XCTAssertNil(schedule().nativeRepeatComponents(of: everyTwoDays))
        XCTAssertNil(schedule().nativeRepeatComponents(of: ending))
        XCTAssertNil(schedule().nativeRepeatComponents(of: oneTime))
    }
}
