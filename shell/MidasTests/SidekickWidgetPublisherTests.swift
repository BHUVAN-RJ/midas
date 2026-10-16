import XCTest
@testable import Midas

// The Sidekick widget, steps 4 and 5 (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html): the app fills every Sidekick's widgets into
// the App Group file and refills on record changes; taps change one record of the owning
// Sidekick; the settings sheet lists Sidekicks with widgets, then that Sidekick's widgets.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let medsWidget = json(#"""
{ "name": "Meds today",
  "sources": { "today": { "records": "reminder:", "when": "today" } },
  "small": { "vstack": [ { "text": "$today.open left" }, { "button": "Taken", "action": { "tick": "$today.next" } } ] } }
"""#)

private let waterWidget = json(#"""
{ "name": "Glasses",
  "sources": { "water": { "record": "water:today" } },
  "small": { "vstack": [ { "text": "$water.glasses" }, { "button": "+", "action": { "increment": "water:today", "field": "glasses" } } ] } }
"""#)

@MainActor
final class SidekickWidgetPublisherTests: XCTestCase {
    private var directory: URL!
    private var store: LocalRecordStore!
    private var widgetsFileURL: URL!
    private var actionsFileURL: URL!
    private var reloadCount = 0
    private var listedSidekicks: [(id: String, name: String)] = [(id: "care-reminders", name: "Reminders"), (id: "water", name: "Water")]
    private let now = octoberPT(13, 10)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "sidekick-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        widgetsFileURL = directory.appending(path: "widgets.json")
        actionsFileURL = directory.appending(path: "actions.json")
        reloadCount = 0
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePublisher(queue: Bool = true) -> SidekickWidgetPublisher {
        let fixedNow = now
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [unowned self] in self.listedSidekicks }
        let countReload: @MainActor () -> Void = { [unowned self] in self.reloadCount += 1 }
        return SidekickWidgetPublisher(fileURL: widgetsFileURL, store: store, sidekicks: listSidekicks,
                                       now: { fixedNow }, calendar: { calendarPT }, reloadWidget: countReload,
                                       pendingActionsFileURL: queue ? actionsFileURL : nil)
    }

    private func seed() throws {
        try store.set(sidekickId: "care-reminders", key: "widget:meds", value: medsWidget)
        let vitaminD = json(#"{ "title": "Vitamin D", "at": "\#(ReminderRecord.formatDate(octoberPT(13, 9)))" }"#)
        try store.set(sidekickId: "care-reminders", key: "reminder:vitd", value: vitaminD)
        try store.set(sidekickId: "water", key: "widget:glasses", value: waterWidget)
        try store.set(sidekickId: "water", key: "water:today", value: json(#"{ "glasses": 3 }"#))
        try store.set(sidekickId: "notes", key: "note:1", value: json(#"{ "text": "hi" }"#))
    }

    private func publishedFile() -> SharedSidekickWidgets? {
        return SharedSidekickWidgets.read(from: widgetsFileURL)
    }

    private func smallTexts(_ choiceId: String) -> [String] {
        guard case .vstack(let stack)? = publishedFile()?.widget(choiceId: choiceId)?.looks.first?.small else {
            return []
        }
        var texts: [String] = []
        for child in stack.children {
            if case .text(let textPiece) = child {
                texts.append(textPiece.text)
            }
        }
        return texts
    }

    private func firstButtonAction(_ choiceId: String) -> WidgetTapAction? {
        guard case .vstack(let stack)? = publishedFile()?.widget(choiceId: choiceId)?.looks.first?.small else {
            return nil
        }
        for child in stack.children {
            if case .button(let button) = child {
                return button.action
            }
        }
        return nil
    }

    func testPublishWritesEveryListedSidekicksWidgetsAndReloads() throws {
        try seed()
        let publisher = makePublisher()
        publisher.publish()
        let file = try XCTUnwrap(publishedFile())
        XCTAssertEqual(file.widgets.map(\.choiceId), ["care-reminders/meds", "water/glasses"])
        XCTAssertEqual(file.widgets.map(\.sidekickName), ["Reminders", "Water"])
        XCTAssertEqual(smallTexts("care-reminders/meds"), ["1 left"])
        XCTAssertEqual(smallTexts("water/glasses"), ["3"])
        XCTAssertEqual(reloadCount, 1)
    }

    func testASidekickTheUserDoesNotHaveIsLeftOut() throws {
        try seed()
        listedSidekicks = [(id: "water", name: "Water")]
        makePublisher().publish()
        XCTAssertEqual(publishedFile()?.widgets.map(\.choiceId), ["water/glasses"])
    }

    func testSignedOutRemovesTheFile() throws {
        try seed()
        let publisher = makePublisher()
        publisher.publish()
        XCTAssertNotNil(publishedFile())
        listedSidekicks = []
        publisher.publish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: widgetsFileURL.path))
    }

    func testARecordChangeRefillsOnlyForSidekicksWithWidgets() throws {
        try seed()
        let publisher = makePublisher()
        publisher.startWatchingStore()
        publisher.publish()
        let reloadsBefore = reloadCount
        try store.set(sidekickId: "notes", key: "note:2", value: json(#"{ "text": "no widget" }"#))
        XCTAssertEqual(reloadCount, reloadsBefore)
        try store.set(sidekickId: "water", key: "water:today", value: json(#"{ "glasses": 6 }"#))
        XCTAssertEqual(reloadCount, reloadsBefore + 1)
        XCTAssertEqual(smallTexts("water/glasses"), ["6"])
        XCTAssertTrue(publisher.affectsWidgets(LocalRecordChange(sidekickId: "notes", key: "widget:new")))
    }

    func testIncrementTapAddsToTheRecordAndRedraws() throws {
        try seed()
        let publisher = makePublisher()
        publisher.publish()
        let plusAction = try XCTUnwrap(firstButtonAction("water/glasses"))
        publisher.perform(plusAction)
        XCTAssertEqual(store.get(sidekickId: "water", key: "water:today")?["glasses"], .number(4))
        XCTAssertEqual(smallTexts("water/glasses"), ["4"])
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty)
    }

    func testTakenTicksTheReminderAsTheNotificationsDoneDoes() throws {
        try seed()
        let publisher = makePublisher()
        publisher.publish()
        let takenAction = try XCTUnwrap(firstButtonAction("care-reminders/meds"))
        publisher.perform(takenAction)
        let reminder = store.get(sidekickId: "care-reminders", key: "reminder:vitd")
        XCTAssertEqual(reminder?["done"], .bool(true))
        XCTAssertEqual(reminder?["completedAt"], .string(ReminderRecord.formatDate(now)))
        XCTAssertEqual(smallTexts("care-reminders/meds"), ["0 left"])
        XCTAssertNil(firstButtonAction("care-reminders/meds"))
    }

    func testATapWithoutTheAppGroupQueueWritesStraightAway() throws {
        try seed()
        let publisher = makePublisher(queue: false)
        let toggle = WidgetTapAction(kind: .toggle, sidekickId: "water", key: "settings:lamp", field: "on", amount: nil, valueJSON: nil, occurrence: nil)
        publisher.perform(toggle)
        XCTAssertEqual(store.get(sidekickId: "water", key: "settings:lamp")?["on"], .bool(true))
        publisher.perform(toggle)
        XCTAssertEqual(store.get(sidekickId: "water", key: "settings:lamp")?["on"], .bool(false))
    }

    func testTapsQueuedByTheWidgetAreAppliedAtTheNextPublish() throws {
        try seed()
        let reset = WidgetTapAction(kind: .set, sidekickId: "water", key: "water:today", field: "glasses", amount: nil, valueJSON: "0", occurrence: nil)
        PendingWidgetActionsFile.append(PendingWidgetAction(action: reset, tappedAt: now), to: actionsFileURL)
        makePublisher().publish()
        XCTAssertEqual(store.get(sidekickId: "water", key: "water:today")?["glasses"], .number(0))
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty)
    }

    func testTapsNeverWriteShellRecordsOrAnotherUsersSidekick() throws {
        try seed()
        let publisher = makePublisher(queue: false)
        let widgetOverwrite = WidgetTapAction(kind: .set, sidekickId: "water", key: "widget:glasses", field: "name", amount: nil, valueJSON: "\"x\"", occurrence: nil)
        XCTAssertTrue(publisher.write(widgetOverwrite))
        XCTAssertEqual(store.get(sidekickId: "water", key: "widget:glasses")?["name"], .string("Glasses"))
        let reminderIncrement = WidgetTapAction(kind: .increment, sidekickId: "care-reminders", key: "reminder:vitd", field: "at", amount: 1, valueJSON: nil, occurrence: nil)
        XCTAssertTrue(publisher.write(reminderIncrement))
        XCTAssertEqual(store.get(sidekickId: "care-reminders", key: "reminder:vitd")?["at"], .string(ReminderRecord.formatDate(octoberPT(13, 9))))
        let unlisted = WidgetTapAction(kind: .increment, sidekickId: "notes", key: "note:1", field: "count", amount: 1, valueJSON: nil, occurrence: nil)
        XCTAssertTrue(publisher.write(unlisted))
        XCTAssertNil(store.get(sidekickId: "notes", key: "note:1")?["count"])
    }

    func testTickingANonReminderRecordMarksItDone() {
        let action = WidgetTapAction(kind: .tick, sidekickId: "habits", key: "habit:walk", field: nil, amount: nil, valueJSON: nil, occurrence: nil)
        let ticked = SidekickWidgetPublisher.changedValue(json(#"{ "title": "Walk" }"#), by: action, now: now)
        XCTAssertEqual(ticked?["done"], .bool(true))
        XCTAssertEqual(ticked?["title"], .string("Walk"))
        XCTAssertNil(SidekickWidgetPublisher.changedValue(nil, by: action, now: now))
    }

    func testIncrementStartsAMissingRecordFromZero() {
        let action = WidgetTapAction(kind: .increment, sidekickId: "water", key: "water:wed", field: "glasses", amount: 1, valueJSON: nil, occurrence: nil)
        XCTAssertEqual(SidekickWidgetPublisher.changedValue(nil, by: action, now: now), json(#"{ "glasses": 1 }"#))
    }

    // MARK: Settings sheet

    func testThePickerListsSidekicksWithWidgetsThenThatSidekicksWidgets() async throws {
        try seed()
        try store.set(sidekickId: "care-reminders", key: "widget:next", value: json(#"{ "name": "Next up", "small": { "text": "x" } }"#))
        makePublisher().publish()
        let sidekickQuery = WidgetSidekickQuery(fileURL: widgetsFileURL)
        let sidekickNames = sidekickQuery.allEntities().map(\.name)
        XCTAssertEqual(sidekickNames, ["Reminders", "Water"])
        let choiceQuery = SidekickWidgetChoiceQuery(fileURL: widgetsFileURL)
        XCTAssertEqual(choiceQuery.choices(sidekickId: "care-reminders").map(\.name), ["Meds today", "Next up"])
        XCTAssertEqual(choiceQuery.choices(sidekickId: "water").map(\.id), ["water/glasses"])
        XCTAssertEqual(choiceQuery.choices(sidekickId: nil).count, 3)
        let found = try await choiceQuery.entities(for: ["water/glasses", "gone/x"])
        XCTAssertEqual(found.map(\.sidekickId), ["water"])
    }

    func testThePickerIsEmptyWithoutAFile() {
        XCTAssertTrue(WidgetSidekickQuery(fileURL: widgetsFileURL).allEntities().isEmpty)
        XCTAssertTrue(SidekickWidgetChoiceQuery(fileURL: nil).choices(sidekickId: nil).isEmpty)
    }

    // MARK: Wiring

    func testTheWidgetIsInTheGalleryAndTheAppRunsItsTaps() throws {
        let shellDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let bundleSource = try String(contentsOf: shellDirectory.appending(path: "MidasWidgets/MidasWidgetsBundle.swift"), encoding: .utf8)
        XCTAssertTrue(bundleSource.contains("SidekickWidget()"))
        let appSource = try String(contentsOf: shellDirectory.appending(path: "Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertTrue(appSource.contains("SidekickWidgetIntentBridge.perform = Self.performFromSidekickWidget"))
        XCTAssertTrue(appSource.contains("sidekickWidgets.publish()"))
        let servicesSource = try String(contentsOf: shellDirectory.appending(path: "Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertTrue(servicesSource.contains("sidekickWidgets.startWatchingStore()"))
        XCTAssertTrue(servicesSource.contains("ShellServices.shared.sidekickWidgets.publish()"))
    }

    func testTheWidgetsWordsFollowTheWritingRules() {
        XCTAssertEqual(SidekickWidgetCopy.displayName, "Sidekick")
        XCTAssertEqual(SidekickWidgetCopy.description, "A Sidekick on your Home Screen.")
        XCTAssertEqual(SidekickWidgetCopy.pickSidekick, "Pick a Sidekick")
        XCTAssertEqual(SidekickWidgetCopy.empty, "Open Midas")
    }
}
