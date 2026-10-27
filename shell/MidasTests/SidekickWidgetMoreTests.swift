import XCTest
@testable import Midas

// "+N more" (founder, 2026-10-26: approved instead of page arrows): a list piece can show how many
// items did not fit, `more: '+$more more'`, under its rows. Any Sidekick can use it.

private let moreCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func moreJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// `count` plain records, `task:1` … `task:<count>`.
private func taskRecords(_ count: Int) -> [LocalRecord] {
    var records: [LocalRecord] = []
    for index in 0..<count {
        records.append(LocalRecord(sidekickId: "tasks", key: "task:\(index + 1)", value: .object(["title": .string("Task \(index + 1)")])))
    }
    return records
}

private func filledList(_ listFields: String, records: [LocalRecord]) -> WidgetStackPiece? {
    let description = moreJSON(#"{ "name": "Tasks", "sources": { "tasks": { "records": "task:" } }, "small": { "list": "$tasks.items", "row": { "text": "$item.title" }\#(listFields) } }"#)
    let widgetRecord = LocalRecord(sidekickId: "tasks", key: "widget:tasks", value: description)
    let filler = SidekickWidgetFiller(calendar: moreCalendar)
    let widget = filler.fill(sidekickId: "tasks", sidekickName: "Tasks", record: widgetRecord, sidekickRecords: records, now: Date())
    guard case .vstack(let column)? = widget.looks.first?.small else {
        return nil
    }
    return column
}

private func rowTexts(_ column: WidgetStackPiece?) -> [String] {
    var texts: [String] = []
    for child in column?.children ?? [] {
        if case .text(let textPiece) = child {
            texts.append(textPiece.text)
        }
    }
    return texts
}

final class SidekickWidgetMoreTests: XCTestCase {
    func testItemsThatDidNotFitAreCountedUnderTheRows() throws {
        let column = try XCTUnwrap(filledList(#", "limit": 3, "more": "+$more more""#, records: taskRecords(5)))
        XCTAssertEqual(rowTexts(column), ["Task 1", "Task 2", "Task 3", "+2 more"])
        guard case .text(let moreLine)? = column.children.last else {
            return XCTFail("no more line")
        }
        XCTAssertEqual(moreLine.style, .caption)
        XCTAssertTrue(moreLine.isSecondary, "grey, under the rows")
        XCTAssertEqual(moreLine.lineLimit, 1)
    }

    func testEverythingFitsNoMoreLine() {
        let column = filledList(#", "limit": 3, "more": "+$more more""#, records: taskRecords(3))
        XCTAssertEqual(rowTexts(column), ["Task 1", "Task 2", "Task 3"])
    }

    func testWithoutMoreNothingIsAdded() {
        let column = filledList(#", "limit": 3"#, records: taskRecords(5))
        XCTAssertEqual(rowTexts(column), ["Task 1", "Task 2", "Task 3"])
    }

    func testTheDefaultLimitCountsToo() {
        let column = filledList(#", "more": "and $more others""#, records: taskRecords(22))
        // The list's default limit is 20; the source holds 20 by default, so nothing is hidden.
        XCTAssertEqual(rowTexts(column).count, 20)
        let fewer = filledList(#", "limit": 18, "more": "and $more others""#, records: taskRecords(22))
        XCTAssertEqual(rowTexts(fewer).last, "and 2 others", "counts the items the binding holds")
    }

    func testTheCheckerTakesWordsForMore() {
        let good = moreJSON(#"{ "name": "W", "small": { "list": "$t.items", "row": { "text": "x" }, "more": "+$more more" } }"#)
        XCTAssertNil(SidekickWidgetDescription.validationError(good))
        let number = moreJSON(#"{ "name": "W", "small": { "list": "$t.items", "row": { "text": "x" }, "more": 5 } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(number), "small: more takes words, up to 200 characters")
        let long = moreJSON(#"{ "name": "W", "small": { "list": "$t.items", "row": { "text": "x" }, "more": "\#(String(repeating: "m", count: 201))" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(long), "small: more takes words, up to 200 characters")
    }
}
