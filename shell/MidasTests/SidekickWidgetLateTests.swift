import XCTest
@testable import Midas

// Late times in the Sidekick widget (founder, 2026-10-26: the Reminders Sidekick makes its own
// widget through the builder, "each Sidekick can also use these features"): a reminder item gets
// `late` once its time has passed today, the widget gets a look at each of today's reminder times
// still to come (at most SidekickWidgetFiller.maximumLateLooks), and a colour can be a choice on a
// binding, { if, then, else }, so a time is drawn red when late.

private let lateCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func lateOctober(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return lateCalendar.date(from: components)!
}

private func lateJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func lateReminder(_ reminderId: String, at moment: Date, extraFields: [String: JSONValue] = [:]) -> LocalRecord {
    var fields: [String: JSONValue] = [
        "title": .string(reminderId), "at": .string(ReminderRecord.formatDate(moment)), "done": .bool(false),
        "timeZone": .string("America/Los_Angeles"),
    ]
    for (fieldName, fieldValue) in extraFields {
        fields[fieldName] = fieldValue
    }
    return LocalRecord(sidekickId: "reminders", key: "reminder:" + reminderId, value: .object(fields))
}

/// One row per item: the title, then the time, red when late and grey before.
private let lateWidget = lateJSON(#"""
{ "name": "Today",
  "sources": { "today": { "records": "reminder:", "when": "today" } },
  "small": { "list": "$today.items", "row": { "hstack": [
    { "text": "$item.title" },
    { "text": "$item.time", "color": { "if": "$item.late", "then": "red", "else": "secondary" } } ] } } }
"""#)

/// Sunday Oct 11 2026, 3:00 PM Pacific.
private let lateNow = lateOctober(11, 15)

private let lateFiller = SidekickWidgetFiller(calendar: lateCalendar)

private func filledLateWidget(_ description: JSONValue, records: [LocalRecord], now: Date = lateNow) -> FilledSidekickWidget {
    let widgetRecord = LocalRecord(sidekickId: "reminders", key: "widget:today", value: description)
    return lateFiller.fill(sidekickId: "reminders", sidekickName: "Reminders", record: widgetRecord, sidekickRecords: records, now: now)
}

private func lookStarts(_ widget: FilledSidekickWidget) -> [Date] {
    var starts: [Date] = []
    for look in widget.looks {
        starts.append(look.from)
    }
    return starts
}

/// Every text piece inside a filled piece, depth first.
private func lateTexts(in piece: WidgetPiece?) -> [WidgetTextPiece] {
    guard let piece else {
        return []
    }
    switch piece {
    case .text(let textPiece):
        return [textPiece]
    case .vstack(let stack), .hstack(let stack):
        var found: [WidgetTextPiece] = []
        for child in stack.children {
            found.append(contentsOf: lateTexts(in: child))
        }
        return found
    default:
        return []
    }
}

private func timeText(_ time: String, in piece: WidgetPiece?) -> WidgetTextPiece? {
    for textPiece in lateTexts(in: piece) where textPiece.text == time {
        return textPiece
    }
    return nil
}

final class SidekickWidgetLateItemTests: XCTestCase {
    private func todayItems(_ records: [LocalRecord], at moment: Date) -> [JSONValue] {
        let scope = lateFiller.sourceValues(description: lateWidget, sidekickRecords: records, at: moment)
        return scope["today"]?["items"]?.arrayValue ?? []
    }

    func testAnItemIsLateOnceItsTimeHasPassedToday() {
        let records = [
            lateReminder("reply", at: lateOctober(11, 9)),
            lateReminder("call", at: lateOctober(11, 18)),
            lateReminder("insurance", at: lateOctober(11, 9), extraFields: ["allDay": .bool(true)]),
        ]
        var lateById: [String: JSONValue] = [:]
        for item in todayItems(records, at: lateNow) {
            lateById[item["id"]?.stringValue ?? ""] = item["late"]
        }
        XCTAssertEqual(lateById["reply"], .bool(true), "9:00 AM has passed at 3:00 PM")
        XCTAssertEqual(lateById["call"], .bool(false), "6:00 PM has not")
        XCTAssertEqual(lateById["insurance"], .bool(false), "an all-day item is never late")
    }

    func testTheTimeItselfCountsAsLate() {
        let records = [lateReminder("call", at: lateOctober(11, 18))]
        let atSix = todayItems(records, at: lateOctober(11, 18))
        XCTAssertEqual(atSix.first?["late"], .bool(true))
        let justBefore = todayItems(records, at: lateOctober(11, 17, 59))
        XCTAssertEqual(justBefore.first?["late"], .bool(false))
    }

    func testUpcomingItemsAreNeverLate() {
        let description = lateJSON(#"{ "name": "Soon", "sources": { "soon": { "records": "reminder:", "when": "upcoming" } }, "small": { "text": "x" } }"#)
        let records = [lateReminder("call", at: lateOctober(11, 18))]
        let scope = lateFiller.sourceValues(description: description, sidekickRecords: records, at: lateNow)
        XCTAssertEqual(scope["soon"]?["next"]?["late"], .bool(false))
    }
}

final class SidekickWidgetLateLookTests: XCTestCase {
    func testTheWidgetHasALookAtEachTimeStillToComeToday() {
        let records = [
            lateReminder("reply", at: lateOctober(11, 9)),
            lateReminder("call", at: lateOctober(11, 18)),
            lateReminder("gym", at: lateOctober(1, 19, 30), extraFields: ["repeat": .object(["every": .string("day")])]),
            lateReminder("also-call", at: lateOctober(11, 18)),
            lateReminder("insurance", at: lateOctober(11, 20), extraFields: ["allDay": .bool(true)]),
            lateReminder("dentist", at: lateOctober(12, 10)),
        ]
        let widget = filledLateWidget(lateWidget, records: records)
        // Now, 6:00 PM once (two reminders share it), 7:30 PM (today's repeat), then midnight. Not
        // 9:00 AM (passed), not the all-day one, not tomorrow's.
        XCTAssertEqual(lookStarts(widget), [lateNow, lateOctober(11, 18), lateOctober(11, 19, 30), lateOctober(12, 0)])
        XCTAssertEqual(SidekickWidgetLayout.timelineDates(widget: widget, now: lateNow), lookStarts(widget), "each look is a timeline entry")
    }

    func testATimeTurnsRedAtItsOwnLookWithoutTheAppRunning() throws {
        let records = [lateReminder("call", at: lateOctober(11, 18))]
        let widget = filledLateWidget(lateWidget, records: records)
        let before = try XCTUnwrap(timeText("6:00 PM", in: widget.look(at: lateOctober(11, 17, 59))?.small))
        XCTAssertNil(before.colorHex)
        XCTAssertTrue(before.isSecondary, "grey before its time")
        let after = try XCTUnwrap(timeText("6:00 PM", in: widget.look(at: lateOctober(11, 18))?.small))
        XCTAssertEqual(after.colorHex, "#FF3B30", "red from its time on")
        XCTAssertFalse(after.isSecondary)
    }

    func testTheLooksAreCappedForWidgetKitsBudget() {
        var records: [LocalRecord] = []
        // 30 reminders, one a minute from 3:10 PM.
        for index in 0..<30 {
            records.append(lateReminder("r\(index)", at: lateOctober(11, 15, 10 + index)))
        }
        let widget = filledLateWidget(lateWidget, records: records)
        XCTAssertEqual(SidekickWidgetFiller.maximumLateLooks, 24)
        XCTAssertEqual(widget.looks.count, 1 + 24 + 1, "now, the next 24 times, midnight")
        XCTAssertEqual(widget.looks[1].from, lateOctober(11, 15, 10), "the earliest times come first")
        XCTAssertEqual(widget.looks[24].from, lateOctober(11, 15, 33))
        XCTAssertEqual(widget.looks.last?.from, lateOctober(12, 0))
    }

    func testAWidgetWithoutTodaysRemindersStaysAtNowAndMidnight() {
        let description = lateJSON(#"{ "name": "Water", "sources": { "day": { "record": "water:{today}" } }, "small": { "text": "$day.ml" } }"#)
        let records = [lateReminder("call", at: lateOctober(11, 18))]
        let widget = filledLateWidget(description, records: records)
        XCTAssertEqual(lookStarts(widget), [lateNow, lateOctober(12, 0)])
    }

    func testOnlyTheSourcesOwnRemindersGetLooks() {
        let description = lateJSON(#"{ "name": "Meds", "sources": { "today": { "records": "reminder:", "when": "today", "where": { "list": "meds" } } }, "small": { "text": "$today.open" } }"#)
        let records = [
            lateReminder("iron", at: lateOctober(11, 20), extraFields: ["list": .string("meds")]),
            lateReminder("walk", at: lateOctober(11, 17), extraFields: ["list": .string("move")]),
        ]
        let widget = filledLateWidget(description, records: records)
        XCTAssertEqual(lookStarts(widget), [lateNow, lateOctober(11, 20), lateOctober(12, 0)])
    }
}

final class SidekickWidgetColorChoiceTests: XCTestCase {
    private func smallError(_ colorText: String, piece: String = #"{ "text": "hi", "color": COLOR }"#) -> String? {
        let pieceText = piece.replacingOccurrences(of: "COLOR", with: colorText)
        let description = lateJSON(#"{ "name": "W", "small": \#(pieceText) }"#)
        return SidekickWidgetDescription.validationError(description)
    }

    func testTheCheckerTakesAColourChoice() {
        XCTAssertNil(smallError(#"{ "if": "$item.late", "then": "red", "else": "secondary" }"#))
        XCTAssertNil(smallError(##"{ "if": "$item.late", "then": "#FF3B30" }"##), "else is optional")
        XCTAssertNil(smallError(#"{ "if": "$day.ml", "then": "blue" }"#, piece: #"{ "fill": { "value": 1, "of": 2 }, "color": COLOR }"#), "a fill takes a choice too")
        XCTAssertNil(SidekickWidgetDescription.validationError(lateWidget))
    }

    func testTheCheckerRefusesABrokenColourChoice() {
        XCTAssertEqual(smallError(#"{ "if": "late", "then": "red" }"#), "small: a colour choice needs if: a binding")
        XCTAssertEqual(smallError(#"{ "if": "$item.late" }"#), "small: a colour choice needs then: a colour")
        XCTAssertEqual(smallError(#"{ "if": "$item.late", "then": "chartreuse" }"#), "small: color chartreuse is not a colour name or #RRGGBB")
        XCTAssertEqual(smallError(#"{ "if": "$item.late", "then": "red", "else": { "if": "$item.allDay", "then": "blue" } }"#), "small: color must be a name or #RRGGBB", "no choice inside a choice")
        XCTAssertEqual(smallError(#"{ "if": "$item.late", "then": "red", "otherwise": "blue" }"#), "small: a colour choice takes if, then and else, not otherwise")
        XCTAssertNil(smallError(##"{ "light": "#FFFFFF", "dark": "#000000" }"##), "a light/dark pair is taken on every piece (2026-10-27)")
    }

    func testTheTintIsOneColourNeverAChoice() {
        let description = lateJSON(#"{ "name": "W", "tint": { "if": "$item.late", "then": "red" }, "small": { "spacer": true } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(description), "tint is not a colour")
    }

    func testAChoiceWithoutElseLeavesThePiecesOwnColour() throws {
        let description = lateJSON(#"""
        { "name": "T", "sources": { "today": { "records": "reminder:", "when": "today" } },
          "small": { "list": "$today.items", "row": { "text": "$item.time", "color": { "if": "$item.late", "then": "orange" } } } }
        """#)
        let records = [lateReminder("reply", at: lateOctober(11, 9)), lateReminder("call", at: lateOctober(11, 18))]
        let small = filledLateWidget(description, records: records).looks.first?.small
        let passed = try XCTUnwrap(timeText("9:00 AM", in: small))
        XCTAssertEqual(passed.colorHex, "#FF9500")
        let coming = try XCTUnwrap(timeText("6:00 PM", in: small))
        XCTAssertNil(coming.colorHex)
        XCTAssertFalse(coming.isSecondary, "primary, the text's default")
    }
}
