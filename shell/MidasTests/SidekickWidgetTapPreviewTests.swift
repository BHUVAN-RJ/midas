import XCTest
@testable import Midas

// A widget tap shows on the widget at once (founder, 2026-10-26: "+0.25 L saves but the widget does
// not change until Midas opens"). The app publishes the records of every Sidekick with a widget;
// the widget refills itself from them with the taps still waiting in the App Group queue.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

// Water's shape: one record per day, a button that adds 250 ml to the day it was tapped.
private let dayWidget = json(#"""
{ "name": "Today",
  "sources": { "day": { "record": "water:{today}" } },
  "small": { "vstack": [ { "text": "$day.ml" }, { "button": "+", "action": { "increment": "water:{today}", "field": "ml", "by": 250 } } ] } }
"""#)

@MainActor
final class SidekickWidgetTapPreviewTests: XCTestCase {
    private var directory: URL!
    private var store: LocalRecordStore!
    private var widgetsFileURL: URL!
    private var actionsFileURL: URL!
    private var recordsFileURL: URL!
    private var listedSidekicks: [(id: String, name: String)] = [(id: "hydration", name: "Water"), (id: "notes", name: "Notes")]
    private let now = octoberPT(26, 10)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "tap-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        widgetsFileURL = directory.appending(path: "widgets.json")
        actionsFileURL = directory.appending(path: "actions.json")
        recordsFileURL = directory.appending(path: "records-snapshot.json")
        try store.set(sidekickId: "hydration", key: "widget:today", value: dayWidget)
        try store.set(sidekickId: "hydration", key: "water:2026-10-26", value: json(#"{ "ml": 1000 }"#))
        try store.set(sidekickId: "notes", key: "note:1", value: json(#"{ "text": "hi" }"#))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePublisher() -> SidekickWidgetPublisher {
        let fixedNow = now
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [unowned self] in self.listedSidekicks }
        let ignoreReload: @MainActor () -> Void = {}
        return SidekickWidgetPublisher(fileURL: widgetsFileURL, store: store, sidekicks: listSidekicks,
                                       now: { fixedNow }, calendar: { calendarPT }, reloadWidget: ignoreReload,
                                       pendingActionsFileURL: actionsFileURL, recordsFileURL: recordsFileURL)
    }

    private func publishedWidget() throws -> FilledSidekickWidget {
        let file = try XCTUnwrap(SharedSidekickWidgets.read(from: widgetsFileURL))
        return try XCTUnwrap(file.widget(choiceId: "hydration/today"))
    }

    /// What the widget draws now: the preview when it has one, else the published widget.
    private func drawnWidget(at moment: Date) throws -> FilledSidekickWidget {
        let published = try publishedWidget()
        let preview = SidekickWidgetTapPreview.widget(published, snapshot: SidekickWidgetRecordsSnapshot.read(from: recordsFileURL),
                                                      pendingActions: PendingWidgetActionsFile.read(from: actionsFileURL),
                                                      now: moment, calendar: calendarPT)
        return preview ?? published
    }

    private func smallText(_ widget: FilledSidekickWidget, at moment: Date) -> String? {
        guard case .vstack(let stack)? = widget.look(at: moment)?.small else {
            return nil
        }
        for child in stack.children {
            if case .text(let textPiece) = child {
                return textPiece.text
            }
        }
        return nil
    }

    private func buttonAction(_ widget: FilledSidekickWidget) -> WidgetTapAction? {
        guard case .vstack(let stack)? = widget.looks.first?.small else {
            return nil
        }
        for child in stack.children {
            if case .button(let button) = child {
                return button.action
            }
        }
        return nil
    }

    /// What the widget extension does when the tap cannot reach the app: queue it, nothing else.
    private func tapInTheWidget(_ action: WidgetTapAction, at moment: Date) {
        PendingWidgetActionsFile.append(PendingWidgetAction(action: action, tappedAt: moment), to: actionsFileURL)
    }

    func testATapWaitingForTheAppShowsOnTheWidgetAtOnce() throws {
        makePublisher().publish()
        let plus = try XCTUnwrap(buttonAction(try publishedWidget()))
        XCTAssertEqual(smallText(try drawnWidget(at: now), at: now), "1000")
        tapInTheWidget(plus, at: now)
        XCTAssertEqual(smallText(try drawnWidget(at: now), at: now), "1250")
        tapInTheWidget(plus, at: now)
        XCTAssertEqual(smallText(try drawnWidget(at: now), at: now), "1500", "every waiting tap counts")
        XCTAssertEqual(store.get(sidekickId: "hydration", key: "water:2026-10-26")?["ml"], .number(1000), "the preview writes nothing")
    }

    func testOnceTheAppWritesTheTapsTheyAreNotCountedTwice() throws {
        makePublisher().publish()
        let plus = try XCTUnwrap(buttonAction(try publishedWidget()))
        tapInTheWidget(plus, at: now)
        tapInTheWidget(plus, at: now)
        makePublisher().publish()
        XCTAssertEqual(store.get(sidekickId: "hydration", key: "water:2026-10-26")?["ml"], .number(1500))
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty)
        XCTAssertEqual(smallText(try drawnWidget(at: now), at: now), "1500")
    }

    func testATapInTheAppsProcessNeedsNoPreview() throws {
        let publisher = makePublisher()
        publisher.publish()
        let plus = try XCTUnwrap(buttonAction(try publishedWidget()))
        publisher.perform(plus)
        XCTAssertEqual(smallText(try publishedWidget(), at: now), "1250")
        XCTAssertEqual(smallText(try drawnWidget(at: now), at: now), "1250")
    }

    func testAWaitingTapLandsOnTheDayItWasTapped() throws {
        makePublisher().publish()
        let plus = try XCTUnwrap(buttonAction(try publishedWidget()))
        // Tapped at 23:59, drawn after midnight: yesterday got the 250, today starts empty.
        tapInTheWidget(plus, at: octoberPT(26, 23, 59))
        let afterMidnight = octoberPT(27, 0, 5)
        XCTAssertEqual(smallText(try drawnWidget(at: afterMidnight), at: afterMidnight), "")
        XCTAssertEqual(smallText(try drawnWidget(at: octoberPT(26, 23, 59)), at: octoberPT(26, 23, 59)), "1250")
    }

    func testTapsOnReminderShellOrOtherSidekicksRecordsChangeNothing() throws {
        makePublisher().publish()
        let reminderTick = WidgetTapAction(kind: .tick, sidekickId: "hydration", key: "reminder:water", field: nil, amount: nil, valueJSON: nil, occurrence: nil)
        let widgetWrite = WidgetTapAction(kind: .set, sidekickId: "hydration", key: "widget:today", field: "name", amount: nil, valueJSON: "\"x\"", occurrence: nil)
        let otherSidekick = WidgetTapAction(kind: .increment, sidekickId: "notes", key: "water:2026-10-26", field: "ml", amount: 250, valueJSON: nil, occurrence: nil)
        tapInTheWidget(reminderTick, at: now)
        tapInTheWidget(widgetWrite, at: now)
        tapInTheWidget(otherSidekick, at: now)
        let preview = SidekickWidgetTapPreview.widget(try publishedWidget(), snapshot: SidekickWidgetRecordsSnapshot.read(from: recordsFileURL),
                                                      pendingActions: PendingWidgetActionsFile.read(from: actionsFileURL),
                                                      now: now, calendar: calendarPT)
        XCTAssertNil(preview)
    }

    func testTheRecordsFileHoldsOnlySidekicksWithWidgetsAndGoesWhenSignedOut() throws {
        makePublisher().publish()
        let snapshot = try XCTUnwrap(SidekickWidgetRecordsSnapshot.read(from: recordsFileURL))
        var snapshotIds: [String] = []
        for sidekick in snapshot.sidekicks {
            snapshotIds.append(sidekick.id)
        }
        XCTAssertEqual(snapshotIds, ["hydration"])
        listedSidekicks = []
        makePublisher().publish()
        XCTAssertNil(SidekickWidgetRecordsSnapshot.read(from: recordsFileURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordsFileURL.path))
    }

    func testTheWidgetExtensionCompilesThePreview() throws {
        let repoShell = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: repoShell.appending(path: "project.yml"), encoding: .utf8)
        let widgetSource = try String(contentsOf: repoShell.appending(path: "MidasWidgets/SidekickWidget.swift"), encoding: .utf8)
        XCTAssertTrue(project.contains("- Midas/SidekickWidgetTapPreview.swift"))
        XCTAssertTrue(widgetSource.contains("SidekickWidgetTapPreview.widget("), "the widget draws the preview")
    }
}
