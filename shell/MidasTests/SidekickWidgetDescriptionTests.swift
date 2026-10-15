import XCTest
@testable import Midas

// The Sidekick widget, step 1 (founder, 2026-10-13: "Approve. You can start building"; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html): the `widget:` record format, the checker
// that refuses a broken description when the Sidekick writes it, and `$` bindings.

/// Parses JSON text written as a Sidekick would write it.
private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// The plan's example, "Meds today".
private let medsToday = """
{ "name": "Meds today",
  "sources": { "today": { "records": "reminder:", "when": "today" } },
  "small": { "vstack": [
    { "hstack": [ { "ring": { "done": "$today.done", "of": "$today.count" } }, { "text": "Meds" } ] },
    { "text": "$today.next.title" },
    { "button": "Taken", "action": { "tick": "$today.next" } } ] } }
"""

final class SidekickWidgetCheckerTests: XCTestCase {
    func testThePlansMedsTodayExampleIsAccepted() {
        XCTAssertNil(SidekickWidgetDescription.validationError(json(medsToday)))
    }

    func testANameAndAtLeastOneSizeAreRequired() {
        XCTAssertNotNil(SidekickWidgetDescription.validationError(json(#"{ "small": { "text": "Hi" } }"#)))
        XCTAssertNotNil(SidekickWidgetDescription.validationError(json(#"{ "name": "", "small": { "text": "Hi" } }"#)))
        XCTAssertNotNil(SidekickWidgetDescription.validationError(json(#"{ "name": "Water" }"#)))
        XCTAssertNotNil(SidekickWidgetDescription.validationError(json(#"[1, 2]"#)))
        XCTAssertNil(SidekickWidgetDescription.validationError(json(#"{ "name": "Water", "large": { "text": "Hi" } }"#)))
    }

    func testAnUnknownPieceIsAcceptedSoANewerSidekickStillWorks() {
        let description = json(#"{ "name": "Map", "small": { "vstack": [ { "map": "here" }, { "text": "Hi" } ] } }"#)
        XCTAssertNil(SidekickWidgetDescription.validationError(description))
    }

    func testAPieceWithTwoKindsIsRefused() {
        let description = json(#"{ "name": "Bad", "small": { "text": "Hi", "symbol": "star" } }"#)
        let error = SidekickWidgetDescription.validationError(description)
        XCTAssertEqual(error, "small: a piece has more than one kind: symbol, text")
    }

    // Found by the care-reminders page test: a button's symbol named `symbol` read as a second piece.
    func testAButtonsIconAndATimersFontAreSettingsNotPieces() {
        let button = json(#"{ "name": "B", "small": { "button": "Taken", "icon": "checkmark", "action": { "open": true } } }"#)
        XCTAssertNil(SidekickWidgetDescription.validationError(button))
        let timer = json(#"{ "name": "T", "small": { "timer": "$a.next.at", "font": "number" } }"#)
        XCTAssertNil(SidekickWidgetDescription.validationError(timer))
    }

    func testBrokenPiecesAreRefusedWithTheSizeAndReason() {
        let gridWithoutColumns = json(#"{ "name": "G", "medium": { "grid": [] } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(gridWithoutColumns), "medium: grid needs columns, 1 to 8")
        let listWithoutRow = json(#"{ "name": "L", "small": { "list": "$today.items" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(listWithoutRow), "small: list needs a row piece")
        let listInList = json(#"{ "name": "L", "small": { "list": "$a.items", "row": { "list": "$item.parts", "row": { "text": "x" } } } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(listInList), "small: a list cannot hold another list")
        let ringWithoutTotal = json(#"{ "name": "R", "small": { "ring": { "value": 3 } } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(ringWithoutTotal), "small: ring needs of: a number or a binding")
        let buttonWithoutAction = json(#"{ "name": "B", "small": { "button": "Go" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(buttonWithoutAction), "small: button needs an action")
        let badColor = json(#"{ "name": "C", "small": { "text": "Hi", "color": "chartreuse" } }"#)
        XCTAssertNotNil(SidekickWidgetDescription.validationError(badColor))
        let badStyle = json(#"{ "name": "S", "small": { "text": "Hi", "style": "huge" } }"#)
        XCTAssertNotNil(SidekickWidgetDescription.validationError(badStyle))
    }

    func testTapsCanNeverWriteShellRecords() {
        for key in ["widget:other", "request:import", "reminder:42"] {
            let description = json(#"{ "name": "T", "small": { "button": "Go", "action": { "set": "\#(key)", "field": "x", "value": 1 } } }"#)
            XCTAssertEqual(SidekickWidgetDescription.validationError(description), "small: set cannot write \(key)")
        }
        let increment = json(#"{ "name": "W", "small": { "button": "+", "action": { "increment": "water:today", "field": "glasses" } } }"#)
        XCTAssertNil(SidekickWidgetDescription.validationError(increment))
    }

    func testAnActionNeedsExactlyOneKnownKind() {
        let twoKinds = json(#"{ "name": "T", "small": { "button": "Go", "action": { "open": true, "tick": "$a.next" } } }"#)
        XCTAssertNotNil(SidekickWidgetDescription.validationError(twoKinds))
        let unknownKind = json(#"{ "name": "T", "small": { "button": "Go", "action": { "launch": "rocket" } } }"#)
        XCTAssertNotNil(SidekickWidgetDescription.validationError(unknownKind))
    }

    func testSourcesAreChecked() {
        let whenWithoutReminders = json(#"{ "name": "S", "sources": { "habits": { "records": "habit:", "when": "today" } }, "small": { "text": "x" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(whenWithoutReminders),
                       "source habits: when works with records: \"reminder:\" only")
        let itemAsName = json(#"{ "name": "S", "sources": { "item": { "record": "a" } }, "small": { "text": "x" } }"#)
        XCTAssertNotNil(SidekickWidgetDescription.validationError(itemAsName))
        let noPrefix = json(#"{ "name": "S", "sources": { "a": { "when": "today" } }, "small": { "text": "x" } }"#)
        XCTAssertNotNil(SidekickWidgetDescription.validationError(noPrefix))
        let good = json(#"{ "name": "S", "sources": { "water": { "record": "water:today" }, "habits": { "records": "habit:", "sum": "streak", "where": { "on": true } } }, "small": { "text": "$water.glasses" } }"#)
        XCTAssertNil(SidekickWidgetDescription.validationError(good))
    }

    func testTooManyPiecesAreRefused() {
        var children: [String] = []
        for _ in 0..<40 {
            children.append(#"{ "vstack": [ { "text": "a" }, { "text": "b" }, { "text": "c" } ] }"#)
        }
        let description = json(#"{ "name": "Big", "large": { "vstack": [ \#(children.joined(separator: ",")) ] } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(description), "large: more than 150 pieces")
    }

    @MainActor
    func testTheShellRefusesABrokenWidgetWhenTheSidekickWritesIt() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "widget-checker-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let store = LocalRecordStore(fileURL: fileURL)
        let channel = SidekickStoreChannel(store: store, reservedValidators: ShellServices.reservedRecordValidators)
        let brokenRequest = #"{ "op": "set", "key": "widget:meds", "value": { "name": "Meds" } }"#
        let brokenReply = channel.handle(sidekickId: "care-reminders", requestBody: Data(brokenRequest.utf8))
        XCTAssertEqual(brokenReply.body["ok"], .bool(false))
        XCTAssertEqual(brokenReply.body["error"], .string("widget needs small, medium or large"))
        XCTAssertNil(store.get(sidekickId: "care-reminders", key: "widget:meds"))

        let goodRequest = #"{ "op": "set", "key": "widget:meds", "value": \#(medsToday) }"#
        let goodReply = channel.handle(sidekickId: "care-reminders", requestBody: Data(goodRequest.utf8))
        XCTAssertEqual(goodReply.body["ok"], .bool(true))
        XCTAssertEqual(store.get(sidekickId: "care-reminders", key: "widget:meds")?["name"], .string("Meds today"))
    }
}

final class SidekickWidgetBindingTests: XCTestCase {
    private let scope: [String: JSONValue] = [
        "today": json(#"{ "open": 2, "done": 1, "count": 3, "items": [ { "title": "Vitamin D" }, { "title": "Iron" } ], "next": { "title": "Vitamin D", "dose": 1.5 } }"#),
    ]

    func testAWholeBindingIsAPath() {
        XCTAssertEqual(SidekickWidgetBinding.wholePath("$today.next.title"), ["today", "next", "title"])
        XCTAssertNil(SidekickWidgetBinding.wholePath("today.next"))
        XCTAssertNil(SidekickWidgetBinding.wholePath("$today..next"))
        XCTAssertNil(SidekickWidgetBinding.wholePath("$today next"))
        XCTAssertNil(SidekickWidgetBinding.wholePath("$1st"))
    }

    func testResolveWalksFieldsPositionsAndCounts() {
        XCTAssertEqual(SidekickWidgetBinding.resolve(["today", "next", "title"], in: scope), .string("Vitamin D"))
        XCTAssertEqual(SidekickWidgetBinding.resolve(["today", "items", "1", "title"], in: scope), .string("Iron"))
        XCTAssertEqual(SidekickWidgetBinding.resolve(["today", "items", "count"], in: scope), .number(2))
        XCTAssertNil(SidekickWidgetBinding.resolve(["today", "items", "5"], in: scope))
        XCTAssertNil(SidekickWidgetBinding.resolve(["water", "glasses"], in: scope))
    }

    func testBindingsAmongWordsAreReplaced() {
        XCTAssertEqual(SidekickWidgetBinding.interpolate("$today.open left", scope: scope), "2 left")
        XCTAssertEqual(SidekickWidgetBinding.interpolate("Next: $today.next.title.", scope: scope), "Next: Vitamin D.")
        XCTAssertEqual(SidekickWidgetBinding.interpolate("$today.done/$today.count", scope: scope), "1/3")
        XCTAssertEqual(SidekickWidgetBinding.interpolate("Dose $today.next.dose", scope: scope), "Dose 1.5")
        XCTAssertEqual(SidekickWidgetBinding.interpolate("Price $5", scope: scope), "Price $5")
        XCTAssertEqual(SidekickWidgetBinding.interpolate("$missing.field!", scope: scope), "!")
    }

    func testTruthiness() {
        XCTAssertFalse(SidekickWidgetBinding.isTruthy(nil))
        XCTAssertFalse(SidekickWidgetBinding.isTruthy(.null))
        XCTAssertFalse(SidekickWidgetBinding.isTruthy(.number(0)))
        XCTAssertFalse(SidekickWidgetBinding.isTruthy(.string("")))
        XCTAssertFalse(SidekickWidgetBinding.isTruthy(.array([])))
        XCTAssertTrue(SidekickWidgetBinding.isTruthy(.number(2)))
        XCTAssertTrue(SidekickWidgetBinding.isTruthy(.object([:])))
    }
}
