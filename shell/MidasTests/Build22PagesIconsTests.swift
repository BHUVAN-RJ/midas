import JavaScriptCore
import SwiftUI
import UIKit
import XCTest
@testable import Midas

// Build 22, pages and icons (founder, 2026-10-31, docs/briefs/build-22-2026-10-31.md):
// - Water's widget at 0 L, option A of docs/mockups/water-zero-and-help-2026-10-27.html part 1: a
//   fill `floor` (the page sends 0.1) keeps a thin low tide at 0 and still reaches the top at the
//   goal (`SidekickWidgetFiller.filledFill`).
// - An hourly time ticked early counts: a tick on the widget's next dose before its time marks
//   that time done (`ReminderChange.donePatch`, `.slot`).
// - Every Sidekick tile has a light and a dark variant (docs/ICONS.md): the manifest's
//   `icon.backgroundDark`, and the shell's drawn artwork in both palettes.

private let buildCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
private let buildRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func octoberLA(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return buildCalendar.date(from: components)!
}

private func buildJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@MainActor
final class Build22PagesIconsTests: XCTestCase {
    // MARK: Water at 0 L: the fill floor

    private func seaWidget(floor: String) -> JSONValue {
        return buildJSON(#"""
        { "name": "Water", "background": "#F4EEE3",
          "sources": { "day": { "record": "water:{today}" }, "settings": { "record": "settings:main" } },
          "small": { "fill": { "value": "$day.ml", "of": "$settings.goalMl" }, "floor": \#(floor), "color": "#9CCFD3", "edge": "wave",
                     "content": { "text": "$day.ml" } } }
        """#)
    }

    private func smallSea(_ widget: JSONValue, todayMl: Int?) throws -> WidgetFillPiece {
        var records = [
            LocalRecord(sidekickId: "hydration", key: "widget:today", value: widget),
            LocalRecord(sidekickId: "hydration", key: "settings:main", value: buildJSON(#"{ "goalMl": 2500 }"#)),
        ]
        if let todayMl {
            records.append(LocalRecord(sidekickId: "hydration", key: "water:2026-10-31", value: buildJSON(#"{ "ml": \#(todayMl) }"#)))
        }
        let filler = SidekickWidgetFiller(calendar: buildCalendar)
        let filled = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: records[0], sidekickRecords: records, now: octoberLA(31, 15))
        let small = try XCTUnwrap(filled.looks.first?.small)
        return try XCTUnwrap(SidekickWidgetSurface.edgeFill(of: small))
    }

    func testTheCheckerTakesAFloorFromZeroToHalf() {
        XCTAssertNil(SidekickWidgetDescription.validationError(seaWidget(floor: "0.1")))
        XCTAssertNil(SidekickWidgetDescription.validationError(seaWidget(floor: "0")))
        XCTAssertNil(SidekickWidgetDescription.validationError(seaWidget(floor: "0.5")))
        XCTAssertEqual(SidekickWidgetDescription.validationError(seaWidget(floor: "0.6")), "small: floor must be 0 to 0.5")
        XCTAssertEqual(SidekickWidgetDescription.validationError(seaWidget(floor: "-0.1")), "small: floor must be 0 to 0.5")
        XCTAssertEqual(SidekickWidgetDescription.validationError(seaWidget(floor: #""low""#)), "small: floor must be 0 to 0.5")
    }

    func testAFloorKeepsALowTideAtZeroAndStillFillsAtTheGoal() throws {
        let widget = seaWidget(floor: "0.1")
        XCTAssertEqual(try smallSea(widget, todayMl: nil).fraction, 0.1, accuracy: 1e-9, "no record yet: the low tide")
        XCTAssertEqual(try smallSea(widget, todayMl: 0).fraction, 0.1, accuracy: 1e-9)
        XCTAssertEqual(try smallSea(widget, todayMl: 1250).fraction, 0.55, accuracy: 1e-9, "half the goal: half of the rest above the floor")
        XCTAssertEqual(try smallSea(widget, todayMl: 2500).fraction, 1, accuracy: 1e-9)
        XCTAssertEqual(try smallSea(widget, todayMl: 4000).fraction, 1, accuracy: 1e-9, "never past the top")
    }

    func testWithoutAFloorZeroIsStillAnEmptySea() throws {
        let noFloor = buildJSON(#"""
        { "name": "W", "sources": { "day": { "record": "water:{today}" }, "settings": { "record": "settings:main" } },
          "small": { "fill": { "value": "$day.ml", "of": "$settings.goalMl" } } }
        """#)
        XCTAssertEqual(try smallSea(noFloor, todayMl: 0).fraction, 0)
        XCTAssertEqual(SidekickWidgetFiller.flooredFraction(0.5, floor: 0), 0.5)
        XCTAssertEqual(SidekickWidgetFiller.flooredFraction(0, floor: 0.9), 0.5, accuracy: 1e-9, "a floor is kept to half")
    }

    func testTheWaterPageSendsTheLowTideFloor() throws {
        let toolsURL = buildRepoRoot.appending(path: "sidekicks/hydration/tools.js")
        let toolsSource = try String(contentsOf: toolsURL, encoding: .utf8)
        let beginRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: begin */"))
        let endRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: end */", range: beginRange.upperBound..<toolsSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(toolsSource[beginRange.upperBound..<endRange.lowerBound]))
        let recordsText = try XCTUnwrap(context.evaluateScript("JSON.stringify(WaterLogic.widgetRecords(WaterLogic.settingsFrom({ goalMl: 2500, unit: 'l' }))[0].value)")?.toString())
        let tide = buildJSON(recordsText)
        XCTAssertNil(SidekickWidgetDescription.validationError(tide))
        XCTAssertEqual(tide["small"]?["floor"], .number(0.1))
        XCTAssertEqual(try smallSea(tide, todayMl: nil).fraction, 0.1, accuracy: 1e-9, "the page's widget at 0 L shows the low tide")
    }

    // MARK: An hourly time ticked early counts

    private let hourly: JSONValue = .object([
        "$type": .string("care.item"), "title": .string("Pills"), "at": .string(ReminderRecord.formatDate(octoberLA(12, 0))),
        "timeZone": .string("America/Los_Angeles"), "done": .bool(false),
        "repeat": .object(["every": .string("day")]), "everyHours": .number(4),
    ])

    func testATimeTickedBeforeItComesIsDoneAtThatTime() {
        let noon = octoberLA(13, 12)
        let early = ReminderChange.donePatch(for: hourly, part: .slot(time: "12:00"), occurrence: noon, now: octoberLA(13, 11, 50))
        XCTAssertEqual(early["slotsDone"]?["12:00"], .string(ReminderRecord.formatDate(noon)))
        let late = ReminderChange.donePatch(for: hourly, part: .slot(time: "12:00"), occurrence: noon, now: octoberLA(13, 12, 20))
        XCTAssertEqual(late["slotsDone"]?["12:00"], .string(ReminderRecord.formatDate(octoberLA(13, 12, 20))), "on time or late: when it was tapped")
        let unknown = ReminderChange.donePatch(for: hourly, part: .slot(time: "12:00"), occurrence: nil, now: octoberLA(13, 11, 50))
        XCTAssertEqual(unknown["slotsDone"]?["12:00"], .string(ReminderRecord.formatDate(octoberLA(13, 11, 50))))
    }

    func testAnEarlyTickOnTheWidgetTakesThatDoseOffToday() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "early-tick-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        let widget = buildJSON(#"""
        { "name": "Meds today",
          "sources": { "today": { "records": "reminder:", "when": "today", "where": { "$type": "care.item" } } },
          "small": { "vstack": [ { "text": "$today.open left" }, { "button": "Taken", "action": { "tick": "$today.next" } } ] } }
        """#)
        try store.set(sidekickId: "care-reminders", key: "widget:meds", value: widget)
        try store.set(sidekickId: "care-reminders", key: "reminder:pills", value: hourly)
        let now = octoberLA(13, 10)
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: "care-reminders", name: "Reminders")] }
        let publisher = SidekickWidgetPublisher(fileURL: folder.appending(path: "widgets.json"), store: store, sidekicks: listSidekicks,
                                                now: { now }, calendar: { buildCalendar }, reloadWidget: {},
                                                pendingActionsFileURL: folder.appending(path: "actions.json"))
        // At 10:00, the noon dose is ticked two hours early
        let taken = WidgetTapAction(kind: .tick, sidekickId: "care-reminders", key: "reminder:pills@1200", field: nil, amount: nil, valueJSON: nil,
                                    occurrence: octoberLA(13, 12))
        publisher.perform(taken)
        let item = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: "reminder:pills"))
        XCTAssertEqual(item["slotsDone"]?["12:00"], .string(ReminderRecord.formatDate(octoberLA(13, 12))))

        let filler = SidekickWidgetFiller(calendar: buildCalendar)
        let today = filler.sourceValues(description: widget, sidekickRecords: store.query(sidekickId: "care-reminders", keyPrefix: ""), at: now)["today"]
        var ids: [String] = []
        for todayItem in today?["items"]?.arrayValue ?? [] {
            ids.append(todayItem["id"]?.stringValue ?? "")
        }
        XCTAssertFalse(ids.contains("pills@1200"), "the dose ticked early is done for today: \(ids)")
        XCTAssertTrue(ids.contains("pills@1600"), "later doses stay: \(ids)")
        XCTAssertEqual(today?["done"], .number(1))
    }

    // MARK: Tiles in light and dark

    func testASymbolTileUsesTheManifestsDarkColourOrDerivesOne() {
        XCTAssertEqual(SymbolTileColors.backgroundHex(lightHex: "#FF9500", darkHex: "#B36800", isDark: false), "#FF9500")
        XCTAssertEqual(SymbolTileColors.backgroundHex(lightHex: "#FF9500", darkHex: "#B36800", isDark: true), "#B36800")
        let derived = SymbolTileColors.backgroundHex(lightHex: "#FF9500", darkHex: nil, isDark: true)
        XCTAssertEqual(derived, SidekickWidgetInk.darkFillHex(fromLight: "#FF9500"))
        XCTAssertLessThan(SidekickWidgetInk.luminance(derived)!, SidekickWidgetInk.luminance("#FF9500")!)
        XCTAssertEqual(SymbolTileColors.backgroundHex(lightHex: "#FF9500", darkHex: "night", isDark: true), derived, "a broken dark colour is derived")
    }

    func testTheCatalogsDarkColourReachesTheTile() throws {
        let body = #"""
        { "sidekicks": [
          { "id": "plants", "name": "Plants", "icon": { "symbol": "leaf", "background": "#9CAF88", "backgroundDark": "#5E6B52" }, "version": "1" },
          { "id": "notes", "name": "Notes", "icon": { "symbol": "note.text", "background": "#FFCC00" }, "version": "2" } ] }
        """#
        let listings = try RemoteSidekickDirectoryFetcher.listings(from: Data(body.utf8))
        XCTAssertEqual(listings[0].entry.backgroundDarkHex, "#5E6B52")
        XCTAssertNil(listings[1].entry.backgroundDarkHex, "a manifest from before build 22")
        XCTAssertEqual(SidekickIconContent.content(for: listings[0].entry), .symbol(name: "leaf", backgroundHex: "#9CAF88", darkBackgroundHex: "#5E6B52"))
    }

    func testAnEntrySavedByAnOlderBuildStillReads() throws {
        let olderJSON = ##"{ "id": "notes", "name": "Notes", "symbolName": "note.text", "backgroundHex": "#FFCC00", "version": "2" }"##
        let older = try JSONDecoder().decode(SidekickEntry.self, from: Data(olderJSON.utf8))
        XCTAssertNil(older.backgroundDarkHex)
        let entry = SidekickEntry(id: "plants", name: "Plants", symbolName: "leaf", backgroundHex: "#9CAF88", version: "1", backgroundDarkHex: "#5E6B52")
        let roundTrip = try JSONDecoder().decode(SidekickEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(roundTrip, entry)
    }

    func testEveryDrawnArtworkHasADarkPalette() {
        let remindersLight = RemindersListArtwork.colors(isDark: false)
        let remindersDark = RemindersListArtwork.colors(isDark: true)
        XCTAssertEqual(remindersLight.tile, "#FFFFFF")
        XCTAssertLessThan(SidekickWidgetInk.luminance(remindersDark.tile)!, 0.05, "the Reminders tile is dark at night (it stayed white)")
        XCTAssertGreaterThan(SidekickWidgetInk.contrast(remindersDark.row, remindersDark.tile), 4.5, "its rows read on it")
        let waterDark = WaterGlassArtwork.colors(isDark: true)
        XCTAssertEqual(waterDark.sand, "#0E1A1E")
        XCTAssertGreaterThan(SidekickWidgetInk.contrast(waterDark.ink, waterDark.sand), 4.5)
        XCTAssertEqual(WaterGlassArtwork.colors(isDark: false).sand, WaterGlassArtwork.sandHex)
        XCTAssertLessThan(SidekickWidgetInk.luminance(CareUrgencyArtwork.background(isDark: true))!, 0.05)
        XCTAssertEqual(CareUrgencyArtwork.background(isDark: false), CareUrgencyArtwork.backgroundHex)
    }

    // MARK: Drawn

    private func render<Content: View>(_ content: Content, colorScheme: ColorScheme) -> UIImage? {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, colorScheme))
        renderer.scale = 2
        // Drawn twice, the first one thrown away (a first drawing can come back blank on a new simulator)
        _ = renderer.uiImage
        return renderer.uiImage
    }

    private func pixelHex(of image: UIImage, atX x: CGFloat, y: CGFloat) -> String? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let pixelX = x * image.scale
        let pixelY = CGFloat(cgImage.height) - y * image.scale - 1
        context.draw(cgImage, in: CGRect(x: -pixelX, y: -pixelY, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    private func assertNear(_ actualHex: String?, _ expectedHex: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let actualHex, let actual = SidekickColor.rgbComponents(fromHex: actualHex), let expected = SidekickColor.rgbComponents(fromHex: expectedHex) else {
            return XCTFail("no pixel: \(message)", file: file, line: line)
        }
        let channels = [(actual.red, expected.red), (actual.green, expected.green), (actual.blue, expected.blue)]
        for (actualValue, expectedValue) in channels {
            XCTAssertLessThanOrEqual(abs(actualValue - expectedValue) * 255, 4, "\(message): \(actualHex) is not \(expectedHex)", file: file, line: line)
        }
    }

    func testTheTilesAreDrawnInEachAppearance() throws {
        let tiles: [(SidekickIconContent, String, String)] = [
            (.artwork(.remindersList), RemindersListArtwork.tileHex, RemindersListArtwork.darkTileHex),
            (.artwork(.waterGlass), WaterGlassArtwork.sandHex, WaterGlassArtwork.darkSandHex),
            (.artwork(.careUrgencyTiles), CareUrgencyArtwork.backgroundHex, CareUrgencyArtwork.darkBackgroundHex),
            (.symbol(name: "leaf", backgroundHex: "#9CAF88", darkBackgroundHex: "#5E6B52"), "#9CAF88", "#5E6B52"),
        ]
        for (content, lightHex, darkHex) in tiles {
            let view = SidekickIconView(content: content, size: 100)
            let lightImage = try XCTUnwrap(render(view, colorScheme: .light))
            let darkImage = try XCTUnwrap(render(view, colorScheme: .dark))
            // Top middle: the tile's own background in every artwork, inside the rounded corners
            assertNear(pixelHex(of: lightImage, atX: 50, y: 6), lightHex, "\(content) light")
            assertNear(pixelHex(of: darkImage, atX: 50, y: 6), darkHex, "\(content) dark")
        }
    }
}
