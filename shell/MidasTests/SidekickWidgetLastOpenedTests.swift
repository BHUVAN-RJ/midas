import XCTest
@testable import Midas

// A new Sidekick widget shows the last Sidekick opened (founder, 2026-10-25: "Our widget shows the
// [last] sidekick open. That is a good change"; built 2026-10-26). Opening a Sidekick that has a
// widget records it; a newly added widget picks it, and a widget with nothing picked shows it.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let todayWidget = json(#"""
{ "name": "Water today",
  "sources": { "day": { "record": "water:today" } },
  "small": { "vstack": [ { "text": "$day.ml" } ] } }
"""#)

private let medsWidget = json(#"""
{ "name": "Meds today",
  "small": { "vstack": [ { "text": "Meds" } ] } }
"""#)

@MainActor
final class SidekickWidgetLastOpenedTests: XCTestCase {
    private var directory: URL!
    private var store: LocalRecordStore!
    private var widgetsFileURL: URL!
    private var lastOpenedFileURL: URL!
    private var reloadCount = 0
    private let listedSidekicks: [(id: String, name: String)] = [(id: "care-reminders", name: "Care"), (id: "hydration", name: "Water"), (id: "notes", name: "Notes")]
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "last-opened-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        widgetsFileURL = directory.appending(path: "widgets.json")
        lastOpenedFileURL = directory.appending(path: "last-opened.json")
        reloadCount = 0
        try store.set(sidekickId: "care-reminders", key: "widget:meds", value: medsWidget)
        try store.set(sidekickId: "hydration", key: "widget:today", value: todayWidget)
        try store.set(sidekickId: "hydration", key: "water:today", value: json(#"{ "ml": 750 }"#))
        try store.set(sidekickId: "notes", key: "note:1", value: json(#"{ "text": "hi" }"#))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePublisher() -> SidekickWidgetPublisher {
        let fixedNow = now
        let sidekicks = listedSidekicks
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { sidekicks }
        let countReload: @MainActor () -> Void = { [unowned self] in self.reloadCount += 1 }
        return SidekickWidgetPublisher(fileURL: widgetsFileURL, store: store, sidekicks: listSidekicks,
                                       now: { fixedNow }, calendar: { calendarPT }, reloadWidget: countReload,
                                       lastOpenedFileURL: lastOpenedFileURL)
    }

    private func screenWithNothingPicked() -> SidekickWidgetScreen {
        return SidekickWidgetLayout.screen(file: SharedSidekickWidgets.read(from: widgetsFileURL), sidekickId: nil, widgetChoiceId: nil,
                                           size: .small, at: now, lastOpenedSidekickId: LastOpenedSidekickFile.read(from: lastOpenedFileURL))
    }

    private func shownSidekickId(_ screen: SidekickWidgetScreen) -> String? {
        guard case .piece(_, let sidekickId, _) = screen else {
            return nil
        }
        return sidekickId
    }

    func testOpeningASidekickWithAWidgetMakesItTheOneANewWidgetShows() async {
        let publisher = makePublisher()
        publisher.publish()
        XCTAssertEqual(screenWithNothingPicked(), .pickSidekick, "nothing opened yet: the person picks")
        publisher.noteOpened(sidekickId: "hydration")
        XCTAssertEqual(LastOpenedSidekickFile.read(from: lastOpenedFileURL), "hydration")
        XCTAssertEqual(shownSidekickId(screenWithNothingPicked()), "hydration")
        let query = WidgetSidekickQuery(fileURL: widgetsFileURL, lastOpenedFileURL: lastOpenedFileURL)
        let defaultSidekick = await query.defaultResult()
        XCTAssertEqual(defaultSidekick?.id, "hydration")
        XCTAssertEqual(defaultSidekick?.name, "Water")
    }

    func testTheLastOneOpenedWins() async {
        let publisher = makePublisher()
        publisher.publish()
        publisher.noteOpened(sidekickId: "hydration")
        publisher.noteOpened(sidekickId: "care-reminders")
        XCTAssertEqual(shownSidekickId(screenWithNothingPicked()), "care-reminders")
        let defaultSidekick = await WidgetSidekickQuery(fileURL: widgetsFileURL, lastOpenedFileURL: lastOpenedFileURL).defaultResult()
        XCTAssertEqual(defaultSidekick?.id, "care-reminders")
    }

    func testASidekickWithoutAWidgetLeavesTheLastOneInPlace() {
        let publisher = makePublisher()
        publisher.publish()
        publisher.noteOpened(sidekickId: "hydration")
        let reloadsBefore = reloadCount
        publisher.noteOpened(sidekickId: "notes")
        XCTAssertEqual(LastOpenedSidekickFile.read(from: lastOpenedFileURL), "hydration")
        XCTAssertEqual(reloadCount, reloadsBefore, "nothing changed, no redraw")
    }

    func testOpeningRedrawsTheWidgetOnlyWhenTheChoiceChanges() {
        let publisher = makePublisher()
        publisher.publish()
        let reloadsBefore = reloadCount
        publisher.noteOpened(sidekickId: "hydration")
        XCTAssertEqual(reloadCount, reloadsBefore + 1)
        publisher.noteOpened(sidekickId: "hydration")
        XCTAssertEqual(reloadCount, reloadsBefore + 1)
    }

    func testAPickedSidekickIsNeverOverriddenByTheLastOpened() {
        let publisher = makePublisher()
        publisher.publish()
        publisher.noteOpened(sidekickId: "hydration")
        let screen = SidekickWidgetLayout.screen(file: SharedSidekickWidgets.read(from: widgetsFileURL), sidekickId: "care-reminders",
                                                 widgetChoiceId: nil, size: .small, at: now, lastOpenedSidekickId: "hydration")
        XCTAssertEqual(shownSidekickId(screen), "care-reminders")
    }

    func testALastOpenedSidekickThatLostItsWidgetFallsBackToPicking() async {
        LastOpenedSidekickFile.write("gone", to: lastOpenedFileURL)
        makePublisher().publish()
        XCTAssertEqual(screenWithNothingPicked(), .pickSidekick)
        let defaultSidekick = await WidgetSidekickQuery(fileURL: widgetsFileURL, lastOpenedFileURL: lastOpenedFileURL).defaultResult()
        XCTAssertNil(defaultSidekick)
    }

    func testTheAppRecordsEveryOpenAndTheWidgetReadsIt() throws {
        let shellRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appSource = try String(contentsOf: shellRoot.appending(path: "Midas/MidasApp.swift"), encoding: .utf8)
        let widgetSource = try String(contentsOf: shellRoot.appending(path: "MidasWidgets/SidekickWidget.swift"), encoding: .utf8)
        XCTAssertTrue(appSource.contains("sidekickWidgets.noteOpened(sidekickId: sidekick.id)"))
        XCTAssertTrue(widgetSource.contains("lastOpenedSidekickId: lastOpenedId"))
    }
}
