import XCTest
@testable import Midas

// Found by the hydration-sidekick agent, 2026-10-25: a records source with `sum` ignored `limit`
// for its totals, so a week chart (`{ records: 'water:', sum: 'ml', limit: 7 }`) got every day.
// With `limit`, items, count, sum and values cover the most recent N records by key, oldest
// first. Without `limit` the total is over every record, as before.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

final class SidekickWidgetSumLimitTests: XCTestCase {
    private let filler = SidekickWidgetFiller(calendar: calendarPT)
    private let moment = calendarPT.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!

    /// Ten days, 2026-10-16 (100 ml) to 2026-10-25 (1000 ml), stored out of order.
    private func tenDays() -> [LocalRecord] {
        var records: [LocalRecord] = []
        for dayOfMonth in [20, 25, 16, 18, 23, 17, 21, 24, 19, 22] {
            let millilitres = (dayOfMonth - 15) * 100
            let value = json(#"{ "ml": \#(millilitres) }"#)
            records.append(LocalRecord(sidekickId: "hydration", key: "water:2026-10-\(dayOfMonth)", value: value))
        }
        records.append(LocalRecord(sidekickId: "hydration", key: "settings:main", value: json(#"{ "goalMl": 2500 }"#)))
        return records
    }

    private func week(_ sourceText: String) -> JSONValue? {
        let description = json(#"{ "sources": { "week": \#(sourceText) } }"#)
        let scope = filler.sourceValues(description: description, sidekickRecords: tenDays(), at: moment)
        return scope["week"]
    }

    func testALimitedSumCoversTheLastSevenDays() {
        let week = week(#"{ "records": "water:", "sum": "ml", "limit": 7 }"#)
        // 2026-10-19 to 2026-10-25: 400 + 500 + ... + 1000.
        XCTAssertEqual(week?["sum"], .number(4900))
        XCTAssertEqual(week?["count"], .number(7))
        let expectedValues: [JSONValue] = [.number(400), .number(500), .number(600), .number(700), .number(800), .number(900), .number(1000)]
        XCTAssertEqual(week?["values"], .array(expectedValues))
        XCTAssertEqual(week?["items"]?.arrayValue?.count, 7)
        XCTAssertEqual(week?["items"]?.arrayValue?.first?["key"], .string("water:2026-10-19"))
        XCTAssertEqual(week?["items"]?.arrayValue?.last?["key"], .string("water:2026-10-25"))
    }

    func testASumWithoutLimitIsEveryRecordAsBefore() {
        let week = week(#"{ "records": "water:", "sum": "ml" }"#)
        XCTAssertEqual(week?["sum"], .number(5500))
        XCTAssertEqual(week?["count"], .number(10))
        XCTAssertEqual(week?["values"]?.arrayValue?.count, 10)
    }

    func testALimitAboveTheRecordsKeepsThemAll() {
        let week = week(#"{ "records": "water:", "sum": "ml", "limit": 30 }"#)
        XCTAssertEqual(week?["sum"], .number(5500))
        XCTAssertEqual(week?["values"]?.arrayValue?.first, .number(100))
    }
}
