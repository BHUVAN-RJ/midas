import XCTest
@testable import Midas

// A reminder tick shows on the Sidekick widget at once (founder, 2026-10-26, the Reminders widget
// made with the builder): while the tick waits in the App Group for the app, the widget refills
// itself with the Done patch the app will write (ReminderChange.donePatch, now compiled into the
// widget extension), hourly times and early alerts included.

private let tickCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func tickOctober(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return tickCalendar.date(from: components)!
}

private func tickJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let todayWidget = tickJSON(#"""
{ "name": "Today",
  "sources": { "today": { "records": "reminder:", "when": "today" } },
  "small": { "vstack": [ { "text": "$today.open" }, { "list": "$today.items", "row": { "hstack": [ { "tick": "$item" }, { "text": "$item.title $item.time" } ] } } ] } }
"""#)

private func reminderValue(_ title: String, at moment: Date, extraFields: [String: JSONValue] = [:]) -> JSONValue {
    var fields: [String: JSONValue] = [
        "title": .string(title), "at": .string(ReminderRecord.formatDate(moment)), "done": .bool(false),
        "timeZone": .string("America/Los_Angeles"),
    ]
    for (fieldName, fieldValue) in extraFields {
        fields[fieldName] = fieldValue
    }
    return .object(fields)
}

@MainActor
final class SidekickWidgetReminderTickPreviewTests: XCTestCase {
    private var folder: URL!
    private var store: LocalRecordStore!
    private let now = tickOctober(13, 10)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reminder-tick-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        try store.set(sidekickId: "reminders", key: "widget:today", value: todayWidget)
        try store.set(sidekickId: "reminders", key: "reminder:call", value: reminderValue("Call", at: tickOctober(13, 18)))
        let daily = ["repeat": JSONValue.object(["every": .string("day")])]
        try store.set(sidekickId: "reminders", key: "reminder:gym", value: reminderValue("Gym", at: tickOctober(1, 19), extraFields: daily))
        // Every 4 hours from midnight: 12, 16 and 20 still to come at 10:00.
        let hourly: [String: JSONValue] = ["repeat": .object(["every": .string("day")]), "everyHours": .number(4)]
        try store.set(sidekickId: "reminders", key: "reminder:pills", value: reminderValue("Pills", at: tickOctober(12, 0), extraFields: hourly))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var widgetsFileURL: URL { folder.appending(path: "widgets.json") }
    private var actionsFileURL: URL { folder.appending(path: "actions.json") }
    private var recordsFileURL: URL { folder.appending(path: "records-snapshot.json") }

    private func makePublisher() -> SidekickWidgetPublisher {
        let fixedNow = now
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: "reminders", name: "Reminders")] }
        let ignoreReload: @MainActor () -> Void = {}
        return SidekickWidgetPublisher(fileURL: widgetsFileURL, store: store, sidekicks: listSidekicks,
                                       now: { fixedNow }, calendar: { tickCalendar }, reloadWidget: ignoreReload,
                                       pendingActionsFileURL: actionsFileURL, recordsFileURL: recordsFileURL)
    }

    private func publishedWidget() throws -> FilledSidekickWidget {
        let file = try XCTUnwrap(SharedSidekickWidgets.read(from: widgetsFileURL))
        return try XCTUnwrap(file.widget(choiceId: "reminders/today"))
    }

    /// What the widget extension draws: the preview when there is one, else the published widget.
    private func drawnWidget() throws -> FilledSidekickWidget {
        let published = try publishedWidget()
        let preview = SidekickWidgetTapPreview.widget(published, snapshot: SidekickWidgetRecordsSnapshot.read(from: recordsFileURL),
                                                      pendingActions: PendingWidgetActionsFile.read(from: actionsFileURL),
                                                      now: now, calendar: tickCalendar)
        return preview ?? published
    }

    /// The rows' words and the ticks' actions, in order.
    private func rows(_ widget: FilledSidekickWidget) -> (texts: [String], ticks: [WidgetTapAction]) {
        var texts: [String] = []
        var ticks: [WidgetTapAction] = []
        guard case .vstack(let column)? = widget.look(at: now)?.small, column.children.count == 2,
              case .vstack(let list) = column.children[1] else {
            return (texts, ticks)
        }
        for row in list.children {
            guard case .hstack(let line) = row, case .tick(let tick) = line.children[0], case .text(let title) = line.children[1] else {
                continue
            }
            ticks.append(tick.action)
            texts.append(title.text)
        }
        return (texts, ticks)
    }

    private func openCount(_ widget: FilledSidekickWidget) -> String? {
        guard case .vstack(let column)? = widget.look(at: now)?.small, case .text(let count) = column.children[0] else {
            return nil
        }
        return count.text
    }

    private func tickInTheWidget(_ title: String) throws {
        let published = rows(try publishedWidget())
        let index = try XCTUnwrap(published.texts.firstIndex(of: title), "no row \(title)")
        let pendingAction = PendingWidgetAction(action: published.ticks[index], tappedAt: now)
        PendingWidgetActionsFile.append(pendingAction, to: actionsFileURL)
    }

    func testTheRowsBeforeAnyTick() throws {
        makePublisher().publish()
        XCTAssertEqual(rows(try drawnWidget()).texts, ["Pills 12:00 AM", "Pills 4:00 AM", "Pills 8:00 AM", "Pills 12:00 PM", "Pills 4:00 PM", "Call 6:00 PM", "Gym 7:00 PM", "Pills 8:00 PM"])
        XCTAssertEqual(openCount(try drawnWidget()), "8")
    }

    func testATickedOneTimeReminderLeavesAtOnceAndNothingIsWritten() throws {
        makePublisher().publish()
        try tickInTheWidget("Call 6:00 PM")
        let drawn = try drawnWidget()
        XCTAssertFalse(rows(drawn).texts.contains("Call 6:00 PM"))
        XCTAssertEqual(openCount(drawn), "7")
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:call")?["done"], .bool(false), "the preview writes nothing")
    }

    func testATickedRepeatLeavesTodayAtOnce() throws {
        makePublisher().publish()
        try tickInTheWidget("Gym 7:00 PM")
        XCTAssertFalse(rows(try drawnWidget()).texts.contains("Gym 7:00 PM"))
    }

    func testATickedHourlyTimeLeavesAndTheOtherTimesStay() throws {
        makePublisher().publish()
        try tickInTheWidget("Pills 8:00 AM")
        let texts = rows(try drawnWidget()).texts
        XCTAssertFalse(texts.contains("Pills 8:00 AM"))
        XCTAssertTrue(texts.contains("Pills 4:00 AM"))
        XCTAssertTrue(texts.contains("Pills 12:00 PM"))
        XCTAssertTrue(texts.contains("Pills 8:00 PM"))
        XCTAssertEqual(texts.count, 7)
    }

    func testThePreviewMatchesWhatTheAppWrites() throws {
        makePublisher().publish()
        try tickInTheWidget("Call 6:00 PM")
        try tickInTheWidget("Pills 8:00 AM")
        let previewTexts = rows(try drawnWidget()).texts
        makePublisher().publish()
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty, "the app wrote the queue")
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:call")?["done"], .bool(true))
        XCTAssertEqual(previewTexts.count, 6, "both rows left in the preview")
        XCTAssertEqual(rows(try publishedWidget()).texts, previewTexts)
        XCTAssertEqual(rows(try drawnWidget()).texts, previewTexts, "not ticked twice")
    }

    func testTheSamePatchAsTheApp() {
        let value = reminderValue("Call", at: tickOctober(13, 18), extraFields: ["snoozedUntil": .string(ReminderRecord.formatDate(tickOctober(13, 18, 10)))])
        let tick = WidgetTapAction(kind: .tick, sidekickId: "reminders", key: "reminder:call", field: nil, amount: nil, valueJSON: nil, occurrence: tickOctober(13, 18))
        let expected = ReminderChange.donePatch(for: value, part: .item, occurrence: tickOctober(13, 18), now: now)
        XCTAssertEqual(SidekickWidgetTapPatch.patch(for: value, by: tick, now: now), expected)
        XCTAssertEqual(SidekickWidgetPublisher.patch(for: value, by: tick, now: now), expected)
        let doseTick = WidgetTapAction(kind: .tick, sidekickId: "reminders", key: "reminder:pills@1600", field: nil, amount: nil, valueJSON: nil, occurrence: tickOctober(13, 16))
        XCTAssertEqual(SidekickWidgetTapPatch.targetKey(for: doseTick), "reminder:pills")
        XCTAssertEqual(SidekickWidgetTapPatch.patch(for: value, by: doseTick, now: now), ReminderChange.donePatch(for: value, part: .slot(time: "16:00"), occurrence: tickOctober(13, 16), now: now))
    }

    func testOtherTapsOnRemindersStayRefused() throws {
        makePublisher().publish()
        let rename = WidgetTapAction(kind: .set, sidekickId: "reminders", key: "reminder:call", field: "title", amount: nil, valueJSON: "\"x\"", occurrence: nil)
        PendingWidgetActionsFile.append(PendingWidgetAction(action: rename, tappedAt: now), to: actionsFileURL)
        let preview = SidekickWidgetTapPreview.widget(try publishedWidget(), snapshot: SidekickWidgetRecordsSnapshot.read(from: recordsFileURL),
                                                      pendingActions: PendingWidgetActionsFile.read(from: actionsFileURL),
                                                      now: now, calendar: tickCalendar)
        XCTAssertNil(preview, "only a tick may change a reminder")
    }

    func testTheWidgetExtensionCompilesTheDonePatch() throws {
        let shellFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: shellFolder.appending(path: "project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("- Midas/ReminderChange.swift"), "the widget target compiles ReminderChange")
        let writerSource = try String(contentsOf: shellFolder.appending(path: "Midas/RecordWriter.swift"), encoding: .utf8)
        XCTAssertFalse(writerSource.contains("enum ReminderChange"), "ReminderChange lives in its own file")
        let changeSource = try String(contentsOf: shellFolder.appending(path: "Midas/ReminderChange.swift"), encoding: .utf8)
        XCTAssertFalse(changeSource.contains("@MainActor"), "nothing app-only in it")
    }
}
