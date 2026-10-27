import XCTest
@testable import Midas

// A Reminders widget tick (brief docs/briefs/widget-reminders.md step 4, founder 2026-10-11) writes
// the record as the Sidekick does. Since 2026-10-26 (founder) Reminders makes its widget with the
// Sidekick widget builder, so the tick goes through SidekickWidgetPublisher; the native widget's
// paging and tick file were removed with it.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func iso(_ date: Date) -> JSONValue {
    .string(ReminderRecord.formatDate(date))
}

/// A widget tick on `reminder:<reminderId>` for the occurrence at `occurrence`, as the Reminders
/// Sidekick's widget sends it through the Sidekick widget builder.
private func tick(_ reminderId: String, occurrence: Date) -> WidgetTapAction {
    return WidgetTapAction(kind: .tick, sidekickId: "reminders", key: "reminder:" + reminderId, field: nil, amount: nil,
                           valueJSON: nil, occurrence: occurrence)
}

/// The record after the tick, or JSON null when the publisher changes nothing.
private func ticked(_ value: JSONValue, _ action: WidgetTapAction, now: Date) -> JSONValue {
    return SidekickWidgetPublisher.changedValue(value, by: action, now: now) ?? .null
}

final class RemindersWidgetTickValueTests: XCTestCase {
    private let now = octoberPT(11, 15)

    func testTickingAOneTimeReminderMarksItDoneAsTheSidekickDoes() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(11, 18)), "title": .string("Call Amma"), "done": .bool(false),
            "snoozedUntil": iso(octoberPT(11, 18, 10)), "list": .string("personal"),
        ])
        let tickedValue = ticked(value, tick("call", occurrence: octoberPT(11, 18)), now: now)
        XCTAssertEqual(tickedValue["done"], .bool(true))
        XCTAssertEqual(tickedValue["completedAt"], iso(now))
        XCTAssertNil(tickedValue["snoozedUntil"])
        XCTAssertNil(tickedValue["doneThrough"])
        XCTAssertEqual(tickedValue["list"], .string("personal"))
    }

    func testTickingARepeatRecordsTodaysOccurrenceAndCarriesOn() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(1, 19, 30)), "title": .string("Gym"), "done": .bool(false),
            "repeat": .object(["every": .string("day")]), "doneThrough": iso(octoberPT(10, 19, 30)),
        ])
        let tickedValue = ticked(value, tick("gym", occurrence: octoberPT(11, 19, 30)), now: now)
        XCTAssertEqual(tickedValue["done"], .bool(false))
        XCTAssertEqual(tickedValue["lastDoneAt"], iso(now))
        XCTAssertEqual(tickedValue["doneThrough"], iso(octoberPT(11, 19, 30)))
        XCTAssertNil(tickedValue["completedAt"])
    }

    func testTickingAnOlderOccurrenceNeverMovesDoneThroughBack() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(1, 9)), "title": .string("Pills"),
            "repeat": .object(["every": .string("day")]), "doneThrough": iso(octoberPT(12, 9)),
        ])
        let tickedValue = ticked(value, tick("pills", occurrence: octoberPT(11, 9)), now: now)
        XCTAssertEqual(tickedValue["doneThrough"], iso(octoberPT(12, 9)))
    }

    func testATickedRepeatLeavesTodayButComesBackTomorrow() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(1, 19, 30)), "title": .string("Gym"), "timeZone": .string("America/Los_Angeles"),
            "repeat": .object(["every": .string("day")]),
        ])
        let tickedValue = ticked(value, tick("gym", occurrence: octoberPT(11, 19, 30)), now: now)
        let record = LocalRecord(sidekickId: "reminders", key: "reminder:gym", value: tickedValue)
        let planner = TodayReminderPlanner(calendar: calendarPT)
        XCTAssertEqual(planner.reminders(reminderRecords: [record], listRecords: [], now: now).count, 0)
        XCTAssertEqual(planner.reminders(reminderRecords: [record], listRecords: [], now: octoberPT(12, 0)).count, 1)
    }
}
