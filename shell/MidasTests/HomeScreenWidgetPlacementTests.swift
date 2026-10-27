import XCTest
@testable import Midas

// "Is my widget on the Home Screen?" (founder, 2026-10-27: Water's Widget button "should only be
// visible until the widget is added"; docs/WIDGETS.md, "Add to Home Screen"). A page asks
// { op: "widget-placed" }; the shell reads WidgetKit's placed Sidekick widgets (behind
// PlacedSidekickWidgetsSource) and answers { placed }. Checked: which placed widgets count for a
// Sidekick, the last-opened rule for a widget with nothing picked, and the store's answer.

private struct ListedPlacedWidgets: PlacedSidekickWidgetsSource {
    let widgets: [PlacedSidekickWidget]

    func placedSidekickWidgets() async -> [PlacedSidekickWidget] {
        return widgets
    }
}

private let pickedWater = PlacedSidekickWidget(pickedSidekickId: "hydration", pickedWidgetChoiceId: nil)
private let pickedWaterWidgetOnly = PlacedSidekickWidget(pickedSidekickId: nil, pickedWidgetChoiceId: "hydration/today")
private let pickedReminders = PlacedSidekickWidget(pickedSidekickId: "reminders", pickedWidgetChoiceId: "reminders/today")
private let pickedNothing = PlacedSidekickWidget(pickedSidekickId: nil, pickedWidgetChoiceId: nil)

@MainActor
final class HomeScreenWidgetPlacementTests: XCTestCase {
    private var lastOpenedFileURL: URL!
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        lastOpenedFileURL = FileManager.default.temporaryDirectory.appending(path: "last-opened-\(UUID().uuidString).json")
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "placement-store-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: lastOpenedFileURL)
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func placement(_ widgets: [PlacedSidekickWidget]) -> HomeScreenWidgetPlacement {
        return HomeScreenWidgetPlacement(source: ListedPlacedWidgets(widgets: widgets), lastOpenedFileURL: lastOpenedFileURL)
    }

    // MARK: Which widgets count

    func testAWidgetThatPicksThisSidekickCounts() {
        XCTAssertTrue(HomeScreenWidgetPlacement.isPlaced(sidekickId: "hydration", among: [pickedReminders, pickedWater], lastOpenedSidekickId: nil))
        XCTAssertFalse(HomeScreenWidgetPlacement.isPlaced(sidekickId: "care-reminders", among: [pickedReminders, pickedWater], lastOpenedSidekickId: nil))
    }

    func testAWidgetThatPicksOnlyOneOfItsWidgetsCounts() {
        XCTAssertTrue(HomeScreenWidgetPlacement.isPlaced(sidekickId: "hydration", among: [pickedWaterWidgetOnly], lastOpenedSidekickId: "reminders"))
        XCTAssertFalse(HomeScreenWidgetPlacement.isPlaced(sidekickId: "reminders", among: [pickedWaterWidgetOnly], lastOpenedSidekickId: "reminders"),
                       "a widget pick names its Sidekick; the last opened does not matter then")
    }

    func testAWidgetThatPicksNothingCountsForTheLastSidekickOpened() {
        XCTAssertTrue(HomeScreenWidgetPlacement.isPlaced(sidekickId: "hydration", among: [pickedNothing], lastOpenedSidekickId: "hydration"))
        XCTAssertFalse(HomeScreenWidgetPlacement.isPlaced(sidekickId: "hydration", among: [pickedNothing], lastOpenedSidekickId: "reminders"))
        XCTAssertFalse(HomeScreenWidgetPlacement.isPlaced(sidekickId: "hydration", among: [pickedNothing], lastOpenedSidekickId: nil))
    }

    func testAnotherSidekicksWidgetDoesNotCount() {
        XCTAssertFalse(HomeScreenWidgetPlacement.isPlaced(sidekickId: "hydration", among: [pickedReminders], lastOpenedSidekickId: "hydration"),
                       "Reminders is picked, so the widget shows Reminders even though Water was opened last")
    }

    func testNoWidgetsIsNotPlaced() {
        XCTAssertFalse(HomeScreenWidgetPlacement.isPlaced(sidekickId: "hydration", among: [], lastOpenedSidekickId: "hydration"))
    }

    func testTheShownSidekickOfEachPick() {
        XCTAssertEqual(HomeScreenWidgetPlacement.shownSidekickId(of: pickedWater, lastOpenedSidekickId: "reminders"), "hydration")
        XCTAssertEqual(HomeScreenWidgetPlacement.shownSidekickId(of: pickedWaterWidgetOnly, lastOpenedSidekickId: "reminders"), "hydration")
        XCTAssertEqual(HomeScreenWidgetPlacement.shownSidekickId(of: pickedNothing, lastOpenedSidekickId: "reminders"), "reminders")
        let brokenChoice = PlacedSidekickWidget(pickedSidekickId: nil, pickedWidgetChoiceId: "no-slash")
        XCTAssertNil(HomeScreenWidgetPlacement.shownSidekickId(of: brokenChoice, lastOpenedSidekickId: "no-slash"))
    }

    // MARK: Reading WidgetKit and the last-opened file

    func testIsPlacedReadsTheLastOpenedFile() async {
        let unpicked = placement([pickedNothing])
        let noFileAnswer = await unpicked.isPlaced(sidekickId: "hydration")
        XCTAssertFalse(noFileAnswer, "no last-opened file: a widget with nothing picked shows no Sidekick")

        LastOpenedSidekickFile.write("hydration", to: lastOpenedFileURL)
        let waterAnswer = await unpicked.isPlaced(sidekickId: "hydration")
        let remindersAnswer = await unpicked.isPlaced(sidekickId: "reminders")
        XCTAssertTrue(waterAnswer)
        XCTAssertFalse(remindersAnswer)
    }

    func testTheAppUsesWidgetKitAndTheSharedLastOpenedFile() {
        let live = HomeScreenWidgetPlacement.live()
        XCTAssertTrue(live.source is WidgetCenterPlacedSidekickWidgets)
        XCTAssertEqual(live.lastOpenedFileURL, SidekickWidgetShared.lastOpenedFileURL())
    }

    // MARK: The store's answer

    private func body(_ text: String) -> Data {
        return Data(text.utf8)
    }

    func testThePageAsksWidgetPlacedForItsOwnSidekick() async {
        let channel = SidekickStoreChannel(store: LocalRecordStore(fileURL: storeFileURL))
        channel.widgetPlacement = placement([pickedWater])

        let waterReply = await channel.handleAsync(sidekickId: "hydration", requestBody: body(#"{ "op": "widget-placed" }"#))
        let remindersReply = await channel.handleAsync(sidekickId: "reminders", requestBody: body(#"{ "op": "widget-placed" }"#))

        XCTAssertEqual(waterReply.statusCode, 200)
        XCTAssertEqual(waterReply.body, .object(["ok": .bool(true), "placed": .bool(true)]))
        XCTAssertEqual(remindersReply.body, .object(["ok": .bool(true), "placed": .bool(false)]))
    }

    func testWithoutAPlacementCheckTheAnswerIsNotPlaced() async {
        let channel = SidekickStoreChannel(store: LocalRecordStore(fileURL: storeFileURL))

        let reply = await channel.handleAsync(sidekickId: "hydration", requestBody: body(#"{ "op": "widget-placed" }"#))

        XCTAssertEqual(reply.body, .object(["ok": .bool(true), "placed": .bool(false)]))
    }

    func testOnlyWidgetPlacedWaitsAndEveryOtherOpIsAnsweredAsBefore() async {
        XCTAssertTrue(SidekickStoreChannel.needsAsyncReply(requestBody: body(#"{ "op": "widget-placed" }"#)))
        XCTAssertFalse(SidekickStoreChannel.needsAsyncReply(requestBody: body(#"{ "op": "shell" }"#)))
        XCTAssertFalse(SidekickStoreChannel.needsAsyncReply(requestBody: body(#"{ "op": "get", "key": "settings:main" }"#)))
        XCTAssertFalse(SidekickStoreChannel.needsAsyncReply(requestBody: body("not json")))

        let channel = SidekickStoreChannel(store: LocalRecordStore(fileURL: storeFileURL))
        channel.widgetPlacement = placement([pickedWater])
        let shellAtOnce = channel.handle(sidekickId: "hydration", requestBody: body(#"{ "op": "shell" }"#))
        let shellThroughAsync = await channel.handleAsync(sidekickId: "hydration", requestBody: body(#"{ "op": "shell" }"#))
        XCTAssertEqual(shellThroughAsync, shellAtOnce)
        let setReply = await channel.handleAsync(sidekickId: "hydration", requestBody: body(#"{ "op": "set", "key": "note:a", "value": { "text": "hi" } }"#))
        XCTAssertEqual(setReply.statusCode, 200)
        XCTAssertNotNil(channel.handle(sidekickId: "hydration", requestBody: body(#"{ "op": "get", "key": "note:a" }"#)).body["value"]?["text"])
    }
}
