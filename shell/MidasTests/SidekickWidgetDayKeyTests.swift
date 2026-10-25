import XCTest
@testable import Midas

// Hydration plan W1 (founder, 2026-10-25; docs/briefs/hydration-sidekick.md section 2.1): `{today}`
// in a source's `record` key and in a tap's key is the local date. The midnight look reads the new
// day; a tap lands on the day it was made, even when the app writes it after midnight; an
// increment on a day with no record yet makes one, typed by the Sidekick's manifest.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let dayWidget = json(#"""
{ "name": "Water today",
  "sources": { "water": { "record": "water:{today}" } },
  "small": { "vstack": [ { "text": "$water.ml" }, { "button": "+250", "action": { "increment": "water:{today}", "field": "ml", "by": 250 } } ] } }
"""#)

private let hydrationTypes = json(#"""
{ "water:": { "$type": "hydration.day",
              "schema": { "type": "object", "required": ["ml"],
                          "properties": { "$type": { "type": "string" }, "ml": { "type": "number", "minimum": 0 }, "goalMl": { "type": "number" } } } } }
"""#)

@MainActor
final class SidekickWidgetDayKeyTests: XCTestCase {
    private var directory: URL!
    private var store: LocalRecordStore!
    private var widgetsFileURL: URL!
    private var actionsFileURL: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "widget-day-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        widgetsFileURL = directory.appending(path: "widgets.json")
        actionsFileURL = directory.appending(path: "actions.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePublisher(now: Date) -> SidekickWidgetPublisher {
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: "hydration", name: "Water")] }
        let doNothing: @MainActor () -> Void = {}
        return SidekickWidgetPublisher(fileURL: widgetsFileURL, store: store, sidekicks: listSidekicks,
                                       now: { now }, calendar: { calendarPT }, reloadWidget: doNothing,
                                       pendingActionsFileURL: actionsFileURL)
    }

    private func firstText(of look: FilledWidgetLook) -> String? {
        guard case .vstack(let stack)? = look.small, case .text(let textPiece)? = stack.children.first else {
            return nil
        }
        return textPiece.text
    }

    private func buttonAction(of look: FilledWidgetLook) -> WidgetTapAction? {
        guard case .vstack(let stack)? = look.small else {
            return nil
        }
        for child in stack.children {
            if case .button(let button) = child {
                return button.action
            }
        }
        return nil
    }

    private func increment(_ key: String) -> WidgetTapAction {
        return WidgetTapAction(kind: .increment, sidekickId: "hydration", key: key, field: "ml", amount: 250, valueJSON: nil, occurrence: nil)
    }

    // MARK: The key

    func testTodayIsTheLocalDateInTheCalendarsZone() {
        // 23:30 in Los Angeles is already the next day in UTC; the key follows the phone's zone.
        let lateEvening = octoberPT(25, 23, 30)
        XCTAssertEqual(SidekickWidgetDayKey.resolve("water:{today}", at: lateEvening, calendar: calendarPT), "water:2026-10-25")
        let calendarUTC = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(SidekickWidgetDayKey.resolve("water:{today}", at: lateEvening, calendar: calendarUTC), "water:2026-10-26")
        XCTAssertEqual(SidekickWidgetDayKey.resolve("water:today", at: lateEvening, calendar: calendarPT), "water:today")
    }

    func testTheDayIsGregorianWhateverCalendarThePhoneShows() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dayCalendar = SidekickWidgetDayKey.calendar(timeZone: buddhist.timeZone)
        XCTAssertEqual(dayCalendar.identifier, .gregorian)
        XCTAssertEqual(SidekickWidgetDayKey.dayText(octoberPT(25, 12), calendar: dayCalendar), "2026-10-25")
    }

    // MARK: Filling

    func testTheMidnightLookReadsTheNextDaysRecord() throws {
        let records = [
            LocalRecord(sidekickId: "hydration", key: "widget:today", value: dayWidget),
            LocalRecord(sidekickId: "hydration", key: "water:2026-10-25", value: json(#"{ "ml": 1750 }"#)),
            LocalRecord(sidekickId: "hydration", key: "water:2026-10-26", value: json(#"{ "ml": 250 }"#)),
        ]
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        let widget = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: records[0], sidekickRecords: records, now: octoberPT(25, 22))
        XCTAssertTrue(widget.isUsable)
        XCTAssertEqual(widget.looks.count, 2)
        XCTAssertEqual(firstText(of: widget.looks[0]), "1750")
        XCTAssertEqual(widget.looks[1].from, octoberPT(26, 0))
        XCTAssertEqual(firstText(of: widget.looks[1]), "250")
    }

    func testTheTapKeepsTodayForTheTapTime() {
        let records = [LocalRecord(sidekickId: "hydration", key: "widget:today", value: dayWidget)]
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        let widget = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: records[0], sidekickRecords: records, now: octoberPT(25, 22))
        XCTAssertEqual(buttonAction(of: widget.looks[0])?.key, "water:{today}")
        XCTAssertEqual(buttonAction(of: widget.looks[1])?.key, "water:{today}")
    }

    // MARK: Writing

    func testATapAfterMidnightWritesTheNewDay() throws {
        try store.set(sidekickId: "hydration", key: "water:2026-10-25", value: json(#"{ "ml": 1750 }"#))
        let publisher = makePublisher(now: octoberPT(26, 0, 1))
        XCTAssertTrue(publisher.write(increment("water:{today}")))
        XCTAssertEqual(store.get(sidekickId: "hydration", key: "water:2026-10-26")?["ml"]?.numberValue, 250)
        XCTAssertEqual(store.get(sidekickId: "hydration", key: "water:2026-10-25")?["ml"]?.numberValue, 1750)
    }

    func testAQueuedTapFrom2359AppliedAfterMidnightLandsOnTheOldDay() throws {
        try store.set(sidekickId: "hydration", key: "water:2026-10-25", value: json(#"{ "ml": 1750 }"#))
        try store.set(sidekickId: "hydration", key: "widget:today", value: dayWidget)
        let lateTap = PendingWidgetAction(action: increment("water:{today}"), tappedAt: octoberPT(25, 23, 59))
        PendingWidgetActionsFile.append(lateTap, to: actionsFileURL)
        let publisher = makePublisher(now: octoberPT(26, 0, 5))
        publisher.publish()
        XCTAssertEqual(store.get(sidekickId: "hydration", key: "water:2026-10-25")?["ml"]?.numberValue, 2000)
        XCTAssertNil(store.get(sidekickId: "hydration", key: "water:2026-10-26"))
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty)
    }

    func testAQueuedTapKeepsItsTapTimeInTheFile() throws {
        let tappedAt = octoberPT(25, 23, 59)
        PendingWidgetActionsFile.append(PendingWidgetAction(action: increment("water:{today}"), tappedAt: tappedAt), to: actionsFileURL)
        let queued = PendingWidgetActionsFile.read(from: actionsFileURL)
        XCTAssertEqual(queued.first?.tappedAt, tappedAt)
        XCTAssertEqual(queued.first?.action.key, "water:{today}")
    }

    func testAnIncrementOnANewDayMakesATypedRecord() throws {
        let engine = try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
        let typesFor: @MainActor (String) -> JSONValue? = { sidekickId in sidekickId == "hydration" ? hydrationTypes : nil }
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: typesFor)
        let publisher = makePublisher(now: octoberPT(26, 7))
        XCTAssertTrue(publisher.write(increment("water:{today}")))
        let newDay = store.get(sidekickId: "hydration", key: "water:2026-10-26")
        XCTAssertEqual(newDay?["ml"]?.numberValue, 250)
        XCTAssertEqual(newDay?["$type"]?.stringValue, "hydration.day")
    }

    func testAReminderKeyWithTodayIsStillProtected() {
        let reminderTap = json(#"{ "increment": "reminder:{today}", "field": "count" }"#)
        XCTAssertEqual(SidekickWidgetDescription.actionValidationError(reminderTap), "increment cannot write reminder:{today}")
    }
}
