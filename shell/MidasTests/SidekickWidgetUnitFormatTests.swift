import XCTest
@testable import Midas

// Hydration plan W2 (founder, 2026-10-25; docs/briefs/hydration-sidekick.md section 2.1): a text's
// `format: 'ml' | 'l' | 'oz'` reads its number bindings as millilitres and shows them in that
// unit. Texts without `format` are unchanged (numbers to one decimal, as before).

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

final class SidekickWidgetUnitFormatTests: XCTestCase {
    private let scope: [String: JSONValue] = [
        "water": json(#"{ "ml": 1250, "goalMl": 2500, "label": "Water" }"#),
    ]

    private func filledText(_ piece: String) -> String? {
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        guard case .text(let textPiece)? = filler.filledPiece(json(piece), scope: scope) else {
            return nil
        }
        return textPiece.text
    }

    func testMillilitresAreGroupedWholeNumbers() {
        XCTAssertEqual(filledText(#"{ "text": "$water.ml", "format": "ml" }"#), "1,250 ml")
        XCTAssertEqual(WidgetUnitFormat.ml.text(millilitres: 249.6), "250 ml")
    }

    func testLitresKeepTwoDecimals() {
        XCTAssertEqual(filledText(#"{ "text": "$water.ml", "format": "l" }"#), "1.25 L")
        XCTAssertEqual(WidgetUnitFormat.l.text(millilitres: 2500), "2.5 L")
        XCTAssertEqual(WidgetUnitFormat.l.text(millilitres: 2000), "2 L")
        XCTAssertEqual(WidgetUnitFormat.l.text(millilitres: 0), "0 L")
    }

    func testOuncesAreWholeUSFluidOunces() {
        XCTAssertEqual(filledText(#"{ "text": "$water.ml", "format": "oz" }"#), "42 oz")
        XCTAssertEqual(WidgetUnitFormat.oz.text(millilitres: 2500), "85 oz")
    }

    func testEveryNumberInTheTextIsFormattedAndWordsStay() {
        XCTAssertEqual(filledText(#"{ "text": "$water.label: $water.ml of $water.goalMl", "format": "l" }"#), "Water: 1.25 L of 2.5 L")
    }

    func testTextWithoutFormatIsUnchanged() {
        XCTAssertEqual(filledText(#"{ "text": "$water.ml" }"#), "1250")
        let litres: [String: JSONValue] = ["water": json(#"{ "litres": 1.27 }"#)]
        XCTAssertEqual(SidekickWidgetBinding.interpolate("$water.litres", scope: litres), "1.3")
    }

    func testTheCheckerAcceptsTheThreeFormatsOnly() {
        for formatName in ["ml", "l", "oz"] {
            let widget = json(#"{ "name": "Water", "small": { "text": "$water.ml", "format": "\#(formatName)" } }"#)
            XCTAssertNil(SidekickWidgetDescription.validationError(widget), formatName)
        }
        let cups = json(#"{ "name": "Water", "small": { "text": "$water.ml", "format": "cups" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(cups), "small: format must be ml, l or oz")
    }
}
