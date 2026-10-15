import XCTest
@testable import Midas

// Early alerts and hourly times are fields on a reminder (unified data plan, phase 3: "care early
// alerts and hourly times as fields; engine expands them"). The expansion builds, in memory, the
// same reminders the care-reminders page used to write as records of their own, under the same
// ids (`<id>~<rule>`, `<id>@HHMM`), so the engine's ledger and bookings carry over.

final class ReminderExpansionTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private var calendar: Calendar {
        ReminderSchedule.phoneCalendar(timeZone: zone)
    }
    private var expansion: ReminderExpansion {
        ReminderExpansion(schedule: ReminderSchedule(calendar: calendar))
    }

    private func date(_ text: String) -> Date {
        ReminderRecord.parseDate(.string(text))!
    }

    private func record(_ key: String, _ fields: [String: JSONValue]) -> ReminderRecord {
        var allFields = fields
        allFields["timeZone"] = .string(zone.identifier)
        return ReminderRecord.parse(sidekickId: "care-reminders", key: key, value: .object(allFields))!
    }

    private let threeRules: JSONValue = .array([
        .object(["id": .string("a1"), "kind": .string("daysBefore"), "days": .number(1), "time": .string("18:00")]),
        .object(["id": .string("a2"), "kind": .string("morningOf"), "time": .string("08:00")]),
        .object(["id": .string("a3"), "kind": .string("before"), "minutes": .number(60)]),
    ])

    func testAnAppointmentWithThreeRulesExpandsToItselfAndThreeAlertsAtTheOldMoments() {
        let dentist = record("reminder:d1", ["title": .string("Dentist"), "at": .string("2026-10-18T13:00:00-07:00"), "alerts": threeRules])
        let now = date("2026-10-15T12:00:00-07:00")
        let expanded = expansion.expand(dentist, now: now)
        XCTAssertEqual(expanded.map(\.identity.reminderId), ["d1", "d1~a1", "d1~a2", "d1~a3"])
        XCTAssertEqual(expanded[1].at, date("2026-10-17T18:00:00-07:00"))
        XCTAssertEqual(expanded[2].at, date("2026-10-18T08:00:00-07:00"))
        XCTAssertEqual(expanded[3].at, date("2026-10-18T12:00:00-07:00"))
        let occurrence = date("2026-10-18T13:00:00-07:00")
        let clock = ReminderExpansion.formatTime(occurrence, zone: zone)
        XCTAssertEqual(expanded[1].title, "Dentist tomorrow at \(clock)")
        XCTAssertEqual(expanded[2].title, "Dentist today at \(clock)")
        XCTAssertEqual(expanded[3].title, "Dentist in 1 hour")
        for alert in expanded.dropFirst() {
            XCTAssertNil(alert.repeatRule)
            XCTAssertFalse(alert.done)
            XCTAssertEqual(alert.timeZone?.identifier, zone.identifier)
            XCTAssertTrue(alert.alerts.isEmpty, "an alert has no alerts of its own")
        }
    }

    func testAnAlertWhoseMomentPassedOrFallsAfterTheReminderIsSkippedAndADoneItemHasNone() {
        // Reminder in 30 minutes: 1 h before and the day before are past; 10 min before stays.
        let rules: JSONValue = .array([
            .object(["id": .string("p1"), "kind": .string("before"), "minutes": .number(60)]),
            .object(["id": .string("p2"), "kind": .string("daysBefore"), "days": .number(1), "time": .string("18:00")]),
            .object(["id": .string("p3"), "kind": .string("before"), "minutes": .number(10)]),
        ])
        let soon = record("reminder:s1", ["title": .string("Call"), "at": .string("2026-10-15T12:30:00-07:00"), "alerts": rules])
        let now = date("2026-10-15T12:00:00-07:00")
        XCTAssertEqual(expansion.expand(soon, now: now).map(\.identity.reminderId), ["s1", "s1~p3"])

        // Morning-of at 08:00 for a 07:00 reminder would come after it: skipped.
        let early = record("reminder:e1", ["title": .string("Run"), "at": .string("2026-10-18T07:00:00-07:00"), "alerts": threeRules])
        XCTAssertEqual(expansion.expand(early, now: now).map(\.identity.reminderId), ["e1", "e1~a1", "e1~a3"])

        var done = record("reminder:d2", ["title": .string("Dentist"), "at": .string("2026-10-18T13:00:00-07:00"), "alerts": threeRules, "done": .bool(true)])
        XCTAssertEqual(expansion.expand(done, now: now).count, 1)
        done = record("reminder:d3", ["title": .string("Plain"), "at": .string("2026-10-18T13:00:00-07:00")])
        XCTAssertEqual(expansion.expand(done, now: now).count, 1)
    }

    func testARepeatGetsAlertsForTheNextOccurrenceAfterWhatIsDone() {
        let daily = record("reminder:r1", [
            "title": .string("Pills"), "at": .string("2026-10-10T13:00:00-07:00"), "repeat": .object(["every": .string("day")]),
            "alerts": .array([.object(["id": .string("b1"), "kind": .string("before"), "minutes": .number(30)])]),
            "doneThrough": .string("2026-10-16T13:00:00-07:00"),
        ])
        let now = date("2026-10-15T12:00:00-07:00")
        let expanded = expansion.expand(daily, now: now)
        XCTAssertEqual(expanded.map(\.identity.reminderId), ["r1", "r1~b1"])
        // Oct 16 is done, so the alert serves Oct 17's occurrence.
        XCTAssertEqual(expanded[1].at, date("2026-10-17T12:30:00-07:00"))
        XCTAssertEqual(expansion.targetOccurrence(of: daily, now: now), date("2026-10-17T13:00:00-07:00"))
    }

    func testAPersonsOwnWordingIsUsedWithTheSamePlaceholders() {
        let rules: JSONValue = .array([.object(["id": .string("w1"), "kind": .string("daysBefore"), "days": .number(3), "time": .string("09:00"), "text": .string("Pack for {title}, {day} at {time}")])])
        let trip = record("reminder:t1", ["title": .string("the trip"), "at": .string("2026-10-20T06:00:00-07:00"), "alerts": rules])
        let now = date("2026-10-15T12:00:00-07:00")
        let alert = expansion.expand(trip, now: now)[1]
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date("2026-10-20T06:00:00-07:00"))
        XCTAssertEqual(alert.title, "Pack for the trip, \(weekday) at \(ReminderExpansion.formatTime(date("2026-10-20T06:00:00-07:00"), zone: zone))")
        XCTAssertEqual(alert.at, date("2026-10-17T09:00:00-07:00"))
    }

    func testEveryThreeHoursFromEightExpandsToTheFoundersEightTimes() {
        let pills = record("reminder:h1", [
            "title": .string("Pills"), "at": .string("2026-10-16T08:00:00-07:00"), "repeat": .object(["every": .string("day")]), "everyHours": .number(3),
            "alerts": threeRules, "slotsDone": .object(["14:00": .string("2026-10-16T14:05:00-07:00")]),
        ])
        XCTAssertEqual(expansion.timesOfDay(pills), ["08:00", "11:00", "14:00", "17:00", "20:00", "23:00", "02:00", "05:00"])
        let now = date("2026-10-15T12:00:00-07:00")
        let expanded = expansion.expand(pills, now: now)
        XCTAssertEqual(expanded.map(\.identity.reminderId), ["h1", "h1@1100", "h1@1400", "h1@1700", "h1@2000", "h1@2300", "h1@0200", "h1@0500"],
                       "an hourly item has its times and no early alerts")
        let dailyRule = RepeatRule(frequency: .day, interval: 1, weekdays: [], until: nil)
        for slot in expanded.dropFirst() {
            XCTAssertEqual(slot.repeatRule, dailyRule)
            XCTAssertEqual(slot.title, "Pills")
            XCTAssertGreaterThanOrEqual(slot.at, pills.at, "\(slot.identity.reminderId) starts before the reminder")
            XCTAssertLessThan(slot.at, pills.at.addingTimeInterval(24 * 3600), "\(slot.identity.reminderId) starts a day late")
        }
        // Times earlier in the day than 08:00 first come the next day.
        XCTAssertEqual(expanded[6].at, date("2026-10-17T02:00:00-07:00"))
        XCTAssertEqual(expanded[2].at, date("2026-10-16T14:00:00-07:00"))
        XCTAssertEqual(expanded[2].lastDoneAt, date("2026-10-16T14:05:00-07:00"), "Done on a time is read from slotsDone")
        XCTAssertNil(expanded[1].lastDoneAt)
    }

    func testTheEngineIdentifiersAndLedgerKeysAreTheOnesTheOldRecordsHad() {
        let dentist = record("reminder:d1", ["title": .string("Dentist"), "at": .string("2026-10-18T13:00:00-07:00"), "alerts": threeRules])
        let now = date("2026-10-15T12:00:00-07:00")
        let planner = ReminderPlanner(schedule: ReminderSchedule(calendar: calendar))
        let plan = planner.plan(records: expansion.expand(dentist, now: now), ledger: [:], previousBookings: [], now: now)
        let identifiers = plan.bookings.map(\.identifier).sorted()
        XCTAssertEqual(identifiers, [
            "reminder|care-reminders|d1|occurrence|1792353600",
            "reminder|care-reminders|d1~a1|occurrence|1792285200",
            "reminder|care-reminders|d1~a2|occurrence|1792335600",
            "reminder|care-reminders|d1~a3|occurrence|1792350000",
        ])
        XCTAssertEqual(Set(plan.ledger.keys), ["care-reminders/d1", "care-reminders/d1~a1", "care-reminders/d1~a2", "care-reminders/d1~a3"])
    }

    func testSplitTellsTheItemFromItsAlertsAndTimes() {
        XCTAssertEqual(ReminderExpansion.split(reminderId: "i1").itemId, "i1")
        XCTAssertEqual(ReminderExpansion.split(reminderId: "i1").part, .item)
        XCTAssertEqual(ReminderExpansion.split(reminderId: "i1~a2").itemId, "i1")
        XCTAssertEqual(ReminderExpansion.split(reminderId: "i1~a2").part, .alert(ruleId: "a2"))
        XCTAssertEqual(ReminderExpansion.split(reminderId: "i1@1400").itemId, "i1")
        XCTAssertEqual(ReminderExpansion.split(reminderId: "i1@1400").part, .slot(time: "14:00"))
    }

    func testDoneOnAnAlertOrATimeLandsOnTheItemRecord() {
        let now = date("2026-10-18T08:05:00-07:00")
        let oneTime: JSONValue = .object(["title": .string("Dentist"), "at": .string("2026-10-18T13:00:00-07:00"), "alerts": threeRules])
        let afterAlertDone = ReminderAction.done.apply(to: oneTime, part: .alert(ruleId: "a2"), occurrence: date("2026-10-18T13:00:00-07:00"), now: now, calendar: calendar)
        XCTAssertEqual(afterAlertDone["done"], .bool(true), "Done on an early alert completes the event (founder, 2026-10-12)")
        XCTAssertEqual(ReminderRecord.parseDate(afterAlertDone["completedAt"]), now)

        let daily: JSONValue = .object(["title": .string("Pills"), "at": .string("2026-10-10T13:00:00-07:00"), "repeat": .object(["every": .string("day")]), "doneThrough": .string("2026-10-16T13:00:00-07:00")])
        let afterRepeatAlertDone = ReminderAction.done.apply(to: daily, part: .alert(ruleId: "b1"), occurrence: date("2026-10-18T13:00:00-07:00"), now: now, calendar: calendar)
        XCTAssertNil(afterRepeatAlertDone["done"])
        XCTAssertEqual(ReminderRecord.parseDate(afterRepeatAlertDone["doneThrough"]), date("2026-10-18T13:00:00-07:00"))
        // doneThrough never moves back.
        let earlier = ReminderAction.done.apply(to: daily, part: .alert(ruleId: "b1"), occurrence: date("2026-10-12T13:00:00-07:00"), now: now, calendar: calendar)
        XCTAssertEqual(ReminderRecord.parseDate(earlier["doneThrough"]), date("2026-10-16T13:00:00-07:00"))

        let hourly: JSONValue = .object(["title": .string("Pills"), "at": .string("2026-10-16T08:00:00-07:00"), "repeat": .object(["every": .string("day")]), "everyHours": .number(4)])
        let afterSlotDone = ReminderAction.done.apply(to: hourly, part: .slot(time: "12:00"), occurrence: nil, now: now, calendar: calendar)
        XCTAssertEqual(afterSlotDone["slotsDone"]?["12:00"], .string(ReminderRecord.formatDate(now)))
        XCTAssertNil(afterSlotDone["lastDoneAt"], "a time's Done does not mark the item's own time")
        let secondSlot = ReminderAction.done.apply(to: afterSlotDone, part: .slot(time: "16:00"), occurrence: nil, now: now, calendar: calendar)
        XCTAssertEqual(secondSlot["slotsDone"]?["12:00"], .string(ReminderRecord.formatDate(now)), "an earlier time's Done is kept")
    }
}
