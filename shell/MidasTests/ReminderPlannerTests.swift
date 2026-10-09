import XCTest
@testable import Midas

final class ReminderPlannerTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let now = ReminderRecord.parseDate(.string("2026-10-08T12:00:00-07:00"))!

    private var planner: ReminderPlanner {
        let schedule = ReminderSchedule(calendar: ReminderSchedule.phoneCalendar(timeZone: losAngeles))
        return ReminderPlanner(schedule: schedule)
    }

    private func reminder(_ reminderId: String, at: Date, title: String = "t", repeat repeatRule: RepeatRule? = nil,
                          done: Bool = false, snoozedUntil: Date? = nil, sidekickId: String = "reminders") -> ReminderRecord {
        let identity = ReminderIdentity(sidekickId: sidekickId, reminderId: reminderId)
        return ReminderRecord(identity: identity, at: at, title: title, body: "", repeatRule: repeatRule,
                              timeZone: nil, done: done, snoozedUntil: snoozedUntil)
    }

    private func minutes(_ count: Double) -> TimeInterval {
        count * 60
    }

    private func daily(interval: Int = 1) -> RepeatRule {
        RepeatRule(frequency: .day, interval: interval, weekdays: [], until: nil)
    }

    private func kinds(_ plan: ReminderPlan) -> [BookingKind] {
        plan.bookings.map(\.kind)
    }

    func testBooksOnlyTheSoonest48Of100() {
        var records: [ReminderRecord] = []
        for index in 0..<100 {
            let reminderAt = now.addingTimeInterval(minutes(Double(index + 1)))
            records.append(reminder("r\(String(format: "%03d", index))", at: reminderAt))
        }
        let plan = planner.plan(records: records.shuffled(), ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(plan.bookings.count, 48)
        let bookedReminderIds = plan.bookings.map(\.identity.reminderId)
        var expectedIds: [String] = []
        for index in 0..<48 {
            expectedIds.append("r\(String(format: "%03d", index))")
        }
        XCTAssertEqual(bookedReminderIds, expectedIds)
    }

    func testTiesAtTheBudgetEdgeAreBrokenTheSameWayEveryTime() {
        var records: [ReminderRecord] = []
        let sameMoment = now.addingTimeInterval(minutes(30))
        for index in 0..<60 {
            records.append(reminder("r\(index)", at: sameMoment, sidekickId: index % 2 == 0 ? "alpha" : "beta"))
        }
        let firstPlan = planner.plan(records: records.shuffled(), ledger: [:], previousBookings: [], now: now)
        let secondPlan = planner.plan(records: records.shuffled(), ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(firstPlan.bookings, secondPlan.bookings)
        XCTAssertEqual(firstPlan.bookings.first?.identity.sidekickId, "alpha")
    }

    func testEditKeepsTheIdentifierAndChangesTheContent() {
        let reminderAt = now.addingTimeInterval(minutes(10))
        let original = planner.plan(records: [reminder("a", at: reminderAt, title: "Old")], ledger: [:], previousBookings: [], now: now)
        let edited = planner.plan(records: [reminder("a", at: reminderAt, title: "New")], ledger: original.ledger, previousBookings: original.bookings, now: now)
        XCTAssertEqual(original.bookings.first?.identifier, edited.bookings.first?.identifier)
        XCTAssertEqual(edited.bookings.first?.title, "New")
    }

    func testMovingTheTimeChangesTheIdentifier() {
        let original = planner.plan(records: [reminder("a", at: now.addingTimeInterval(minutes(10)))], ledger: [:], previousBookings: [], now: now)
        let moved = planner.plan(records: [reminder("a", at: now.addingTimeInterval(minutes(20)))], ledger: original.ledger, previousBookings: original.bookings, now: now)
        XCTAssertNotEqual(original.bookings.first?.identifier, moved.bookings.first?.identifier)
        XCTAssertEqual(moved.bookings.count, 1)
    }

    func testDeletedReminderIsNotBookedAndLeavesTheLedger() {
        let original = planner.plan(records: [reminder("a", at: now.addingTimeInterval(minutes(10)))], ledger: [:], previousBookings: [], now: now)
        let afterDelete = planner.plan(records: [], ledger: original.ledger, previousBookings: original.bookings, now: now)
        XCTAssertEqual(afterDelete.bookings, [])
        XCTAssertEqual(afterDelete.ledger, [:])
    }

    func testDoneReminderIsNotBooked() {
        let plan = planner.plan(records: [reminder("a", at: now.addingTimeInterval(minutes(10)), done: true)], ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(plan.bookings, [])
    }

    func testDailyRepeatThatHasStartedIsOneRepeatingTrigger() {
        let started = now.addingTimeInterval(-minutes(60 * 3))
        let plan = planner.plan(records: [reminder("a", at: started, repeat: daily())], ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(kinds(plan), [.repeating])
        XCTAssertEqual(plan.bookings.first?.trigger, .repeating(DateComponents(hour: 9, minute: 0, second: 0)))
    }

    func testWeekdaysRepeatIsOneTriggerPerWeekday() {
        let started = now.addingTimeInterval(-minutes(60))
        let weekdays = RepeatRule(frequency: .week, interval: 1, weekdays: [1, 2, 3, 4, 5], until: nil)
        let plan = planner.plan(records: [reminder("a", at: started, repeat: weekdays)], ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(kinds(plan), [.repeating, .repeating, .repeating, .repeating, .repeating])
    }

    func testRepeatStartingNextWeekIsBookedOneByOneUntilItStarts() {
        let nextWeek = now.addingTimeInterval(7 * 24 * 3600)
        let record = reminder("a", at: nextWeek, repeat: daily())
        let beforeStart = planner.plan(records: [record], ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(beforeStart.bookings.first?.kind, .occurrence)
        XCTAssertEqual(beforeStart.bookings.first?.fireDate, nextWeek)

        let afterStart = planner.plan(records: [record], ledger: beforeStart.ledger, previousBookings: beforeStart.bookings, now: nextWeek.addingTimeInterval(60))
        XCTAssertEqual(kinds(afterStart), [.repeating])
    }

    func testEveryTwoDaysIsBookedOccurrenceByOccurrence() {
        let plan = planner.plan(records: [reminder("a", at: now.addingTimeInterval(60), repeat: daily(interval: 2))], ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(plan.bookings.count, 48)
        XCTAssertTrue(plan.bookings.allSatisfy(Self.isOccurrence))
        XCTAssertEqual(plan.bookings[1].fireDate.timeIntervalSince(plan.bookings[0].fireDate), 2 * 24 * 3600)
    }

    private static func isOccurrence(_ booking: PlannedBooking) -> Bool {
        booking.kind == .occurrence
    }

    func testOneTimeReminderInThePastFiresOnceAsMissed() {
        let record = reminder("a", at: now.addingTimeInterval(-minutes(5)))
        let firstRun = planner.plan(records: [record], ledger: [:], previousBookings: [], now: now)
        XCTAssertEqual(kinds(firstRun), [.missed])
        XCTAssertEqual(firstRun.bookings.first?.trigger, .immediately)

        let secondRun = planner.plan(records: [record], ledger: firstRun.ledger, previousBookings: firstRun.bookings, now: now.addingTimeInterval(60))
        XCTAssertEqual(secondRun.bookings, [])
    }

    func testDeliveredReminderIsNeitherRebookedNorMissed() {
        let reminderAt = now.addingTimeInterval(minutes(10))
        let record = reminder("a", at: reminderAt)
        let booked = planner.plan(records: [record], ledger: [:], previousBookings: [], now: now)
        let afterItFired = planner.plan(records: [record], ledger: booked.ledger, previousBookings: booked.bookings, now: reminderAt.addingTimeInterval(60))
        XCTAssertEqual(afterItFired.bookings, [])
    }

    func testReminderPushedOutByTheBudgetFiresAsMissedOnceItsTimePasses() {
        var records: [ReminderRecord] = []
        for index in 0..<48 {
            records.append(reminder("early\(index)", at: now.addingTimeInterval(minutes(Double(index + 1)))))
        }
        let lateComer = reminder("late", at: now.addingTimeInterval(minutes(100)))
        records.append(lateComer)
        let firstRun = planner.plan(records: records, ledger: [:], previousBookings: [], now: now)
        XCTAssertFalse(firstRun.bookings.contains(where: Self.isLateComer))

        // The app does not run again until long after "late" was due.
        let muchLater = now.addingTimeInterval(minutes(200))
        let secondRun = planner.plan(records: records, ledger: firstRun.ledger, previousBookings: firstRun.bookings, now: muchLater)
        XCTAssertEqual(kinds(secondRun), [.missed])
        XCTAssertEqual(secondRun.bookings.first?.identity.reminderId, "late")
    }

    private static func isLateComer(_ booking: PlannedBooking) -> Bool {
        booking.identity.reminderId == "late"
    }

    func testNewRepeatDoesNotReportItsPastOccurrencesAsMissed() {
        let longAgo = now.addingTimeInterval(-30 * 24 * 3600)
        let everyTwoDays = reminder("a", at: longAgo, repeat: daily(interval: 2))
        let plan = planner.plan(records: [everyTwoDays], ledger: [:], previousBookings: [], now: now)
        XCTAssertFalse(kinds(plan).contains(.missed))
    }

    func testRepeatOccurrencesMissedWhileUnbookedFireOnceNotOncePerOccurrence() {
        let everyTwoDays = reminder("a", at: now.addingTimeInterval(60), repeat: daily(interval: 2))
        let ledger: ReminderLedger = [everyTwoDays.identity.ledgerKey: now]
        // Nothing was booked (previousBookings empty) and ten days pass.
        let tenDaysLater = now.addingTimeInterval(10 * 24 * 3600)
        let plan = planner.plan(records: [everyTwoDays], ledger: ledger, previousBookings: [], now: tenDaysLater)
        let missedBookings = plan.bookings.filter(Self.isMissed)
        XCTAssertEqual(missedBookings.count, 1)
    }

    private static func isMissed(_ booking: PlannedBooking) -> Bool {
        booking.kind == .missed
    }

    func testSnoozeUsesTheReserveNotTheMainBudget() {
        var records: [ReminderRecord] = []
        for index in 0..<60 {
            records.append(reminder("r\(index)", at: now.addingTimeInterval(minutes(Double(index + 1)))))
        }
        let snoozedUntil = now.addingTimeInterval(minutes(10))
        records.append(reminder("snoozed", at: now.addingTimeInterval(-minutes(1)), snoozedUntil: snoozedUntil))
        let ledger: ReminderLedger = [ReminderIdentity(sidekickId: "reminders", reminderId: "snoozed").ledgerKey: now]
        let plan = planner.plan(records: records, ledger: ledger, previousBookings: [], now: now)
        let snoozeBookings = plan.bookings.filter(Self.isSnooze)
        XCTAssertEqual(plan.bookings.count, 49)
        XCTAssertEqual(snoozeBookings.count, 1)
        XCTAssertEqual(snoozeBookings.first?.fireDate, snoozedUntil)
    }

    func testSnoozesAreCappedAtTheReserve() {
        var records: [ReminderRecord] = []
        for index in 0..<20 {
            let snoozedUntil = now.addingTimeInterval(minutes(Double(index + 1)))
            records.append(reminder("s\(index)", at: now.addingTimeInterval(-minutes(1)), snoozedUntil: snoozedUntil))
        }
        var ledger: ReminderLedger = [:]
        for record in records {
            ledger[record.identity.ledgerKey] = now
        }
        let plan = planner.plan(records: records, ledger: ledger, previousBookings: [], now: now)
        XCTAssertEqual(plan.bookings.filter(Self.isSnooze).count, 16)
        XCTAssertLessThanOrEqual(plan.bookings.count, 64)
    }

    private static func isSnooze(_ booking: PlannedBooking) -> Bool {
        booking.kind == .snooze
    }

    func testSnoozeInThePastBooksNothing() {
        let record = reminder("a", at: now.addingTimeInterval(-minutes(30)), snoozedUntil: now.addingTimeInterval(-minutes(1)))
        let ledger: ReminderLedger = [record.identity.ledgerKey: now]
        let plan = planner.plan(records: [record], ledger: ledger, previousBookings: [], now: now)
        XCTAssertEqual(plan.bookings, [])
    }

    func testNeverMoreThan64BookingsWhateverTheInput() {
        var records: [ReminderRecord] = []
        for index in 0..<300 {
            let snoozedUntil = index % 3 == 0 ? now.addingTimeInterval(minutes(Double(index))) : nil
            let rule: RepeatRule? = index % 5 == 0 ? RepeatRule(frequency: .week, interval: 1, weekdays: [0, 1, 2, 3, 4, 5, 6], until: nil) : nil
            records.append(reminder("r\(index)", at: now.addingTimeInterval(minutes(Double(index) - 50)), repeat: rule, snoozedUntil: snoozedUntil))
        }
        let plan = planner.plan(records: records, ledger: [:], previousBookings: [], now: now)
        XCTAssertLessThanOrEqual(plan.bookings.count, 64)
        XCTAssertEqual(plan.bookings.count, 48 + 16)
    }
}
