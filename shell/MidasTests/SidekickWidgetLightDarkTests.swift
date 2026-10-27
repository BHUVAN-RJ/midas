import JavaScriptCore
import SwiftUI
import UIKit
import XCTest
@testable import Midas

// Light and dark for every widget (founder, 2026-10-27, docs/PRODUCT.md "Widget builder: light and
// dark for every widget"). Seen on build 20 in dark mode: Water's widget kept its light sand and
// sea while its text was the system colour, white on light. Checked here: every colour of a
// description takes { light, dark } (checker and filler); a single colour gets a derived dark one;
// text and symbols over the widget's own background get an ink chosen for it; and the drawing:
// Water's real widget (from its own code in tools.js) in light and dark, a widget with only single
// colours, and a dark background in light mode, each with its text read off the pixels and checked
// for contrast (4.5, body text). Renders are saved when MIDAS_WIDGET_RENDER_DIR is set
// (docs/mockups/widget-dark-{light,dark}-2026-10-27.png).

private let lightDarkRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let lightDarkCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func lightDarkOctober(_ day: Int, _ hour: Int) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour)
    return lightDarkCalendar.date(from: components)!
}

private func lightDarkJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

// Water's Tide by day and its night Tide (the page's dark tokens)
private let sandHex = "#F4EEE3"
private let nightSandHex = "#0E1A1E"
private let seaHex = "#9CCFD3"
private let nightSeaHex = "#2A6970"

private let pairText = ##"{ "light": "#24343A", "dark": "#E3EEEF" }"##

/// A rendered image's pixels, row 0 at the top.
private struct PixelImage {
    let width: Int
    let height: Int
    let scale: CGFloat
    let bytes: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        var buffer = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = buffer.withUnsafeMutableBytes { bufferPointer in
            guard let context = CGContext(data: bufferPointer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                          bytesPerRow: pixelWidth * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard drawn else {
            return nil
        }
        width = pixelWidth
        height = pixelHeight
        scale = image.scale
        bytes = buffer
    }

    func hex(column: Int, row: Int) -> String {
        let offset = (row * width + column) * 4
        return String(format: "#%02X%02X%02X", bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    /// The pixel at a point, in points.
    func hex(atX x: CGFloat, y: CGFloat) -> String {
        return hex(column: Int(x * scale), row: Int(y * scale))
    }

    func differs(from other: PixelImage, column: Int, row: Int) -> Bool {
        let offset = (row * width + column) * 4
        var difference = 0
        for channel in 0..<3 {
            difference += abs(Int(bytes[offset + channel]) - Int(other.bytes[offset + channel]))
        }
        return difference > 30
    }
}

/// One line of foreground (text) found in a drawing: its rows, and the highest contrast of any of
/// its pixels against what is drawn behind it there.
private struct ForegroundLine {
    let firstRow: Int
    let lastRow: Int
    let highestContrast: Double
}

@MainActor
final class SidekickWidgetLightDarkTests: XCTestCase {
    // MARK: Checker

    private func smallPieceError(_ pieceText: String) -> String? {
        let description = lightDarkJSON(#"{ "name": "W", "small": "# + pieceText + #" }"#)
        return SidekickWidgetDescription.validationError(description)
    }

    func testTheCheckerTakesLightAndDarkOnEveryColour() {
        let pieces = [
            #"{ "text": "hi", "color": PAIR }"#,
            #"{ "symbol": "drop.fill", "color": PAIR }"#,
            #"{ "button": "+1", "color": PAIR, "action": { "open": true } }"#,
            #"{ "chart": [1, 2, 3], "color": PAIR }"#,
            #"{ "ring": { "value": 1, "of": 2 }, "color": PAIR }"#,
            #"{ "bar": { "value": 1, "of": 2 }, "color": PAIR }"#,
            #"{ "dots": { "value": 1, "of": 2 }, "color": PAIR }"#,
            #"{ "timer": "$today.next.at", "color": PAIR }"#,
            #"{ "tick": "$today.next", "color": PAIR }"#,
            #"{ "fill": { "value": 1, "of": 2 }, "color": PAIR }"#,
            #"{ "text": "$item.time", "color": { "if": "$item.late", "then": PAIR, "else": PAIR } }"#,
            #"{ "text": "$item.time", "color": { "if": "$item.late", "then": PAIR, "else": "secondary" } }"#,
            #"{ "text": "hi", "color": { "light": "primary", "dark": "accent" } }"#,
        ]
        for piece in pieces {
            let pieceText = piece.replacingOccurrences(of: "PAIR", with: pairText)
            XCTAssertNil(smallPieceError(pieceText), pieceText)
        }
        let background = lightDarkJSON(##"{ "name": "W", "background": { "light": "#F4EEE3", "dark": "#0E1A1E" }, "small": { "spacer": true } }"##)
        XCTAssertNil(SidekickWidgetDescription.validationError(background))
    }

    func testTheCheckerStillTakesSingleColours() {
        // Widgets already on phones write one colour; they must keep working.
        XCTAssertNil(smallPieceError(##"{ "text": "hi", "color": "#24343A" }"##))
        XCTAssertNil(smallPieceError(##"{ "symbol": "drop.fill", "color": "accent" }"##))
        XCTAssertNil(smallPieceError(##"{ "text": "$item.time", "color": { "if": "$item.late", "then": "red", "else": "secondary" } }"##))
        let singleBackground = lightDarkJSON(##"{ "name": "W", "tint": "#2F7E87", "background": "#F4EEE3", "small": { "spacer": true } }"##)
        XCTAssertNil(SidekickWidgetDescription.validationError(singleBackground))
    }

    func testTheCheckerRefusesABrokenPair() {
        XCTAssertEqual(smallPieceError(##"{ "text": "hi", "color": { "light": "#24343A" } }"##), "small: color takes { light, dark }")
        XCTAssertEqual(smallPieceError(##"{ "button": "+1", "color": { "light": "#24343A", "dark": "night" }, "action": { "open": true } }"##),
                       "small: color night is not a colour name or #RRGGBB")
        let pairInAPairsChoice = ##"{ "text": "hi", "color": { "light": { "if": "$item.late", "then": { "light": "red", "dark": "red" } }, "dark": "red" } }"##
        XCTAssertEqual(smallPieceError(pairInAPairsChoice), "small: color must be a name or #RRGGBB")
        XCTAssertEqual(smallPieceError(##"{ "text": "hi", "color": { "if": "$item.late", "then": { "dark": "red" } } }"##), "small: color takes { light, dark }")
        let pairTint = lightDarkJSON(##"{ "name": "W", "tint": { "light": "#2F7E87", "dark": "#5FB3BA" }, "small": { "spacer": true } }"##)
        XCTAssertEqual(SidekickWidgetDescription.validationError(pairTint), "tint is not a colour", "the tint stays one colour")
    }

    // MARK: Filler

    private func filled(_ pieceText: String, scope: [String: JSONValue] = [:]) -> WidgetPiece? {
        let filler = SidekickWidgetFiller(calendar: lightDarkCalendar)
        return filler.filledPiece(lightDarkJSON(pieceText.replacingOccurrences(of: "PAIR", with: pairText)), scope: scope)
    }

    func testEveryPieceCarriesItsDarkColour() {
        guard case .text(let text)? = filled(#"{ "text": "hi", "color": PAIR }"#) else {
            return XCTFail("no text")
        }
        XCTAssertEqual(text.colorHex, "#24343A")
        XCTAssertEqual(text.darkColorHex, "#E3EEEF")
        guard case .symbol(let symbol)? = filled(#"{ "symbol": "drop.fill", "color": PAIR }"#) else {
            return XCTFail("no symbol")
        }
        XCTAssertEqual([symbol.colorHex, symbol.darkColorHex], ["#24343A", "#E3EEEF"])
        guard case .button(let button)? = filled(#"{ "button": "+1", "color": PAIR, "action": { "open": true } }"#) else {
            return XCTFail("no button")
        }
        XCTAssertEqual([button.colorHex, button.darkColorHex], ["#24343A", "#E3EEEF"])
        guard case .chart(let chart)? = filled(#"{ "chart": [1, 2, 3], "color": PAIR }"#) else {
            return XCTFail("no chart")
        }
        XCTAssertEqual([chart.colorHex, chart.darkColorHex], ["#24343A", "#E3EEEF"])
        guard case .ring(let ring)? = filled(#"{ "ring": { "value": 1, "of": 2 }, "color": PAIR }"#) else {
            return XCTFail("no ring")
        }
        XCTAssertEqual([ring.colorHex, ring.darkColorHex], ["#24343A", "#E3EEEF"])
        guard case .timer(let timer)? = filled(#"{ "timer": "2026-10-27T16:00:00.000Z", "color": PAIR }"#) else {
            return XCTFail("no timer")
        }
        XCTAssertEqual([timer.colorHex, timer.darkColorHex], ["#24343A", "#E3EEEF"])
        let itemScope: [String: JSONValue] = ["one": lightDarkJSON(#"{ "key": "thing:one" }"#)]
        guard case .tick(let tick)? = filled(#"{ "tick": "$one", "color": PAIR }"#, scope: itemScope) else {
            return XCTFail("no tick")
        }
        XCTAssertEqual([tick.colorHex, tick.darkColorHex], ["#24343A", "#E3EEEF"])
        guard case .fill(let fill)? = filled(#"{ "fill": { "value": 1, "of": 2 }, "color": PAIR }"#) else {
            return XCTFail("no fill")
        }
        XCTAssertEqual([fill.colorHex, fill.darkColorHex], ["#24343A", "#E3EEEF"])
    }

    func testAChoiceCanPickAPair() {
        let choice = ##"{ "text": "9:00 AM", "color": { "if": "$late", "then": { "light": "#FF3B30", "dark": "#FF453A" }, "else": "secondary" } }"##
        guard case .text(let late)? = filled(choice, scope: ["late": .bool(true)]),
              case .text(let coming)? = filled(choice, scope: ["late": .bool(false)]) else {
            return XCTFail("no text")
        }
        XCTAssertEqual(late.colorHex, "#FF3B30")
        XCTAssertEqual(late.darkColorHex, "#FF453A")
        XCTAssertNil(coming.colorHex)
        XCTAssertTrue(coming.isSecondary)
    }

    func testASingleColourLeavesTheDarkOneToTheDrawing() {
        guard case .text(let text)? = filled(##"{ "text": "hi", "color": "#24343A" }"##),
              case .button(let tinted)? = filled(##"{ "button": "+1", "action": { "open": true } }"##) else {
            return XCTFail("no pieces")
        }
        XCTAssertEqual(text.colorHex, "#24343A")
        XCTAssertNil(text.darkColorHex)
        XCTAssertNil(tinted.darkColorHex)
        guard case .symbol(let inked)? = filled(##"{ "symbol": "drop.fill", "color": "secondary" }"##),
              case .symbol(let accent)? = filled(##"{ "symbol": "drop.fill" }"##) else {
            return XCTFail("no symbols")
        }
        XCTAssertEqual(inked.ink, .secondary, "a secondary symbol is drawn in the ink")
        XCTAssertNil(accent.ink, "without a colour a symbol is the accent")
    }

    // MARK: Ink and derived colours

    func testTheInkIsDarkOnLightAndLightOnDark() {
        XCTAssertEqual(SidekickWidgetInk.inkHex(over: [sandHex, seaHex]), SidekickWidgetInk.darkInkHex)
        XCTAssertEqual(SidekickWidgetInk.inkHex(over: [nightSandHex, nightSeaHex]), SidekickWidgetInk.lightInkHex)
        XCTAssertEqual(SidekickWidgetInk.inkHex(over: ["#123A4A"]), SidekickWidgetInk.lightInkHex)
        for surfaces in [[sandHex, seaHex], [nightSandHex, nightSeaHex], ["#123A4A"], ["#FFCC00"]] {
            let inkHex = SidekickWidgetInk.inkHex(over: surfaces)
            XCTAssertGreaterThanOrEqual(SidekickWidgetInk.lowestContrast(inkHex, over: surfaces), 4.5, "\(surfaces)")
            let opacity = SidekickWidgetInk.secondaryOpacity(inkHex: inkHex, over: surfaces)
            XCTAssertLessThan(opacity, 1.0001)
            for surface in surfaces {
                let secondaryHex = SidekickWidgetInk.blend(inkHex, opacity: opacity, over: surface)
                XCTAssertGreaterThanOrEqual(SidekickWidgetInk.contrast(secondaryHex, surface), 4.5, "secondary over \(surface)")
            }
        }
        XCTAssertNil(WidgetSurfaceColors.system.inkHex, "over the system background, system colours stay")
    }

    func testADerivedDarkColourKeepsItsHueAndIsNeverPurple() throws {
        for lightHex in [sandHex, "#9CAF88", "#FFCC00", "#30D5C8", "#9CCFD3"] {
            let backgroundHex = SidekickWidgetInk.darkBackgroundHex(fromLight: lightHex)
            let fillHex = SidekickWidgetInk.darkFillHex(fromLight: lightHex)
            let lightHue = try XCTUnwrap(SidekickWidgetInk.hsl(lightHex)?.hue)
            for darkHex in [backgroundHex, fillHex] {
                let darkHue = try XCTUnwrap(SidekickWidgetInk.hsl(darkHex)?.hue)
                let hueDistance = min(abs(darkHue - lightHue), 360 - abs(darkHue - lightHue))
                XCTAssertLessThan(hueDistance, 8, "\(lightHex) → \(darkHex)")
                XCTAssertFalse(darkHue > 260 && darkHue < 320, "\(darkHex) is purple")
            }
            XCTAssertLessThan(try XCTUnwrap(SidekickWidgetInk.luminance(backgroundHex)), 0.03, "\(lightHex) background goes dark")
            XCTAssertGreaterThanOrEqual(SidekickWidgetInk.contrast(SidekickWidgetInk.lightInkHex, backgroundHex), 4.5)
            XCTAssertGreaterThan(SidekickWidgetInk.contrast(fillHex, backgroundHex), 1.4, "\(lightHex) sea shows above the night")
        }
    }

    func testADerivedForegroundReadsOverWhatIsBehindIt() {
        let systemDark = [SidekickWidgetInk.systemDarkBackgroundHex]
        for (lightHex, surfaces) in [("#24343A", [nightSandHex]), ("#007AFF", systemDark), ("#2F7E87", [nightSandHex, nightSeaHex])] {
            let darkHex = SidekickWidgetInk.readableHex(lightHex, over: surfaces, minimumContrast: SidekickWidgetInk.textContrast)
            XCTAssertGreaterThanOrEqual(SidekickWidgetInk.lowestContrast(darkHex, over: surfaces), 4.5, "\(lightHex) → \(darkHex)")
        }
        XCTAssertEqual(SidekickWidgetInk.readableHex("#5FB3BA", over: [nightSandHex], minimumContrast: 4.5), "#5FB3BA", "kept when it reads")
        let surface = WidgetSurfaceColors(hexes: [nightSandHex])
        XCTAssertEqual(surface.foregroundHex(lightHex: "#2F7E87", darkHex: "#5FB3BA", isDark: true, minimumContrast: 4.5), "#5FB3BA", "a given dark colour is drawn as it is")
        XCTAssertEqual(surface.foregroundHex(lightHex: "#2F7E87", darkHex: "#5FB3BA", isDark: false, minimumContrast: 4.5), "#2F7E87")
    }

    // MARK: Drawing

    private func waterWidgetFromItsPage() throws -> JSONValue {
        let toolsSource = try String(contentsOf: lightDarkRepoRoot.appending(path: "sidekicks/hydration/tools.js"), encoding: .utf8)
        let beginRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: begin */"))
        let endRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: end */", range: beginRange.upperBound..<toolsSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(toolsSource[beginRange.upperBound..<endRange.lowerBound]))
        XCTAssertNil(context.exception)
        let script = "JSON.stringify(WaterLogic.widgetRecords(WaterLogic.settingsFrom({ goalMl: 2500, unit: 'l' }))[0].value)"
        let widgetText = try XCTUnwrap(context.evaluateScript(script)?.toString())
        return lightDarkJSON(widgetText)
    }

    // Today (Oct 25) at 1,000 of 2,500 ml (the sea 40% up), yesterday at the goal (a 1 day streak)
    private func screen(widget: JSONValue, size: SidekickWidgetSize) -> SidekickWidgetScreen {
        let records = [
            LocalRecord(sidekickId: "hydration", key: "widget:today", value: widget),
            LocalRecord(sidekickId: "hydration", key: "settings:main", value: lightDarkJSON(#"{ "goalMl": 2500, "unit": "l" }"#)),
            LocalRecord(sidekickId: "hydration", key: "water:2026-10-24", value: lightDarkJSON(#"{ "ml": 2500, "goalMl": 2500 }"#)),
            LocalRecord(sidekickId: "hydration", key: "water:2026-10-25", value: lightDarkJSON(#"{ "ml": 1000 }"#)),
        ]
        let filler = SidekickWidgetFiller(calendar: lightDarkCalendar)
        let filledWidget = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: records[0], sidekickRecords: records, now: lightDarkOctober(25, 15))
        let file = SharedSidekickWidgets(widgets: [filledWidget], savedAt: lightDarkOctober(25, 15))
        return SidekickWidgetLayout.screen(file: file, sidekickId: "hydration", widgetChoiceId: "hydration/today", size: size, at: lightDarkOctober(25, 15))
    }

    private func render<Content: View>(_ content: Content, colorScheme: ColorScheme) throws -> PixelImage {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        // Drawn twice, the first one thrown away (a first drawing once came back blank)
        _ = renderer.uiImage
        let image = try XCTUnwrap(renderer.uiImage)
        return try XCTUnwrap(PixelImage(image))
    }

    private func backdropOnly(_ screen: SidekickWidgetScreen, size: SidekickWidgetSize) -> some View {
        return SidekickWidgetBackdrop(screen: screen)
            .frame(width: SidekickWidgetSnapshot.width(of: size), height: SidekickWidgetSnapshot.height(of: size))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// The lines of foreground inside the margins, top first: where the widget differs from its
    /// backdrop drawn alone, rows grouped with gaps of at most two pixels.
    private func foregroundLines(_ screen: SidekickWidgetScreen, size: SidekickWidgetSize, colorScheme: ColorScheme) throws -> [ForegroundLine] {
        let full = try render(SidekickWidgetSnapshot(screen: screen, size: size), colorScheme: colorScheme)
        let backdrop = try render(backdropOnly(screen, size: size), colorScheme: colorScheme)
        XCTAssertEqual(full.width, backdrop.width)
        let margin = Int(16 * full.scale)
        var lines: [ForegroundLine] = []
        var currentFirstRow: Int?
        var currentLastRow = 0
        var currentContrast = 1.0
        for row in margin..<(full.height - margin) {
            var rowContrast: Double?
            for column in margin..<(full.width - margin) where full.differs(from: backdrop, column: column, row: row) {
                let pixelContrast = SidekickWidgetInk.contrast(full.hex(column: column, row: row), backdrop.hex(column: column, row: row))
                rowContrast = max(rowContrast ?? 1, pixelContrast)
            }
            guard let rowContrast else {
                continue
            }
            if let firstRow = currentFirstRow, row - currentLastRow > 3 {
                lines.append(ForegroundLine(firstRow: firstRow, lastRow: currentLastRow, highestContrast: currentContrast))
                currentFirstRow = nil
            }
            if currentFirstRow == nil {
                currentFirstRow = row
                currentContrast = 1
            }
            currentLastRow = row
            currentContrast = max(currentContrast, rowContrast)
        }
        if let firstRow = currentFirstRow {
            lines.append(ForegroundLine(firstRow: firstRow, lastRow: currentLastRow, highestContrast: currentContrast))
        }
        return lines
    }

    private func assertClose(_ actualHex: String, _ expectedHex: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let actual = SidekickColor.rgbComponents(fromHex: actualHex)
        let expected = SidekickColor.rgbComponents(fromHex: expectedHex)
        guard let actual, let expected else {
            return XCTFail("no colour: \(message)", file: file, line: line)
        }
        let differences = [abs(actual.red - expected.red), abs(actual.green - expected.green), abs(actual.blue - expected.blue)]
        XCTAssertLessThanOrEqual((differences.max() ?? 1) * 255, 4, "\(message): \(actualHex) is not \(expectedHex)", file: file, line: line)
    }

    /// The first `count` lines (the texts above the buttons) all read as body text.
    private func assertTextReads(_ lines: [ForegroundLine], count: Int, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(lines.count, count, "\(message): lines of text found", file: file, line: line)
        for (index, foundLine) in lines.prefix(count).enumerated() {
            XCTAssertGreaterThanOrEqual(foundLine.highestContrast, 4.5, "\(message): line \(index + 1) (rows \(foundLine.firstRow)–\(foundLine.lastRow))", file: file, line: line)
        }
    }

    func testWatersWidgetIsTheTideByDayAndTheNightTideInDarkMode() throws {
        let water = try waterWidgetFromItsPage()
        for (colorScheme, backgroundHex, fillHex) in [(ColorScheme.light, sandHex, seaHex), (ColorScheme.dark, nightSandHex, nightSeaHex)] {
            for size in SidekickWidgetSize.allCases {
                let width = SidekickWidgetSnapshot.width(of: size)
                let height = SidekickWidgetSnapshot.height(of: size)
                let image = try render(SidekickWidgetSnapshot(screen: screen(widget: water, size: size), size: size), colorScheme: colorScheme)
                assertClose(image.hex(atX: width - 20, y: 20), backgroundHex, "\(colorScheme) \(size) sand at the top")
                assertClose(image.hex(atX: width - 20, y: height - 10), fillHex, "\(colorScheme) \(size) sea at the bottom")
            }
        }
    }

    func testWatersTextReadsOverItsSandInLightAndDark() throws {
        let water = try waterWidgetFromItsPage()
        for colorScheme in [ColorScheme.light, ColorScheme.dark] {
            for size in [SidekickWidgetSize.small, .medium] {
                // The amount, the goal and the streak, above the buttons
                let lines = try foregroundLines(screen(widget: water, size: size), size: size, colorScheme: colorScheme)
                assertTextReads(lines, count: 3, "Water \(colorScheme) \(size)")
            }
        }
    }

    func testAWidgetWithSingleColoursGetsADerivedNight() throws {
        let oldWidget = lightDarkJSON(##"""
        { "name": "Old", "tint": "#2F7E87", "background": "#F4EEE3",
          "sources": { "day": { "record": "water:{today}" }, "settings": { "record": "settings:main" } },
          "small": { "fill": { "value": "$day.ml", "of": "$settings.goalMl" }, "color": "#9CCFD3", "edge": "wave",
                     "content": { "vstack": [
                       { "text": "$day.ml", "format": "l", "style": "title" },
                       { "text": "of $settings.goalMl", "format": "l", "style": "caption", "color": "secondary" },
                       { "spacer": true },
                       { "button": "+250 ml", "action": { "increment": "water:{today}", "field": "ml", "by": 250 } } ] } } }
        """##)
        let oldScreen = screen(widget: oldWidget, size: .small)
        let dark = try render(SidekickWidgetSnapshot(screen: oldScreen, size: .small), colorScheme: .dark)
        assertClose(dark.hex(atX: 150, y: 20), SidekickWidgetInk.darkBackgroundHex(fromLight: sandHex), "derived night sand")
        assertClose(dark.hex(atX: 150, y: 160), SidekickWidgetInk.darkFillHex(fromLight: seaHex), "derived night sea")
        let light = try render(SidekickWidgetSnapshot(screen: oldScreen, size: .small), colorScheme: .light)
        assertClose(light.hex(atX: 150, y: 20), sandHex, "sand by day, as before")
        for colorScheme in [ColorScheme.light, ColorScheme.dark] {
            let lines = try foregroundLines(oldScreen, size: .small, colorScheme: colorScheme)
            assertTextReads(lines, count: 2, "single colours \(colorScheme)")
        }
    }

    func testTextOverADarkBackgroundInLightModeIsLightInk() throws {
        // The build 20 bug the other way round: the system colour (black in light mode) on a
        // background of the widget's own that is dark.
        let navyWidget = lightDarkJSON(##"""
        { "name": "Navy", "background": "#123A4A",
          "small": { "vstack": [ { "text": "Ninety", "style": "title" }, { "text": "minutes left", "style": "caption", "color": "secondary" },
                                 { "symbol": "moon.fill", "color": "primary", "size": 20 } ], "align": "leading" } }
        """##)
        let lines = try foregroundLines(screen(widget: navyWidget, size: .small), size: .small, colorScheme: .light)
        assertTextReads(lines, count: 3, "navy, light mode")
    }

    func testTheAddToHomeScreenDemoDrawsTheNightTideInDarkMode() throws {
        let water = try waterWidgetFromItsPage()
        let demo = HomeScreenDemoWidget(look: .filled(screen(widget: water, size: .small)), family: .small, width: 170, height: 170,
                                        ink: HomeScreenDemoInk(colorScheme: .dark))
        let image = try render(demo, colorScheme: .dark)
        assertClose(image.hex(atX: 150, y: 20), nightSandHex, "night sand in the demo")
        assertClose(image.hex(atX: 150, y: 160), nightSeaHex, "night sea in the demo")
        var amountContrast = 1.0
        for row in Int(18 * image.scale)..<Int(36 * image.scale) {
            for column in Int(16 * image.scale)..<Int(90 * image.scale) {
                amountContrast = max(amountContrast, SidekickWidgetInk.contrast(image.hex(column: column, row: row), nightSandHex))
            }
        }
        XCTAssertGreaterThanOrEqual(amountContrast, 4.5, "the amount reads in the demo")
    }

    /// Water small, medium and large side by side on a plain wallpaper; saved only when asked for.
    func testRenderWatersWidgetLightAndDark() throws {
        let water = try waterWidgetFromItsPage()
        for (colorScheme, modeName) in [(ColorScheme.light, "light"), (ColorScheme.dark, "dark")] {
            let wallpaper = colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.11) : Color(red: 0.86, green: 0.87, blue: 0.9)
            let board = HStack(alignment: .top, spacing: 22) {
                SidekickWidgetSnapshot(screen: screen(widget: water, size: .small), size: .small)
                SidekickWidgetSnapshot(screen: screen(widget: water, size: .medium), size: .medium)
                SidekickWidgetSnapshot(screen: screen(widget: water, size: .large), size: .large)
            }
            .padding(24)
            .background(wallpaper)
            let renderer = ImageRenderer(content: board.environment(\.colorScheme, colorScheme))
            renderer.scale = 3
            _ = renderer.uiImage
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, CGSize(width: 24 + 170 + 22 + 364 + 22 + 364 + 24, height: 24 + 382 + 24))
            guard let renderDirectory = ProcessInfo.processInfo.environment["MIDAS_WIDGET_RENDER_DIR"] else {
                continue
            }
            let pngData = try XCTUnwrap(image.pngData())
            try pngData.write(to: URL(filePath: renderDirectory).appending(path: "widget-dark-\(modeName)-2026-10-27.png"))
        }
    }
}
