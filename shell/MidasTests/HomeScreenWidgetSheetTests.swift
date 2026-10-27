import SwiftUI
import UIKit
import XCTest
@testable import Midas

// "Add to Home Screen" (founder, 2026-10-25/26: one sheet for every widget, demo B in Midas style,
// docs/mockups/widget-howto-demo-2026-10-25.html; "add this to water hydration"). A Sidekick writes
// request:<id> { kind: "home-screen.widget", widget: "sidekick" }; the shell shows the sheet for that
// Sidekick, with its own small widget, and marks the request done. Checked: the dispatch, the widget
// the sheet picks and its plain stand-in, the mockup's timing, Reduce Motion's list, the step 4
// square, and the drawing (saved as PNGs when MIDAS_SHEET_RENDER_DIR is set).

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

// Water's Tide widget, small and medium, as its page writes it
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
               { "button": "+250 ml", "action": { "increment": "water:{today}", "field": "ml", "by": 250 } } ] } },
  "medium": { "fill": { "value": "$water.ml", "of": "$settings.goalMl" },
              "color": { "light": "#9CCFD3", "dark": "#2E6E77" }, "edge": "wave",
              "content": { "vstack": [ { "text": "$water.ml", "format": "l", "style": "number" } ] } } }
"""#)

private let remindersWidget = json(#"{ "name": "Today", "small": { "text": "Reminders", "style": "headline" } }"#)

private let waterEntry = SidekickEntry(id: "hydration", name: "Water", symbolName: "drop.fill", backgroundHex: "#30D5C8", version: "1")
private let remindersEntry = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FFBF00", version: "1")
private let careEntry = SidekickEntry(id: "care-reminders", name: "Care", symbolName: "heart", backgroundHex: "#C41E3A", version: "1")

private let seaHex = "#9CCFD3"
private let nightSeaHex = "#2E6E77"

@MainActor
final class HomeScreenWidgetSheetTests: XCTestCase {
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "home-screen-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private struct Shell {
        let store: LocalRecordStore
        let channel: SidekickStoreChannel
        let homeScreen: HomeScreenWidgetCenter
        let remindersImport: AppleRemindersImportCenter
    }

    private func makeShell() -> Shell {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let channel = SidekickStoreChannel(store: store)
        let homeScreen = HomeScreenWidgetCenter(store: store)
        let remindersImport = AppleRemindersImportCenter(store: store, source: EventKitRemindersSource())
        let dispatch = ShellRequestDispatch(homeScreen: homeScreen, remindersImport: remindersImport)
        channel.requestObserver = dispatch.handleRequestWritten
        return Shell(store: store, channel: channel, homeScreen: homeScreen, remindersImport: remindersImport)
    }

    private func body(_ text: String) -> Data {
        return Data(text.utf8)
    }

    private func setRequestBody(key: String, fields: String) -> Data {
        return body(#"{ "op": "set", "key": "\#(key)", "value": { "status": "pending", "createdAt": "2026-10-26T20:00:00.000Z", \#(fields) } }"#)
    }

    // MARK: The request

    func testTheRequestShowsTheSheetForTheAskingSidekickAndIsMarkedDone() {
        let shell = makeShell()

        let reply = shell.channel.handle(sidekickId: "hydration", requestBody: setRequestBody(key: "request:h1", fields: #""kind": "home-screen.widget", "widget": "sidekick""#))

        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertEqual(shell.homeScreen.shownRequest, HomeScreenWidgetRequest(sidekickId: "hydration", requestKey: "request:h1", variant: .sidekick))
        let stored = shell.store.get(sidekickId: "hydration", key: "request:h1")
        XCTAssertEqual(stored?["status"]?.stringValue, "done")
        XCTAssertNotNil(stored?["finishedAt"]?.stringValue)
        XCTAssertEqual(stored?["kind"]?.stringValue, ShellRequests.homeScreenWidgetKind, "what the Sidekick wrote stays")
        XCTAssertNil(shell.remindersImport.shownRequest, "not the import sheet")
    }

    func testAnyOtherSidekickCanAskWithoutAShellChange() {
        let shell = makeShell()

        _ = shell.channel.handle(sidekickId: "care-reminders", requestBody: setRequestBody(key: "request:c9", fields: #""kind": "home-screen.widget""#))

        XCTAssertEqual(shell.homeScreen.shownRequest, HomeScreenWidgetRequest(sidekickId: "care-reminders", requestKey: "request:c9", variant: .sidekick))
        XCTAssertEqual(shell.store.get(sidekickId: "care-reminders", key: "request:c9")?["status"]?.stringValue, "done")
    }

    func testTheFolderVariantIsTheSameSheet() {
        let shell = makeShell()

        _ = shell.channel.handle(sidekickId: "hydration", requestBody: setRequestBody(key: "request:f1", fields: #""kind": "home-screen.widget", "widget": "folder""#))

        XCTAssertEqual(shell.homeScreen.shownRequest?.variant, .folder)
    }

    func testAnUnknownWidgetIsMarkedFailedAndShowsNothing() {
        let shell = makeShell()

        _ = shell.channel.handle(sidekickId: "hydration", requestBody: setRequestBody(key: "request:x1", fields: #""kind": "home-screen.widget", "widget": "lock-screen""#))

        XCTAssertNil(shell.homeScreen.shownRequest)
        let stored = shell.store.get(sidekickId: "hydration", key: "request:x1")
        XCTAssertEqual(stored?["status"]?.stringValue, "failed")
        XCTAssertEqual(stored?["error"]?.stringValue, "unknown widget")
    }

    func testAnImportRequestStillReachesTheImport() {
        let shell = makeShell()

        _ = shell.channel.handle(sidekickId: "reminders", requestBody: setRequestBody(key: "request:r1", fields: #""kind": "import.apple-reminders""#))

        XCTAssertEqual(shell.remindersImport.shownRequest, AppleRemindersImportRequest(sidekickId: "reminders", requestKey: "request:r1"))
        XCTAssertNil(shell.homeScreen.shownRequest)
    }

    func testDoneClosesTheSheet() {
        let shell = makeShell()
        _ = shell.channel.handle(sidekickId: "hydration", requestBody: setRequestBody(key: "request:h1", fields: #""kind": "home-screen.widget""#))

        shell.homeScreen.dismiss()

        XCTAssertNil(shell.homeScreen.shownRequest)
    }

    func testThePageCanAskWhetherThisBuildHasTheSheet() {
        let shell = makeShell()

        let reply = shell.channel.handle(sidekickId: "hydration", requestBody: body(#"{ "op": "shell" }"#))

        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertEqual(reply.body["ok"], .bool(true))
        var kinds: [String] = []
        for kind in reply.body["requests"]?.arrayValue ?? [] {
            kinds.append(kind.stringValue ?? "")
        }
        XCTAssertEqual(kinds, ["import.apple-reminders", "home-screen.widget"])
    }

    // MARK: The widget it shows

    private func filledTide(ml: Int) -> FilledSidekickWidget {
        let records = [
            LocalRecord(sidekickId: "hydration", key: "widget:today", value: tideWidget),
            LocalRecord(sidekickId: "hydration", key: "settings:main", value: json(#"{ "goalMl": 2500 }"#)),
            LocalRecord(sidekickId: "hydration", key: "water:2026-10-25", value: json(#"{ "ml": \#(ml) }"#)),
        ]
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        return filler.fill(sidekickId: "hydration", sidekickName: "Water", record: records[0], sidekickRecords: records, now: octoberPT(25, 15))
    }

    private func filledReminders() -> FilledSidekickWidget {
        let record = LocalRecord(sidekickId: "reminders", key: "widget:today", value: remindersWidget)
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        return filler.fill(sidekickId: "reminders", sidekickName: "Reminders", record: record, sidekickRecords: [record], now: octoberPT(25, 15))
    }

    private func sidekickRequest(_ sidekickId: String) -> HomeScreenWidgetRequest {
        return HomeScreenWidgetRequest(sidekickId: sidekickId, requestKey: "request:t1", variant: .sidekick)
    }

    private func pieceSidekickId(_ look: HomeScreenWidgetLook) -> String? {
        guard case .filled(let screen) = look, case .piece(_, let sidekickId, _) = screen else {
            return nil
        }
        return sidekickId
    }

    func testTheSheetDrawsTheAskingSidekicksOwnWidget() {
        let file = SharedSidekickWidgets(widgets: [filledReminders(), filledTide(ml: 1250)], savedAt: octoberPT(25, 15))
        let entries = [remindersEntry, waterEntry]

        let waterContent = HomeScreenDemoContent.make(request: sidekickRequest("hydration"), file: file, entries: entries, now: octoberPT(25, 15))
        let remindersContent = HomeScreenDemoContent.make(request: sidekickRequest("reminders"), file: file, entries: entries, now: octoberPT(25, 15))

        XCTAssertEqual(pieceSidekickId(waterContent.placedLook), "hydration")
        XCTAssertEqual(pieceSidekickId(remindersContent.placedLook), "reminders")
        // The Sidekicks folder is the first page (founder, 2026-10-27, docs/PRODUCT.md "Gallery
        // order"); the three Sidekick pages after it are the same widget at each size
        XCTAssertEqual(waterContent.galleryLooks.count, 4)
        guard case .folder = waterContent.galleryLooks[0] else {
            return XCTFail("the first page is the Sidekicks folder")
        }
        for pageIndex in 1...3 {
            XCTAssertEqual(pieceSidekickId(waterContent.galleryLooks[pageIndex]), "hydration", "page \(pageIndex)")
        }
        // The real description, filled: the small look's sea is the day's share of the goal
        guard case .filled(let screen) = waterContent.placedLook, case .piece(let piece, _, _) = screen else {
            return XCTFail("no piece")
        }
        XCTAssertEqual(SidekickWidgetSurface.edgeFill(of: piece)?.fraction, 0.5)
    }

    func testWithoutAFilledWidgetThePlainCardInTheTileColour() {
        let onlyReminders = SharedSidekickWidgets(widgets: [filledReminders()], savedAt: octoberPT(25, 15))
        let entries = [remindersEntry, waterEntry]

        let noWidget = HomeScreenDemoContent.make(request: sidekickRequest("hydration"), file: onlyReminders, entries: entries, now: octoberPT(25, 15))
        let noFile = HomeScreenDemoContent.make(request: sidekickRequest("hydration"), file: nil, entries: entries, now: octoberPT(25, 15))

        XCTAssertEqual(noWidget.placedLook, .plain(name: "Water", tileHex: "#30D5C8"))
        XCTAssertEqual(noFile.placedLook, .plain(name: "Water", tileHex: "#30D5C8"))
        // Page 0 is the Sidekicks folder (founder, 2026-10-27); the Sidekick's small page is 1
        XCTAssertEqual(noFile.galleryLooks[1], .plain(name: "Water", tileHex: "#30D5C8"))
    }

    func testAWidgetThatCouldNotBeFilledAlsoGetsThePlainCard() {
        let broken = FilledSidekickWidget(sidekickId: "hydration", sidekickName: "Water", widgetId: "today", name: "Water today", tintHex: nil, isUsable: false, looks: [])
        let file = SharedSidekickWidgets(widgets: [broken], savedAt: octoberPT(25, 15))

        let content = HomeScreenDemoContent.make(request: sidekickRequest("hydration"), file: file, entries: [waterEntry], now: octoberPT(25, 15))

        XCTAssertEqual(content.placedLook, .plain(name: "Water", tileHex: "#30D5C8"))
    }

    func testTheFolderVariantLandsTheSidekicksFolder() {
        let request = HomeScreenWidgetRequest(sidekickId: "hydration", requestKey: "request:t1", variant: .folder)

        let content = HomeScreenDemoContent.make(request: request, file: nil, entries: [waterEntry, remindersEntry, careEntry], now: octoberPT(25, 15))

        XCTAssertEqual(content.placedLook, .folder(tileHexes: ["#30D5C8", "#FFBF00", "#C41E3A", "#30D5C8"]))
    }

    // MARK: Home Screen colours

    func testTheHomeScreenUsesThePersonsTileColours() {
        let palette = HomeScreenDemoColors.palette(personalHexes: ["#30D5C8", "#ffbf00", "#C41E3A", "#30D5C8"])
        XCTAssertEqual(palette, ["#30D5C8", "#FFBF00", "#C41E3A"])
        let icons = HomeScreenDemoColors.iconHexes(palette: palette)
        XCTAssertEqual(icons.count, 12)
        XCTAssertEqual(icons[HomeScreenDemoColors.midasIconIndex], "", "the written Midas icon's slot")
        for (index, hex) in icons.enumerated() where index != HomeScreenDemoColors.midasIconIndex {
            XCTAssertTrue(palette.contains(hex), "icon \(index): \(hex)")
        }
        XCTAssertNotEqual(icons[0], icons[1], "neighbours differ")
    }

    func testFewerThanThreeOwnColoursFallBackToTheEight() {
        XCTAssertEqual(HomeScreenDemoColors.palette(personalHexes: ["#30D5C8", "#30D5C8"]), HomeScreenDemoColors.tilePalette)
        XCTAssertEqual(HomeScreenDemoColors.palette(personalHexes: []), HomeScreenDemoColors.tilePalette)
        // The mockup's order: every third of the eight
        let icons = HomeScreenDemoColors.iconHexes(palette: HomeScreenDemoColors.tilePalette)
        XCTAssertEqual(Array(icons.prefix(3)), ["#30D5C8", "#FF6347", "#FFE600"])
        XCTAssertEqual(HomeScreenDemoColors.dockHexes(palette: HomeScreenDemoColors.tilePalette), ["#FFBF00", "#FF6347", "#2E2E2E", "#C41E3A"])
    }

    // MARK: Timing (the mockup's buildTimeline)

    func testTheSidekickTimelineMatchesTheMockup() {
        let timeline = HomeScreenDemoTimeline(variant: .sidekick)

        XCTAssertEqual(timeline.pagesToPass, 1, "Sidekicks (the folder) is first: one swipe")
        XCTAssertEqual(timeline.jiggleStart, 1300)
        XCTAssertEqual(timeline.menuOpen, 2600)
        XCTAssertEqual(timeline.menuTap, 3300)
        XCTAssertEqual(timeline.galleryUp, 3700)
        XCTAssertEqual(timeline.midasTap, 5000)
        XCTAssertEqual(timeline.pickUp, 5500)
        XCTAssertEqual(timeline.swipeStart, 6300)
        XCTAssertEqual(timeline.swipeEnd, 7100)
        XCTAssertEqual(timeline.spotlight, 7100)
        XCTAssertEqual(timeline.addTap, 8800)
        XCTAssertEqual(timeline.placed, 9500)
        XCTAssertEqual(timeline.jiggleEnd, 11000)
        XCTAssertEqual(timeline.length, 12200)
        XCTAssertEqual(timeline.steps, [
            HomeScreenDemoStep(fromMs: 0, caption: "Touch and hold the Home Screen"),
            HomeScreenDemoStep(fromMs: 2200, caption: "Tap Edit, then Add Widget"),
            HomeScreenDemoStep(fromMs: 4300, caption: "Tap Midas"),
            HomeScreenDemoStep(fromMs: 6000, caption: "Swipe to Sidekick"),
            HomeScreenDemoStep(fromMs: 7600, caption: "Tap Add Widget"),
        ])
    }

    func testTheFolderTimelineHasNoSwipe() {
        let timeline = HomeScreenDemoTimeline(variant: .folder)

        XCTAssertEqual(timeline.pagesToPass, 0, "Sidekicks (the folder) is the first page: no swipe")
        XCTAssertEqual(timeline.swipeEnd, 6300)
        XCTAssertEqual(timeline.spotlight, 6000)
        XCTAssertEqual(timeline.addTap, 7700)
        XCTAssertEqual(timeline.placed, 8400)
        XCTAssertEqual(timeline.jiggleEnd, 9900)
        XCTAssertEqual(timeline.length, 11100)
        XCTAssertEqual(timeline.steps.count, 4)
        XCTAssertEqual(timeline.steps[3], HomeScreenDemoStep(fromMs: 6500, caption: "Tap Add Widget"))
        for step in timeline.steps {
            XCTAssertFalse(step.caption.hasPrefix("Swipe to"), step.caption)
        }
    }

    func testTheLastCaptionIsOnYourHomeScreenWithNoPickStep() {
        let timeline = HomeScreenDemoTimeline(variant: .sidekick)

        XCTAssertEqual(timeline.caption(at: 9000), "Tap Add Widget")
        XCTAssertEqual(timeline.caption(at: 9800), "Tap Add Widget")
        XCTAssertEqual(timeline.caption(at: 9801), "On your Home Screen")
        XCTAssertEqual(timeline.caption(at: 12000), "On your Home Screen")
        XCTAssertEqual(timeline.stepIndex(at: 12000), 4, "the dots stay on the last step")
        for step in timeline.steps {
            XCTAssertFalse(step.caption.lowercased().contains("pick"), step.caption)
        }
    }

    func testTheEasingNeverOvershoots() {
        XCTAssertEqual(HomeScreenDemoEasing.progress(0, from: 100, to: 200), 0)
        XCTAssertEqual(HomeScreenDemoEasing.progress(150, from: 100, to: 200), 0.5)
        XCTAssertEqual(HomeScreenDemoEasing.progress(125, from: 100, to: 200), 0.15625)
        XCTAssertEqual(HomeScreenDemoEasing.progress(300, from: 100, to: 200), 1)
    }

    // MARK: Reduce Motion

    func testReduceMotionShowsTheFiveStepsAsAList() {
        let still = HomeScreenDemoPresentation.choose(variant: .sidekick, reduceMotion: true)
        let moving = HomeScreenDemoPresentation.choose(variant: .sidekick, reduceMotion: false)

        XCTAssertEqual(still, .stillList(["Touch and hold the Home Screen", "Tap Edit, then Add Widget", "Tap Midas", "Swipe to Sidekick", "Tap Add Widget"]))
        XCTAssertEqual(moving, .animated(HomeScreenDemoTimeline(variant: .sidekick)))
    }

    func testTheStillListDrawsNumberedSteps() throws {
        let list = HomeScreenDemoStillList(captions: ["One", "Two", "Three", "Four"], ink: HomeScreenDemoInk(colorScheme: .light))
            .frame(width: 346)
        let image = try XCTUnwrap(render(list, colorScheme: .light))
        // Four rows of 30 points with 18 between, under 28 of top space
        XCTAssertEqual(image.size.height, 28 + 4 * 30 + 3 * 18, accuracy: 1)
        // The first number's ink disc
        assertClose(hexColor(of: image, atX: 8, y: 28 + 15), "#111111", "the number disc")
    }

    // MARK: Step 4: the placed widget

    func testThePlacedWidgetCoversExactlyTheTwoByTwoSquare() {
        let grid = HomeScreenDemoGrid(width: 346)
        let first = grid.iconFrame(0)
        let second = grid.iconFrame(1)
        let below = grid.iconFrame(4)
        let diagonal = grid.iconFrame(5)

        let columnGap = second.minX - first.maxX
        let rowGap = below.minY - first.maxY
        XCTAssertGreaterThan(columnGap, 0)
        XCTAssertEqual(rowGap, columnGap, accuracy: 0.001, "rows spaced like columns")
        let placed = grid.placedFrame
        XCTAssertEqual(placed.minX, first.minX, accuracy: 0.001)
        XCTAssertEqual(placed.minY, first.minY, accuracy: 0.001)
        XCTAssertEqual(placed.maxX, diagonal.maxX, accuracy: 0.001)
        XCTAssertEqual(placed.maxY, diagonal.maxY, accuracy: 0.001)
        XCTAssertEqual(placed.width, placed.height, accuracy: 0.001, "a square")
    }

    func testTheGridHasThreeRowsClearOfTheDock() {
        let grid = HomeScreenDemoGrid(width: 346)
        XCTAssertEqual(HomeScreenDemoColors.iconCount, HomeScreenDemoGrid.columns * HomeScreenDemoGrid.rows)
        XCTAssertEqual(HomeScreenDemoGrid.rows, 3)
        let lastRow = grid.iconFrame(HomeScreenDemoColors.iconCount - 1)
        let dockTop = HomeScreenDemoFrame.stageHeight - 10 - 76
        XCTAssertLessThan(lastRow.maxY, dockTop)
    }

    // MARK: Drawing

    private func render<Content: View>(_ content: Content, colorScheme: ColorScheme) -> UIImage? {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        // Drawn twice, the first one thrown away (a first drawing once came back blank)
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
            XCTAssertLessThanOrEqual(abs(actualValue - expectedValue), 8, "\(message): \(actualHex) is not \(expectedHex)", file: file, line: line)
        }
    }

    private func waterFrame(atMs timeMs: Double, colorScheme: ColorScheme) -> some View {
        let file = SharedSidekickWidgets(widgets: [filledTide(ml: 1250)], savedAt: octoberPT(25, 15))
        let content = HomeScreenDemoContent.make(request: sidekickRequest("hydration"), file: file, entries: [waterEntry, remindersEntry, careEntry], now: octoberPT(25, 15))
        let ink = HomeScreenDemoInk(colorScheme: colorScheme)
        return HomeScreenDemoFrame(content: content, timeline: HomeScreenDemoTimeline(variant: .sidekick), timeMs: timeMs, ink: ink)
            .frame(width: 346)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(ink.paper)
    }

    /// Step 4 with Water's widget landed, light and dark; saved only when asked for.
    func testRenderStepFourWithWatersWidget() throws {
        let grid = HomeScreenDemoGrid(width: 346)
        let placed = grid.placedFrame
        for (colorScheme, modeName, seaColor) in [(ColorScheme.light, "light", seaHex), (ColorScheme.dark, "dark", nightSeaHex)] {
            let image = try XCTUnwrap(render(waterFrame(atMs: 10400, colorScheme: colorScheme), colorScheme: colorScheme))
            XCTAssertEqual(image.size.width, 386)
            // The stage starts 14 points down, 20 in. Near the widget's bottom right: the sea of a
            // half-full day, so the real Tide widget is drawn where the four icons were.
            let seaPoint = CGPoint(x: 20 + placed.maxX - 24, y: 14 + placed.maxY - 24)
            assertClose(hexColor(of: image, atX: seaPoint.x, y: seaPoint.y), seaColor, "\(modeName) sea in the placed widget")
            // The wall beside the widget, between it and the next icon column
            let wallPoint = CGPoint(x: 20 + placed.maxX + 12, y: 14 + placed.midY)
            let wallHex = colorScheme == .dark ? "#1C1C1C" : "#E9E6DF"
            assertClose(hexColor(of: image, atX: wallPoint.x, y: wallPoint.y), wallHex, "\(modeName) wall")
            guard let renderDirectory = ProcessInfo.processInfo.environment["MIDAS_SHEET_RENDER_DIR"] else {
                continue
            }
            let pngData = try XCTUnwrap(image.pngData())
            let fileURL = URL(filePath: renderDirectory).appending(path: "home-screen-sheet-step4-\(modeName)-2026-10-26.png")
            try pngData.write(to: fileURL)
        }
    }

    func testBeforeTheWidgetLandsTheIconsAreThere() throws {
        let grid = HomeScreenDemoGrid(width: 346)
        let firstIcon = grid.iconFrame(0)
        // At 1 s nothing has moved: icon 0 is drawn in the first of the eight tile colours the
        // person has (Water's Turquoise), and the sea is nowhere
        let image = try XCTUnwrap(render(waterFrame(atMs: 1000, colorScheme: .light), colorScheme: .light))
        assertClose(hexColor(of: image, atX: 20 + firstIcon.midX, y: 14 + firstIcon.midY), "#30D5C8", "icon 0")
    }
}
