import XCTest
@testable import Midas

// The Sidekick widget, steps 2 and 3 (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html): sources filled from the Sidekick's records,
// bindings replaced, pieces turned into what the widget draws, and which look a placed widget
// shows (founder question 2026-10-13: two Sidekicks can each use a small widget).

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func iso(_ date: Date) -> String {
    return ReminderRecord.formatDate(date)
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func storedRecord(_ key: String, _ text: String) -> LocalRecord {
    return LocalRecord(sidekickId: "care-reminders", key: key, value: json(text))
}

/// Care Reminders on Tue Oct 13, 10:00 AM PT: Vitamin D daily at 9:00 (missed, still in Today),
/// Iron at 8:00 PM and fish oil done at 8:00 AM (all in the green Meds list), and a walk at 8:45 AM
/// in another list.
private let careRecords: [LocalRecord] = [
    storedRecord("list:meds", #"{ "$type": "care.list", "name": "Meds", "color": "green" }"#),
    storedRecord("reminder:vitd", #"{ "$type": "care.item", "title": "Vitamin D", "at": "\#(iso(octoberPT(1, 9)))", "timeZone": "America/Los_Angeles", "repeat": { "every": "day" }, "list": "meds", "createdAt": "\#(iso(octoberPT(1, 8)))" }"#),
    storedRecord("reminder:walk", #"{ "$type": "care.item", "title": "Walk", "at": "\#(iso(octoberPT(13, 8, 45)))", "list": "move" }"#),
    storedRecord("reminder:iron", #"{ "$type": "care.item", "title": "Iron", "at": "\#(iso(octoberPT(13, 20)))", "list": "meds" }"#),
    storedRecord("reminder:fish", #"{ "$type": "care.item", "title": "Fish oil", "at": "\#(iso(octoberPT(13, 8)))", "done": true, "completedAt": "\#(iso(octoberPT(13, 8, 5)))", "list": "meds" }"#),
]

private let now = octoberPT(13, 10)

private let todaySource = #"{ "records": "reminder:", "when": "today", "where": { "$type": "care.item", "list": "meds" } }"#

/// The plan's "Meds today" example.
private let medsToday = json("""
{ "name": "Meds today", "tint": "#9CAF88",
  "sources": { "today": \(todaySource) },
  "small": { "vstack": [
    { "hstack": [ { "ring": { "done": "$today.done", "of": "$today.count" } }, { "text": "Meds" } ] },
    { "text": "$today.next.title" },
    { "button": "Taken", "action": { "tick": "$today.next" } } ] } }
""")

private let filler = SidekickWidgetFiller(calendar: calendarPT)

private func fillPiece(_ pieceText: String, sources: String = #"{ "today": \#(todaySource) }"#, records: [LocalRecord] = careRecords) -> WidgetPiece? {
    let description = json(#"{ "name": "T", "sources": \#(sources), "small": \#(pieceText) }"#)
    let widgetRecord = LocalRecord(sidekickId: "care-reminders", key: "widget:t", value: description)
    let filled = filler.fill(sidekickId: "care-reminders", sidekickName: "Reminders", record: widgetRecord, sidekickRecords: records, now: now)
    return filled.looks.first?.small
}

private func text(_ value: String, style: WidgetTextStyle = .body, colorHex: String? = nil, isSecondary: Bool = false) -> WidgetPiece {
    return .text(WidgetTextPiece(text: value, style: style, colorHex: colorHex, isSecondary: isSecondary, lineLimit: 1))
}

final class SidekickWidgetSourceTests: XCTestCase {
    func testTodayCountsOpenAndDoneAndPointsAtTheNextOne() {
        let scope = filler.sourceValues(description: medsToday, sidekickRecords: careRecords, at: now)
        let today = scope["today"]
        XCTAssertEqual(today?["open"], .number(2))
        XCTAssertEqual(today?["done"], .number(1))
        XCTAssertEqual(today?["count"], .number(3))
        XCTAssertEqual(today?["next"]?["title"], .string("Vitamin D"))
        XCTAssertEqual(today?["next"]?["key"], .string("reminder:vitd"))
        XCTAssertEqual(today?["next"]?["time"], .string("9:00 AM"))
        XCTAssertEqual(today?["next"]?["at"], .string(iso(octoberPT(13, 9))))
        XCTAssertEqual(today?["next"]?["color"], .string("#34C759"))
        let titles = today?["items"]?.arrayValue?.compactMap { item in item["title"]?.stringValue }
        XCTAssertEqual(titles, ["Vitamin D", "Iron"])
    }

    func testWhereLeavesOutRecordsThatDoNotMatch() {
        let withoutWhere = json(#"{ "sources": { "today": { "records": "reminder:", "when": "today" } } }"#)
        let scope = filler.sourceValues(description: withoutWhere, sidekickRecords: careRecords, at: now)
        XCTAssertEqual(scope["today"]?["open"], .number(3))
    }

    func testTodayRollsOverAtMidnight() {
        let scope = filler.sourceValues(description: medsToday, sidekickRecords: careRecords, at: octoberPT(14, 0))
        let today = scope["today"]
        XCTAssertEqual(today?["open"], .number(1))
        XCTAssertEqual(today?["done"], .number(0))
        XCTAssertEqual(today?["next"]?["at"], .string(iso(octoberPT(14, 9))))
    }

    func testUpcomingIsEachReminderAtItsNextTimeInOrder() {
        let description = json(#"{ "sources": { "soon": { "records": "reminder:", "when": "upcoming", "where": { "$type": "care.item", "list": "meds" } } } }"#)
        let scope = filler.sourceValues(description: description, sidekickRecords: careRecords, at: now)
        let soon = scope["soon"]
        XCTAssertEqual(soon?["count"], .number(2))
        XCTAssertEqual(soon?["next"]?["title"], .string("Iron"))
        XCTAssertEqual(soon?["items"]?.arrayValue?.last?["at"], .string(iso(octoberPT(14, 9))))
        XCTAssertEqual(soon?["items"]?.arrayValue?.last?["day"], .string("Wed"))
    }

    func testPlainRecordsCountAndSum() {
        let waterRecords = [
            storedRecord("water:mon", #"{ "glasses": 3 }"#),
            storedRecord("water:tue", #"{ "glasses": 5 }"#),
            storedRecord("note:x", #"{ "glasses": 100 }"#),
        ]
        let description = json(#"{ "sources": { "week": { "records": "water:", "sum": "glasses" }, "today": { "record": "water:tue" } } }"#)
        let scope = filler.sourceValues(description: description, sidekickRecords: waterRecords, at: now)
        XCTAssertEqual(scope["week"]?["count"], .number(2))
        XCTAssertEqual(scope["week"]?["sum"], .number(8))
        XCTAssertEqual(scope["week"]?["values"], .array([.number(3), .number(5)]))
        XCTAssertEqual(scope["today"]?["glasses"], .number(5))
        XCTAssertEqual(scope["today"]?["key"], .string("water:tue"))
    }
}

final class SidekickWidgetFillTests: XCTestCase {
    func testTheMedsTodayExampleFillsForNowAndForMidnight() {
        let widgetRecord = LocalRecord(sidekickId: "care-reminders", key: "widget:meds", value: medsToday)
        let filled = filler.fill(sidekickId: "care-reminders", sidekickName: "Reminders", record: widgetRecord, sidekickRecords: careRecords, now: now)
        XCTAssertEqual(filled.widgetId, "meds")
        XCTAssertEqual(filled.choiceId, "care-reminders/meds")
        XCTAssertEqual(filled.name, "Meds today")
        XCTAssertEqual(filled.tintHex, "#9CAF88")
        XCTAssertTrue(filled.isUsable)
        XCTAssertEqual(filled.looks.map(\.from), [now, octoberPT(14, 0)])

        let taken = WidgetTapAction(kind: .tick, sidekickId: "care-reminders", key: "reminder:vitd", field: nil, amount: nil,
                                    valueJSON: nil, occurrence: octoberPT(13, 9))
        let expectedNow = WidgetPiece.vstack(WidgetStackPiece(children: [
            .hstack(WidgetStackPiece(children: [
                .ring(WidgetMeterPiece(value: 1, total: 3, colorHex: "#9CAF88", label: nil)),
                text("Meds"),
            ], spacing: nil, alignment: nil)),
            text("Vitamin D"),
            .button(WidgetButtonPiece(title: "Taken", symbolName: nil, colorHex: "#9CAF88", action: taken)),
        ], spacing: nil, alignment: nil))
        XCTAssertEqual(filled.looks[0].small, expectedNow)
        XCTAssertNil(filled.looks[0].medium)

        guard case .vstack(let midnight)? = filled.looks[1].small, case .button(let midnightButton) = midnight.children[2] else {
            return XCTFail("midnight look is not the stack with a button")
        }
        XCTAssertEqual(midnightButton.action.occurrence, octoberPT(14, 9))
        guard case .hstack(let ringLine) = midnight.children[0], case .ring(let midnightRing) = ringLine.children[0] else {
            return XCTFail("midnight look has no ring")
        }
        XCTAssertEqual(midnightRing.value, 0)
        XCTAssertEqual(midnightRing.total, 1)
    }

    func testAListMakesOneRowPerItemWithTheItemBound() {
        let piece = fillPiece(#"{ "list": "$today.items", "limit": 1, "row": { "hstack": [ { "tick": "$item" }, { "text": "$item.title · $item.time" } ] } }"#)
        let tick = WidgetTapAction(kind: .tick, sidekickId: "care-reminders", key: "reminder:vitd", field: nil, amount: nil,
                                   valueJSON: nil, occurrence: octoberPT(13, 9))
        let expected = WidgetPiece.vstack(WidgetStackPiece(children: [
            .hstack(WidgetStackPiece(children: [
                .tick(WidgetTickPiece(action: tick, colorHex: "#34C759", size: 16)),
                text("Vitamin D · 9:00 AM"),
            ], spacing: nil, alignment: nil)),
        ], spacing: 6, alignment: .leading))
        XCTAssertEqual(piece, expected)
    }

    func testAnEmptyListShowsItsEmptyWords() {
        let piece = fillPiece(#"{ "list": "$today.items", "empty": "All done", "row": { "text": "$item.title" } }"#, records: [])
        XCTAssertEqual(piece, text("All done", isSecondary: true))
    }

    func testIfAndUnlessShowOrHideAPiece() {
        let shown = fillPiece(#"{ "vstack": [ { "text": "All done", "unless": "$today.open" }, { "text": "$today.open left", "if": "$today.open" } ] }"#)
        XCTAssertEqual(shown, .vstack(WidgetStackPiece(children: [text("2 left")], spacing: nil, alignment: nil)))
        let allDone = fillPiece(#"{ "vstack": [ { "text": "All done", "unless": "$today.open" }, { "text": "$today.open left", "if": "$today.open" } ] }"#, records: [])
        XCTAssertEqual(allDone, .vstack(WidgetStackPiece(children: [text("All done")], spacing: nil, alignment: nil)))
    }

    func testAnUnknownPieceIsSkippedAndTheRestDrawn() {
        let piece = fillPiece(#"{ "vstack": [ { "map": "here" }, { "text": "Hi" } ] }"#)
        XCTAssertEqual(piece, .vstack(WidgetStackPiece(children: [text("Hi")], spacing: nil, alignment: nil)))
    }

    func testATapOnNothingLeftIsLeftOut() {
        let piece = fillPiece(#"{ "vstack": [ { "button": "Taken", "action": { "tick": "$today.next" } }, { "tick": "$today.next" } ] }"#, records: [])
        XCTAssertEqual(piece, .vstack(WidgetStackPiece(children: [], spacing: nil, alignment: nil)))
    }

    func testIncrementToggleAndSetCarryTheirRecordAndField() {
        let piece = fillPiece(#"""
        { "hstack": [
          { "button": "+", "action": { "increment": "water:today", "field": "glasses", "by": 2 } },
          { "button": "On", "action": { "toggle": "lamp", "field": "on" } },
          { "button": "Reset", "action": { "set": "water:today", "field": "glasses", "value": 0 } },
          { "button": "Open", "action": { "open": true } } ] }
        """#)
        guard case .hstack(let row)? = piece else {
            return XCTFail("no row")
        }
        var actions: [WidgetTapAction] = []
        for child in row.children {
            if case .button(let button) = child {
                actions.append(button.action)
            }
        }
        XCTAssertEqual(actions.map(\.kind), [.increment, .toggle, .set, .open])
        XCTAssertEqual(actions[0].key, "water:today")
        XCTAssertEqual(actions[0].field, "glasses")
        XCTAssertEqual(actions[0].amount, 2)
        XCTAssertEqual(actions[1].field, "on")
        XCTAssertNil(actions[1].amount)
        XCTAssertEqual(actions[2].valueJSON, "0")
        XCTAssertEqual(actions[3].sidekickId, "care-reminders")
        XCTAssertNil(actions[3].key)
    }

    func testColoursByNameHexAndAccent() {
        let piece = fillPiece(##"{ "vstack": [ { "text": "a", "color": "red" }, { "text": "b", "color": "#abc" }, { "text": "c", "color": "secondary" }, { "symbol": "pills.fill", "color": "accent" } ] }"##)
        let expected = WidgetPiece.vstack(WidgetStackPiece(children: [
            text("a", colorHex: "#FF3B30"),
            text("b", colorHex: "#AABBCC"),
            text("c", isSecondary: true),
            .symbol(WidgetSymbolPiece(name: "pills.fill", colorHex: nil, size: 16)),
        ], spacing: nil, alignment: nil))
        XCTAssertEqual(piece, expected)
    }

    func testMetersChartsAndTimers() {
        let piece = fillPiece(#"""
        { "vstack": [
          { "bar": { "value": 3, "of": 8, "label": "$today.open left" } },
          { "dots": { "value": "$today.done", "of": 4 } },
          { "chart": [1, 2, 3] },
          { "timer": "$today.next.at", "style": "countdown", "font": "number" } ] }
        """#)
        let expected = WidgetPiece.vstack(WidgetStackPiece(children: [
            .bar(WidgetMeterPiece(value: 3, total: 8, colorHex: nil, label: "2 left")),
            .dots(WidgetMeterPiece(value: 1, total: 4, colorHex: nil, label: nil)),
            .chart(WidgetChartPiece(values: [1, 2, 3], colorHex: nil)),
            .timer(WidgetTimerPiece(target: octoberPT(13, 9), style: .countdown, colorHex: nil, textStyle: .number)),
        ], spacing: nil, alignment: nil))
        XCTAssertEqual(piece, expected)
        XCTAssertEqual(WidgetMeterPiece(value: 3, total: 8, colorHex: nil, label: nil).fraction, 0.375)
        XCTAssertEqual(WidgetMeterPiece(value: 9, total: 8, colorHex: nil, label: nil).fraction, 1)
        XCTAssertEqual(WidgetMeterPiece(value: 1, total: 0, colorHex: nil, label: nil).fraction, 0)
    }

    func testABrokenDescriptionIsKeptAsUnusable() {
        let widgetRecord = LocalRecord(sidekickId: "care-reminders", key: "widget:broken", value: json(#"{ "name": "Broken" }"#))
        let filled = filler.fill(sidekickId: "care-reminders", sidekickName: "Reminders", record: widgetRecord, sidekickRecords: careRecords, now: now)
        XCTAssertFalse(filled.isUsable)
        XCTAssertEqual(filled.name, "Broken")
        XCTAssertTrue(filled.looks.isEmpty)
    }
}

final class SidekickWidgetLayoutTests: XCTestCase {
    private func widget(_ sidekickId: String, _ widgetId: String, small: WidgetPiece?, medium: WidgetPiece? = nil, isUsable: Bool = true) -> FilledSidekickWidget {
        let looks = [
            FilledWidgetLook(from: octoberPT(13, 0), small: small, medium: medium, large: nil),
            FilledWidgetLook(from: octoberPT(14, 0), small: text("tomorrow"), medium: nil, large: nil),
        ]
        return FilledSidekickWidget(sidekickId: sidekickId, sidekickName: sidekickId.capitalized, widgetId: widgetId, name: widgetId,
                                    tintHex: nil, isUsable: isUsable, looks: isUsable ? looks : [])
    }

    private lazy var file = SharedSidekickWidgets(widgets: [
        widget("care-reminders", "meds", small: text("Meds")),
        widget("care-reminders", "next", small: text("Next")),
        widget("water", "glasses", small: text("Water")),
        widget("water", "broken", small: nil, isUsable: false),
    ], savedAt: now)

    func testTwoSidekicksEachFillTheirOwnSmallWidget() {
        let meds = SidekickWidgetLayout.screen(file: file, sidekickId: "care-reminders", widgetChoiceId: "care-reminders/meds", size: .small, at: now)
        let water = SidekickWidgetLayout.screen(file: file, sidekickId: "water", widgetChoiceId: "water/glasses", size: .small, at: now)
        XCTAssertEqual(meds, .piece(text("Meds"), sidekickId: "care-reminders", tintHex: nil))
        XCTAssertEqual(water, .piece(text("Water"), sidekickId: "water", tintHex: nil))
    }

    func testOneSidekickCanHaveSeveralWidgets() {
        let next = SidekickWidgetLayout.screen(file: file, sidekickId: "care-reminders", widgetChoiceId: "care-reminders/next", size: .small, at: now)
        XCTAssertEqual(next, .piece(text("Next"), sidekickId: "care-reminders", tintHex: nil))
    }

    func testWithOnlyASidekickPickedItsFirstWidgetShows() {
        let screen = SidekickWidgetLayout.screen(file: file, sidekickId: "water", widgetChoiceId: nil, size: .small, at: now)
        XCTAssertEqual(screen, .piece(text("Water"), sidekickId: "water", tintHex: nil))
        let mismatched = SidekickWidgetLayout.screen(file: file, sidekickId: "water", widgetChoiceId: "care-reminders/meds", size: .small, at: now)
        XCTAssertEqual(mismatched, .piece(text("Water"), sidekickId: "water", tintHex: nil))
    }

    func testNothingPickedAsksForASidekick() {
        XCTAssertEqual(SidekickWidgetLayout.screen(file: file, sidekickId: nil, widgetChoiceId: nil, size: .small, at: now), .pickSidekick)
    }

    func testAGoneOrBrokenWidgetShowsOpenMidas() {
        let gone = SidekickWidgetLayout.screen(file: file, sidekickId: "notes", widgetChoiceId: "notes/today", size: .small, at: now)
        XCTAssertEqual(gone, .empty(sidekickId: "notes"))
        let broken = SidekickWidgetLayout.screen(file: file, sidekickId: "water", widgetChoiceId: "water/broken", size: .small, at: now)
        XCTAssertEqual(broken, .empty(sidekickId: "water"))
        let noFile = SidekickWidgetLayout.screen(file: nil, sidekickId: "water", widgetChoiceId: nil, size: .small, at: now)
        XCTAssertEqual(noFile, .empty(sidekickId: "water"))
    }

    func testAMissingSizeDrawsTheNearestOne() {
        let large = SidekickWidgetLayout.screen(file: file, sidekickId: "water", widgetChoiceId: "water/glasses", size: .large, at: now)
        XCTAssertEqual(large, .piece(text("Water"), sidekickId: "water", tintHex: nil))
    }

    func testTheLookChangesAtMidnight() {
        let afterMidnight = SidekickWidgetLayout.screen(file: file, sidekickId: "water", widgetChoiceId: "water/glasses", size: .small, at: octoberPT(14, 0, 1))
        XCTAssertEqual(afterMidnight, .piece(text("tomorrow"), sidekickId: "water", tintHex: nil))
        let dates = SidekickWidgetLayout.timelineDates(widget: file.widget(choiceId: "water/glasses"), now: now)
        XCTAssertEqual(dates, [now, octoberPT(14, 0)])
    }

    func testTheFileRoundTripsAndRefusesAnUnknownVersion() throws {
        let encoded = try file.encoded()
        XCTAssertEqual(SharedSidekickWidgets.decoded(from: encoded), file)
        let otherVersion = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":99")
        XCTAssertNil(SharedSidekickWidgets.decoded(from: Data(otherVersion.utf8)))
    }

    func testATapActionSurvivesTheIntentParameter() {
        let action = WidgetTapAction(kind: .set, sidekickId: "water", key: "water:today", field: "glasses", amount: nil,
                                     valueJSON: "0", occurrence: octoberPT(13, 9))
        XCTAssertEqual(WidgetTapAction.decoded(fromText: action.encodedText()), action)
        XCTAssertNil(WidgetTapAction.decoded(fromText: "not json"))
    }
}
