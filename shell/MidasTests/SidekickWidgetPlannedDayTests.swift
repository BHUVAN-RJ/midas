import XCTest
@testable import Midas

// The To-Do widget (founder, 2026-11-02; docs/CONCERNS.md 25, docs/briefs/todo.md "Widget"). The
// `when: 'today'` source lists only reminders with a time today, so To-Do's untimed and carried-over
// to-dos were missing. `when: 'planned'` lists items by their `when` day, as the To-Do page's Today
// does (Carry Over, Overdue, Start Dates: planned today or earlier; Fresh Start: picked for today).
// The widget description below is the one sidekicks/todo/index.html writes (Notebook look).

private let phoneCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    return phoneCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private let toDoWidget = json(##"""
{ "name": "Today", "version": 1, "tint": "#2F6FEB",
  "background": { "light": "#FCFBF7", "dark": "#141414" },
  "sources": { "today": { "records": "reminder:", "when": "planned", "model": "carry", "where": { "$type": "todo.item" }, "limit": 50 } },
  "small": { "vstack": [
    { "hstack": [ { "text": "Today", "style": "headline", "color": { "light": "#2F6FEB", "dark": "#5B8DEF" } }, { "spacer": true },
                  { "text": "$today.open", "style": "headline", "color": { "light": "#2F6FEB", "dark": "#5B8DEF" } } ] },
    { "divider": true },
    { "list": "$today.items", "limit": 3, "spacing": 8, "more": "+$more More", "if": "$today.open",
      "row": { "hstack": [ { "text": "$item.title", "style": "body" }, { "spacer": true },
                           { "text": "$item.time", "style": "caption", "color": "secondary", "if": "$item.time" },
                           { "tick": "$item", "size": 18, "color": { "light": "#2F6FEB", "dark": "#5B8DEF" } } ], "spacing": 8 } },
    { "vstack": [ { "spacer": true },
                  { "text": "All Done", "style": "headline", "if": "$today.done" },
                  { "text": "Nothing Today", "style": "headline", "unless": "$today.done" },
                  { "spacer": true } ], "unless": "$today.open" },
    { "spacer": true } ], "spacing": 6, "align": "leading" } }
"""##)

@MainActor
final class SidekickWidgetPlannedDayTests: XCTestCase {
    private let noonOnMonday = moment(2, 12)

    private func toDo(_ id: String, _ fields: String) -> LocalRecord {
        return LocalRecord(sidekickId: "todo", key: "reminder:" + id, value: json("{ \"$type\": \"todo.item\", " + fields + " }"))
    }

    /// A Monday's to-dos, one of each kind the page's Today must sort out.
    private func mondayRecords() -> [LocalRecord] {
        let doneToday = ReminderRecord.formatDate(moment(2, 8))
        let doneSunday = ReminderRecord.formatDate(moment(1, 11))
        return [
            toDo("call", #""title": "Call dad", "when": "2026-11-02", "time": "17:00", "order": 2"#),
            toDo("rent", #""title": "Pay rent", "when": "2026-10-31", "order": 1"#),
            toDo("gym", #""title": "Gym", "when": "2026-11-02", "order": 3"#),
            toDo("later", #""title": "Laundry", "when": "2026-11-03", "order": 0"#),
            toDo("someday", #""title": "Learn piano", "when": "2026-11-02", "someday": true, "order": 0"#),
            toDo("trashed", #""title": "Old", "when": "2026-11-02", "deletedAt": "2026-11-02T10:00:00.000Z", "order": 0"#),
            toDo("undated", #""title": "Read", "order": 0"#),
            toDo("picked", #""title": "Picked", "inToday": "2026-11-02", "order": 5"#),
            toDo("ticked", #""title": "Email Sam", "when": "2026-11-02", "done": true, "completedAt": "\#(doneToday)", "order": 4"#),
            toDo("sunday", #""title": "Sunday chore", "when": "2026-11-01", "done": true, "completedAt": "\#(doneSunday)", "order": 0"#),
            LocalRecord(sidekickId: "todo", key: "list:inbox", value: json(#"{ "$type": "todo.list", "name": "Inbox" }"#)),
        ]
    }

    private func record(_ key: String, in records: [LocalRecord]) -> LocalRecord? {
        for record in records where record.key == key {
            return record
        }
        return nil
    }

    private func planned(_ model: String, records: [LocalRecord], at date: Date) -> JSONValue {
        let source = json(#"{ "records": "reminder:", "when": "planned", "model": "\#(model)", "where": { "$type": "todo.item" } }"#)
        let description = JSONValue.object(["sources": .object(["today": source])])
        let scope = SidekickWidgetFiller(calendar: phoneCalendar).sourceValues(description: description, sidekickRecords: records, at: date)
        return scope["today"] ?? .null
    }

    private func keys(_ value: JSONValue) -> [String] {
        var found: [String] = []
        for item in value["items"]?.arrayValue ?? [] {
            found.append(item["key"]?.stringValue ?? "?")
        }
        return found
    }

    private func texts(in piece: WidgetPiece?) -> [String] {
        var found: [String] = []
        switch piece {
        case .text(let textPiece)?:
            found.append(textPiece.text)
        case .vstack(let stack)?, .hstack(let stack)?:
            for child in stack.children {
                found += texts(in: child)
            }
        case .background(let backgroundPiece)?:
            found += texts(in: backgroundPiece.content)
        default:
            break
        }
        return found
    }

    private func ticks(in piece: WidgetPiece?) -> [WidgetTapAction] {
        var found: [WidgetTapAction] = []
        switch piece {
        case .tick(let tickPiece)?:
            found.append(tickPiece.action)
        case .vstack(let stack)?, .hstack(let stack)?:
            for child in stack.children {
                found += ticks(in: child)
            }
        case .background(let backgroundPiece)?:
            found += ticks(in: backgroundPiece.content)
        default:
            break
        }
        return found
    }

    private func filledSmall(records: [LocalRecord], at date: Date) -> WidgetPiece? {
        let widgetRecord = LocalRecord(sidekickId: "todo", key: "widget:today", value: toDoWidget)
        let filler = SidekickWidgetFiller(calendar: phoneCalendar)
        let filled = filler.fill(sidekickId: "todo", sidekickName: "To-Do", record: widgetRecord, sidekickRecords: records + [widgetRecord], now: date)
        XCTAssertTrue(filled.isUsable)
        return filled.looks.first?.small
    }

    // MARK: The source

    func testCarryListsUntimedAndCarriedOverToDosInTheListsOrder() {
        let today = planned("carry", records: mondayRecords(), at: noonOnMonday)
        XCTAssertEqual(keys(today), ["reminder:rent", "reminder:call", "reminder:gym"])
        XCTAssertEqual(today["open"]?.numberValue, 3)
        // Ticked today counts; ticked on Sunday does not
        XCTAssertEqual(today["done"]?.numberValue, 1)
        XCTAssertEqual(today["count"]?.numberValue, 4)
        XCTAssertEqual(today["next"]?["key"]?.stringValue, "reminder:rent")
    }

    func testItemsCarryTheirTimeAndTheDayTheyWerePlannedFor() {
        let items = planned("carry", records: mondayRecords(), at: noonOnMonday)["items"]?.arrayValue ?? []
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0]["id"]?.stringValue, "rent")
        XCTAssertEqual(items[0]["day"]?.stringValue, "Sat")
        XCTAssertEqual(items[0]["late"]?.boolValue, true)
        XCTAssertEqual(items[0]["time"]?.stringValue, "")
        XCTAssertEqual(items[1]["time"]?.stringValue, "5:00 PM")
        XCTAssertEqual(items[1]["day"]?.stringValue, "")
        XCTAssertEqual(items[1]["late"]?.boolValue, false)
        XCTAssertEqual(items[1]["title"]?.stringValue, "Call dad")
    }

    func testOverdueAndStartDatesShowTheSameDayAsCarryOver() {
        for model in ["stay", "gated"] {
            XCTAssertEqual(keys(planned(model, records: mondayRecords(), at: noonOnMonday)), ["reminder:rent", "reminder:call", "reminder:gym"], model)
        }
    }

    func testFreshStartListsOnlyWhatWasPickedForToday() {
        let today = planned("fresh", records: mondayRecords(), at: noonOnMonday)
        XCTAssertEqual(keys(today), ["reminder:picked"])
        XCTAssertEqual(today["done"]?.numberValue, 0)
    }

    func testAtMidnightTodaysOpenOnesCarryOverAndTomorrowsArrive() {
        let tuesdayMidnight = moment(3, 0)
        let today = planned("carry", records: mondayRecords(), at: tuesdayMidnight)
        XCTAssertEqual(keys(today), ["reminder:later", "reminder:rent", "reminder:call", "reminder:gym"])
        let items = today["items"]?.arrayValue ?? []
        XCTAssertEqual(items[2]["day"]?.stringValue, "Mon")
        XCTAssertEqual(items[2]["late"]?.boolValue, true)
        // Monday's tick is yesterday's now
        XCTAssertEqual(today["done"]?.numberValue, 0)
    }

    func testTheWidgetHasALookForTheNextMidnight() {
        let widgetRecord = LocalRecord(sidekickId: "todo", key: "widget:today", value: toDoWidget)
        let filler = SidekickWidgetFiller(calendar: phoneCalendar)
        let filled = filler.fill(sidekickId: "todo", sidekickName: "To-Do", record: widgetRecord, sidekickRecords: mondayRecords() + [widgetRecord], now: noonOnMonday)
        let midnightLook = filled.looks.last
        XCTAssertEqual(midnightLook?.from, moment(3, 0))
        XCTAssertEqual(texts(in: midnightLook?.small), ["Today", "4", "Laundry", "Pay rent", "Call dad", "5:00 PM", "+1 More"])
    }

    func testALimitKeepsTheCountsWhole() {
        let source = json(#"{ "records": "reminder:", "when": "planned", "limit": 1 }"#)
        let description = JSONValue.object(["sources": .object(["today": source])])
        let scope = SidekickWidgetFiller(calendar: phoneCalendar).sourceValues(description: description, sidekickRecords: mondayRecords(), at: noonOnMonday)
        XCTAssertEqual(keys(scope["today"] ?? .null), ["reminder:rent"])
        XCTAssertEqual(scope["today"]?["open"]?.numberValue, 3)
    }

    // MARK: The checker

    func testTheCheckerTakesPlannedWithAModel() {
        XCTAssertNil(SidekickWidgetDescription.validationError(toDoWidget))
        let otherPrefix = json(#"{ "name": "T", "sources": { "t": { "records": "task:", "when": "planned" } }, "small": { "text": "$t.open" } }"#)
        XCTAssertNil(SidekickWidgetDescription.validationError(otherPrefix))
    }

    func testTheCheckerRefusesABadModel() {
        let unknownModel = json(#"{ "name": "T", "sources": { "t": { "records": "reminder:", "when": "planned", "model": "someday" } }, "small": { "text": "x" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(unknownModel), "source t: model must be carry, stay, fresh or gated")
        let modelWithoutPlanned = json(#"{ "name": "T", "sources": { "t": { "records": "reminder:", "when": "today", "model": "carry" } }, "small": { "text": "x" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(modelWithoutPlanned), "source t: model works with when: \"planned\" only")
        let todayOnOtherRecords = json(#"{ "name": "T", "sources": { "t": { "records": "task:", "when": "today" } }, "small": { "text": "x" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(todayOnOtherRecords), "source t: when works with records: \"reminder:\" only")
        let unknownWhen = json(#"{ "name": "T", "sources": { "t": { "records": "reminder:", "when": "soon" } }, "small": { "text": "x" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(unknownWhen), "source t: when must be today, upcoming or planned")
    }

    // MARK: The To-Do widget

    func testSmallShowsThreeRowsAndHowManyMore() {
        var records = mondayRecords()
        records.append(toDo("plants", #""title": "Water the plants", "when": "2026-11-02", "time": "20:00", "order": 6"#))
        records.append(toDo("book", #""title": "Read 20 pages", "when": "2026-11-01", "order": 7"#))
        XCTAssertEqual(texts(in: filledSmall(records: records, at: noonOnMonday)), ["Today", "5", "Pay rent", "Call dad", "5:00 PM", "Gym", "+2 More"])
    }

    func testEverythingTickedSaysAllDone() {
        let doneToday = ReminderRecord.formatDate(moment(2, 9))
        let records = [
            toDo("a", #""title": "A", "when": "2026-11-02", "done": true, "completedAt": "\#(doneToday)", "order": 1"#),
            toDo("b", #""title": "B", "when": "2026-10-30", "done": true, "completedAt": "\#(doneToday)", "order": 2"#),
        ]
        XCTAssertEqual(texts(in: filledSmall(records: records, at: noonOnMonday)), ["Today", "0", "All Done"])
    }

    func testNothingPlannedSaysNothingToday() {
        let records = [toDo("later", #""title": "Laundry", "when": "2026-11-03", "order": 1"#)]
        XCTAssertEqual(texts(in: filledSmall(records: records, at: noonOnMonday)), ["Today", "0", "Nothing Today"])
        // No to-dos at all: the zero state, never "Open Midas"
        XCTAssertEqual(texts(in: filledSmall(records: [], at: noonOnMonday)), ["Today", "0", "Nothing Today"])
    }

    func testATickWritesDoneAtTheTapTimeAndTheRowLeaves() throws {
        let records = mondayRecords()
        let rowTicks = ticks(in: filledSmall(records: records, at: noonOnMonday))
        XCTAssertEqual(rowTicks.count, 3)
        let firstTick = try XCTUnwrap(rowTicks.first)
        XCTAssertEqual(firstTick.kind, .tick)
        XCTAssertEqual(firstTick.key, "reminder:rent")
        // Tapped at 12:05; the app may write it much later, the time stays the tap's
        let tappedAt = moment(2, 12, 5)
        let rentRecord = try XCTUnwrap(record("reminder:rent", in: records))
        let patch = try XCTUnwrap(SidekickWidgetTapPatch.patch(for: rentRecord.value, by: firstTick, now: tappedAt))
        XCTAssertEqual(patch["done"]?.boolValue, true)
        XCTAssertEqual(patch["completedAt"]?.stringValue, ReminderRecord.formatDate(tappedAt))
        var ticked: [LocalRecord] = []
        for record in records {
            let value = record.key == "reminder:rent" ? JSONMergePatch.apply(patch, to: record.value) : record.value
            ticked.append(LocalRecord(sidekickId: record.sidekickId, key: record.key, value: value))
        }
        let today = planned("carry", records: ticked, at: moment(2, 12, 6))
        XCTAssertEqual(keys(today), ["reminder:call", "reminder:gym"])
        XCTAssertEqual(today["done"]?.numberValue, 2)
        // The type and the title are kept: the patch changes only what Done changes
        let tickedRent = try XCTUnwrap(record("reminder:rent", in: ticked))
        XCTAssertEqual(tickedRent.value["$type"]?.stringValue, "todo.item")
        XCTAssertEqual(tickedRent.value["title"]?.stringValue, "Pay rent")
    }
}
