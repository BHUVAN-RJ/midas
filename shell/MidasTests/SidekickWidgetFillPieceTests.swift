import SwiftUI
import UIKit
import XCTest
@testable import Midas

// Hydration plan W4 (founder, 2026-10-25; docs/briefs/hydration-sidekick.md section 2.1, look
// "E. Tide"): the `fill` piece, `{ fill: { value, of }, color, edge: 'wave', content: { … } }`, a
// colour rising from the bottom to value/of with a still wave and its content on top, and the
// description's own `background` colour. Colours may be `{ light, dark }`. Checked, filled
// (clamped to 0…1), carried through the App Group file, and drawn: the drawing is checked by its
// pixels and saved as PNGs when MIDAS_WIDGET_RENDER_DIR is set
// (docs/mockups/hydration-widget-render-{light,dark}-2026-10-25.png).

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let sandHex = "#F4EEE3"
private let nightHex = "#0F2229"
private let seaHex = "#9CCFD3"
private let nightSeaHex = "#2E6E77"

private let tideWidget = json(#"""
{ "name": "Water today",
  "tint": "#2E7D86",
  "background": { "light": "#F4EEE3", "dark": "#0F2229" },
  "sources": { "water": { "record": "water:{today}" },
               "settings": { "record": "settings:main" },
               "streak": { "records": "water:", "streak": { "field": "ml", "goal": "$settings.goalMl", "dayGoalField": "goalMl" } } },
  "small": { "fill": { "value": "$water.ml", "of": "$settings.goalMl" },
             "color": { "light": "#9CCFD3", "dark": "#2E6E77" }, "edge": "wave",
             "content": { "vstack": [
               { "text": "$water.ml", "format": "l", "style": "number" },
               { "text": "of $settings.goalMl", "format": "l", "style": "caption", "color": "secondary" },
               { "spacer": true },
               { "text": "$streak.days day streak", "style": "caption" },
               { "button": "+250 ml", "action": { "increment": "water:{today}", "field": "ml", "by": 250 } } ] } },
  "medium": { "fill": { "value": "$water.ml", "of": "$settings.goalMl" },
              "color": { "light": "#9CCFD3", "dark": "#2E6E77" }, "edge": "wave",
              "content": { "hstack": [
                { "vstack": [
                  { "text": "$water.ml", "format": "l", "style": "number" },
                  { "text": "of $settings.goalMl", "format": "l", "style": "caption", "color": "secondary" },
                  { "spacer": true },
                  { "text": "$streak.days day streak", "style": "caption" } ], "align": "leading" },
                { "spacer": true },
                { "vstack": [
                  { "button": "+250 ml", "action": { "increment": "water:{today}", "field": "ml", "by": 250 } },
                  { "button": "+500 ml", "action": { "increment": "water:{today}", "field": "ml", "by": 500 } },
                  { "button": "+750 ml", "action": { "increment": "water:{today}", "field": "ml", "by": 750 } } ], "align": "trailing" } ], "align": "top" } } }
"""#)

private func tideRecords(ml: Int) -> [LocalRecord] {
    return [
        LocalRecord(sidekickId: "hydration", key: "widget:today", value: tideWidget),
        LocalRecord(sidekickId: "hydration", key: "settings:main", value: json(#"{ "goalMl": 2500 }"#)),
        LocalRecord(sidekickId: "hydration", key: "water:2026-10-23", value: json(#"{ "ml": 2500 }"#)),
        LocalRecord(sidekickId: "hydration", key: "water:2026-10-24", value: json(#"{ "ml": 2600 }"#)),
        LocalRecord(sidekickId: "hydration", key: "water:2026-10-25", value: json(#"{ "ml": \#(ml) }"#)),
    ]
}

@MainActor
final class SidekickWidgetFillPieceTests: XCTestCase {
    private func filledTide(ml: Int) -> FilledSidekickWidget {
        let records = tideRecords(ml: ml)
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        return filler.fill(sidekickId: "hydration", sidekickName: "Water", record: records[0], sidekickRecords: records, now: octoberPT(25, 15))
    }

    private func smallFill(ml: Int) -> WidgetFillPiece? {
        guard let small = filledTide(ml: ml).looks.first?.small else {
            return nil
        }
        return SidekickWidgetSurface.edgeFill(of: small)
    }

    // MARK: Checker

    func testTheCheckerAcceptsTheTideWidget() {
        XCTAssertNil(SidekickWidgetDescription.validationError(tideWidget))
        let plainColours = json(##"{ "name": "W", "background": "#F4EEE3", "small": { "fill": { "value": 1, "of": 2 }, "color": "cyan" } }"##)
        XCTAssertNil(SidekickWidgetDescription.validationError(plainColours))
    }

    func testTheCheckerRefusesABrokenFill() {
        let noTotal = json(#"{ "name": "W", "small": { "fill": { "value": 1 } } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(noTotal), "small: fill needs of: a number or a binding")
        let notAnObject = json(#"{ "name": "W", "small": { "fill": 0.5 } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(notAnObject), "small: fill takes { value, of }")
        let zigzag = json(#"{ "name": "W", "small": { "fill": { "value": 1, "of": 2 }, "edge": "zigzag" } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(zigzag), "small: edge must be wave or flat")
        let badContent = json(#"{ "name": "W", "small": { "fill": { "value": 1, "of": 2 }, "content": { "text": 5 } } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(badContent), "small: text takes words, up to 200 characters")
        let halfPair = json(##"{ "name": "W", "small": { "fill": { "value": 1, "of": 2 }, "color": { "light": "#FFFFFF" } } }"##)
        XCTAssertEqual(SidekickWidgetDescription.validationError(halfPair), "small: color takes { light, dark }")
        let pairOnText = json(##"{ "name": "W", "small": { "text": "hi", "color": { "light": "#FFFFFF", "dark": "#000000" } } }"##)
        XCTAssertNil(SidekickWidgetDescription.validationError(pairOnText), "a light/dark pair is taken on every piece (2026-10-27)")
    }

    func testTheCheckerRefusesABadBackground() {
        let badBackground = json(#"{ "name": "W", "background": "sand", "small": { "spacer": true } }"#)
        XCTAssertEqual(SidekickWidgetDescription.validationError(badBackground), "background is not a colour or { light, dark }")
        let badDark = json(##"{ "name": "W", "background": { "light": "#F4EEE3", "dark": "night" }, "small": { "spacer": true } }"##)
        XCTAssertEqual(SidekickWidgetDescription.validationError(badDark), "background is not a colour or { light, dark }")
    }

    func testAFillsContentCountsTowardTheLimits() {
        // Twelve fills deep is the limit; the thirteenth level is refused.
        var piece: JSONValue = json(#"{ "spacer": true }"#)
        for _ in 0..<13 {
            piece = .object(["fill": json(#"{ "value": 1, "of": 2 }"#), "content": piece])
        }
        let tooDeep = JSONValue.object(["name": .string("W"), "small": piece])
        XCTAssertEqual(SidekickWidgetDescription.validationError(tooDeep), "small: pieces nested deeper than 12")
        var children: [JSONValue] = []
        for _ in 0..<38 {
            children.append(json(#"{ "fill": { "value": 1, "of": 2 }, "content": { "vstack": [ { "spacer": true }, { "spacer": true }, { "spacer": true } ] } }"#))
        }
        let tooMany = JSONValue.object(["name": .string("W"), "small": .object(["vstack": .array(children)])])
        XCTAssertEqual(SidekickWidgetDescription.validationError(tooMany), "small: more than 150 pieces")
    }

    // MARK: Filling

    func testTheFillIsTheDaysShareOfTheGoal() {
        XCTAssertEqual(smallFill(ml: 1250)?.fraction, 0.5)
        XCTAssertEqual(smallFill(ml: 0)?.fraction, 0)
        XCTAssertEqual(smallFill(ml: 1250)?.edge, .wave)
        XCTAssertEqual(smallFill(ml: 1250)?.colorHex, seaHex)
        XCTAssertEqual(smallFill(ml: 1250)?.darkColorHex, nightSeaHex)
    }

    func testTheFillIsClampedToZeroThroughOne() {
        XCTAssertEqual(smallFill(ml: 2750)?.fraction, 1)
        XCTAssertEqual(SidekickWidgetFiller.clampedFraction(value: -100, total: 2500), 0)
        XCTAssertEqual(SidekickWidgetFiller.clampedFraction(value: 100, total: 0), 0)
        XCTAssertEqual(SidekickWidgetFiller.clampedFraction(value: 3000, total: 2500), 1)
    }

    func testTheContentIsFilledOnTop() {
        guard let small = filledTide(ml: 1250).looks.first?.small,
              case .vstack(let column)? = SidekickWidgetSurface.foreground(of: small) else {
            return XCTFail("no content")
        }
        var texts: [String] = []
        for child in column.children {
            if case .text(let textPiece) = child {
                texts.append(textPiece.text)
            }
        }
        XCTAssertEqual(texts, ["1.25 L", "of 2.5 L", "2 day streak"])
    }

    func testTheBackgroundWrapsTheWholeLook() {
        guard let small = filledTide(ml: 1250).looks.first?.small, case .background(let background) = small else {
            return XCTFail("no background")
        }
        XCTAssertEqual(background.colorHex, sandHex)
        XCTAssertEqual(background.darkColorHex, nightHex)
        guard case .fill = background.content else {
            return XCTFail("the fill is not inside the background")
        }
        let plain = json(#"{ "name": "W", "small": { "fill": { "value": 1, "of": 4 } } }"#)
        let plainRecord = LocalRecord(sidekickId: "hydration", key: "widget:plain", value: plain)
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        let plainWidget = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: plainRecord, sidekickRecords: [plainRecord], now: octoberPT(25, 15))
        guard case .fill(let plainFill)? = plainWidget.looks.first?.small else {
            return XCTFail("a widget without background is wrapped")
        }
        XCTAssertEqual(plainFill.fraction, 0.25)
        XCTAssertNil(plainFill.colorHex, "no colour and no tint: the system tint")
    }

    func testAFillAndBackgroundSurviveTheAppGroupFile() throws {
        let file = SharedSidekickWidgets(widgets: [filledTide(ml: 1250)], savedAt: octoberPT(25, 15))
        let decoded = SharedSidekickWidgets.decoded(from: try file.encoded())
        XCTAssertEqual(decoded, file)
        let decodedSmall = try XCTUnwrap(decoded?.widgets.first?.looks.first?.small)
        XCTAssertEqual(SidekickWidgetSurface.edgeFill(of: decodedSmall)?.fraction, 0.5)
    }

    // MARK: Drawing

    private func screen(ml: Int, size: SidekickWidgetSize) -> SidekickWidgetScreen {
        let file = SharedSidekickWidgets(widgets: [filledTide(ml: ml)], savedAt: octoberPT(25, 15))
        return SidekickWidgetLayout.screen(file: file, sidekickId: "hydration", widgetChoiceId: "hydration/today", size: size, at: octoberPT(25, 15))
    }

    private func render<Content: View>(_ content: Content, colorScheme: ColorScheme) -> UIImage? {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        // Drawn twice, the first one thrown away: once, on a freshly made simulator, a first
        // drawing came back blank (2026-10-25).
        _ = renderer.uiImage
        return renderer.uiImage
    }

    /// The pixel at a point (in points) as "#RRGGBB".
    private func hexColor(of image: UIImage, atX x: CGFloat, y: CGFloat) -> String? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        let pixelX = x * image.scale
        let pixelY = CGFloat(cgImage.height) - y * image.scale - 1
        context.draw(cgImage, in: CGRect(x: -pixelX, y: -pixelY, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    private func assertClose(_ actualHex: String?, _ expectedHex: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let actualHex, actualHex.count == 7 else {
            return XCTFail("no pixel: \(message)", file: file, line: line)
        }
        let actualDigits = Array(actualHex.dropFirst())
        let expectedDigits = Array(expectedHex.dropFirst())
        for channel in 0..<3 {
            let actualValue = Int(String(actualDigits[(channel * 2)...(channel * 2 + 1)]), radix: 16) ?? -1
            let expectedValue = Int(String(expectedDigits[(channel * 2)...(channel * 2 + 1)]), radix: 16) ?? -1
            XCTAssertLessThanOrEqual(abs(actualValue - expectedValue), 4, "\(message): \(actualHex) is not \(expectedHex)", file: file, line: line)
        }
    }

    func testTheSeaIsDrawnBelowTheLineAndTheSandAbove() throws {
        for (colorScheme, backgroundHex, fillHex) in [(ColorScheme.light, sandHex, seaHex), (ColorScheme.dark, nightHex, nightSeaHex)] {
            let snapshot = SidekickWidgetSnapshot(screen: screen(ml: 1250, size: .small), size: .small)
            let image = try XCTUnwrap(render(snapshot, colorScheme: colorScheme))
            XCTAssertEqual(image.size, CGSize(width: 170, height: 170))
            // Half full: the sea up to y = 85 (the wave moves it 3 points either way).
            assertClose(hexColor(of: image, atX: 150, y: 150), fillHex, "\(colorScheme) bottom")
            assertClose(hexColor(of: image, atX: 150, y: 100), fillHex, "\(colorScheme) just under the line")
            assertClose(hexColor(of: image, atX: 150, y: 70), backgroundHex, "\(colorScheme) just over the line")
            assertClose(hexColor(of: image, atX: 150, y: 20), backgroundHex, "\(colorScheme) top")
        }
    }

    func testAnEmptyDayIsAllSandAndAMetDayAllSea() throws {
        let emptyImage = try XCTUnwrap(render(SidekickWidgetSnapshot(screen: screen(ml: 0, size: .small), size: .small), colorScheme: .light))
        assertClose(hexColor(of: emptyImage, atX: 150, y: 150), sandHex, "empty bottom")
        let fullImage = try XCTUnwrap(render(SidekickWidgetSnapshot(screen: screen(ml: 3000, size: .small), size: .small), colorScheme: .light))
        assertClose(hexColor(of: fullImage, atX: 150, y: 20), seaHex, "full top")
    }

    /// Small and medium, side by side on a plain wallpaper; saved only when asked for.
    func testRenderTheTideWidgetLightAndDark() throws {
        for (colorScheme, modeName) in [(ColorScheme.light, "light"), (ColorScheme.dark, "dark")] {
            let wallpaper = colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.11) : Color(red: 0.86, green: 0.87, blue: 0.9)
            let board = HStack(alignment: .top, spacing: 22) {
                SidekickWidgetSnapshot(screen: screen(ml: 1250, size: .small), size: .small)
                SidekickWidgetSnapshot(screen: screen(ml: 1250, size: .medium), size: .medium)
            }
            .padding(24)
            .background(wallpaper)
            let image = try XCTUnwrap(render(board, colorScheme: colorScheme))
            XCTAssertEqual(image.size, CGSize(width: 24 + 170 + 22 + 364 + 24, height: 24 + 170 + 24))
            let pngData = try XCTUnwrap(image.pngData())
            guard let renderDirectory = ProcessInfo.processInfo.environment["MIDAS_WIDGET_RENDER_DIR"] else {
                continue
            }
            let fileURL = URL(filePath: renderDirectory).appending(path: "hydration-widget-render-\(modeName)-2026-10-25.png")
            try pngData.write(to: fileURL)
        }
    }
}
