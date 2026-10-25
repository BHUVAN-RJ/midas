import XCTest
@testable import Midas

// Hydration plan W3 (founder, 2026-10-25; docs/briefs/hydration-sidekick.md section 2.1): the
// streak source, `{ records: 'water:', streak: { field: 'ml', goal: '$settings.goalMl',
// dayGoalField: 'goalMl' } }`, gives `days`: the days in a row, back from today, whose `ml` met
// the goal (the day's own `goalMl` when it has one). An unmet today does not break it; a met
// today counts; a day with no record does.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let streakWidget = json(#"""
{ "name": "Water",
  "sources": { "settings": { "record": "settings:main" },
               "streak": { "records": "water:", "streak": { "field": "ml", "goal": "$settings.goalMl", "dayGoalField": "goalMl" } } },
  "small": { "text": "$streak.days day streak" } }
"""#)

final class SidekickWidgetStreakTests: XCTestCase {
    private let filler = SidekickWidgetFiller(calendar: calendarPT)

    private func day(_ date: String, _ fields: String) -> LocalRecord {
        return LocalRecord(sidekickId: "hydration", key: "water:\(date)", value: json(fields))
    }

    private func settings(goalMl: Int) -> LocalRecord {
        return LocalRecord(sidekickId: "hydration", key: "settings:main", value: json(#"{ "goalMl": \#(goalMl) }"#))
    }

    private func streakDays(_ records: [LocalRecord], at moment: Date, description: JSONValue = streakWidget) -> Double? {
        let scope = filler.sourceValues(description: description, sidekickRecords: records, at: moment)
        return scope["streak"]?["days"]?.numberValue
    }

    func testMetDaysBeforeAnUnmetTodayCount() {
        let records = [
            settings(goalMl: 2000),
            day("2026-10-22", #"{ "ml": 2100 }"#),
            day("2026-10-23", #"{ "ml": 2000 }"#),
            day("2026-10-24", #"{ "ml": 2500 }"#),
            day("2026-10-25", #"{ "ml": 500 }"#),
        ]
        XCTAssertEqual(streakDays(records, at: octoberPT(25, 15)), 3)
    }

    func testTodayCountsOnceItIsMet() {
        let records = [
            settings(goalMl: 2000),
            day("2026-10-24", #"{ "ml": 2500 }"#),
            day("2026-10-25", #"{ "ml": 2250 }"#),
        ]
        XCTAssertEqual(streakDays(records, at: octoberPT(25, 15)), 2)
    }

    func testAGapBreaksIt() {
        let records = [
            settings(goalMl: 2000),
            day("2026-10-20", #"{ "ml": 2500 }"#),
            day("2026-10-21", #"{ "ml": 2500 }"#),
            day("2026-10-23", #"{ "ml": 2500 }"#),
            day("2026-10-24", #"{ "ml": 2500 }"#),
        ]
        XCTAssertEqual(streakDays(records, at: octoberPT(25, 15)), 2)
        let unmetYesterday = [
            settings(goalMl: 2000),
            day("2026-10-23", #"{ "ml": 2500 }"#),
            day("2026-10-24", #"{ "ml": 1999 }"#),
        ]
        XCTAssertEqual(streakDays(unmetYesterday, at: octoberPT(25, 15)), 0)
    }

    func testEachDayKeepsTheGoalItHad() {
        // The goal went from 2000 to 3000 on the 25th: earlier days met their own 2000.
        let records = [
            settings(goalMl: 3000),
            day("2026-10-23", #"{ "ml": 2000, "goalMl": 2000 }"#),
            day("2026-10-24", #"{ "ml": 2100, "goalMl": 2000 }"#),
            day("2026-10-25", #"{ "ml": 3000, "goalMl": 3000 }"#),
        ]
        XCTAssertEqual(streakDays(records, at: octoberPT(25, 20)), 3)
        // Without its own goal, a day is held to the current one.
        let withoutDayGoal = [settings(goalMl: 3000), day("2026-10-24", #"{ "ml": 2100 }"#)]
        XCTAssertEqual(streakDays(withoutDayGoal, at: octoberPT(25, 20)), 0)
    }

    func testTheMidnightLookStartsTheNewDayUnmet() {
        let records = [
            settings(goalMl: 2000),
            day("2026-10-24", #"{ "ml": 2500 }"#),
            day("2026-10-25", #"{ "ml": 2500 }"#),
        ]
        let widgetRecord = LocalRecord(sidekickId: "hydration", key: "widget:water", value: streakWidget)
        let widget = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: widgetRecord, sidekickRecords: records + [widgetRecord], now: octoberPT(25, 22))
        guard case .text(let todayText)? = widget.looks[0].small, case .text(let midnightText)? = widget.looks[1].small else {
            return XCTFail("no text")
        }
        XCTAssertEqual(todayText.text, "2 day streak")
        XCTAssertEqual(midnightText.text, "2 day streak")
        XCTAssertEqual(streakDays(records, at: octoberPT(27, 9)), 0)
    }

    func testANumberGoalAndNoGoal() {
        let numberGoal = json(#"{ "name": "W", "sources": { "streak": { "records": "water:", "streak": { "field": "ml", "goal": 1000 } } }, "small": { "spacer": true } }"#)
        let records = [day("2026-10-24", #"{ "ml": 1000 }"#)]
        XCTAssertEqual(streakDays(records, at: octoberPT(25, 9), description: numberGoal), 1)
        // No goal anywhere: nothing can be met.
        let missingGoal = [day("2026-10-24", #"{ "ml": 1000 }"#)]
        XCTAssertEqual(streakDays(missingGoal, at: octoberPT(25, 9)), 0)
    }

    func testTheCheckerAcceptsAndRefuses() {
        XCTAssertNil(SidekickWidgetDescription.validationError(streakWidget))
        let noField = json(#"{ "name": "W", "sources": { "s": { "records": "water:", "streak": { "goal": 1000 } } }, "small": { "spacer": true } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(noField), "source s: streak needs field")
        let badGoal = json(#"{ "name": "W", "sources": { "s": { "records": "water:", "streak": { "field": "ml", "goal": "lots" } } }, "small": { "spacer": true } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(badGoal), "source s: streak goal must be a number or a binding")
        let withWhen = json(#"{ "name": "W", "sources": { "s": { "records": "reminder:", "when": "today", "streak": { "field": "ml", "goal": 1 } } }, "small": { "spacer": true } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(withWhen), "source s: streak and when cannot be used together")
    }
}
