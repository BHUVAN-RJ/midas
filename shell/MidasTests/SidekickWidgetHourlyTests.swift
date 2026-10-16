import XCTest
@testable import Midas

// Hourly doses still count in a Sidekick widget once they are fields on the item (unified data
// plan, section 4): the filler expands an hourly item's times into reminders of their own, and a
// tick on one of them lands on the item as `slotsDone`.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let medsWidget = json(#"""
{ "name": "Meds today",
  "sources": { "today": { "records": "reminder:", "when": "today", "where": { "$type": "care.item" } } },
  "small": { "vstack": [ { "text": "$today.open left" }, { "text": "$today.done done" }, { "button": "Taken", "action": { "tick": "$today.next" } } ] } }
"""#)

@MainActor
final class SidekickWidgetHourlyTests: XCTestCase {
    private var folder: URL!
    private var store: LocalRecordStore!
    private let now = octoberPT(13, 10)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "widget-hourly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        try store.set(sidekickId: "care-reminders", key: "widget:meds", value: medsWidget)
        // Every 4 hours from midnight yesterday: 00, 04, 08, 12, 16, 20.
        let pills: JSONValue = .object([
            "$type": .string("care.item"), "title": .string("Pills"), "at": .string(ReminderRecord.formatDate(octoberPT(12, 0))),
            "timeZone": .string("America/Los_Angeles"), "done": .bool(false), "list": .string("medicine"),
            "repeat": .object(["every": .string("day")]), "everyHours": .number(4),
        ])
        try store.set(sidekickId: "care-reminders", key: "reminder:pills", value: pills)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makePublisher() -> SidekickWidgetPublisher {
        let fixedNow = now
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: "care-reminders", name: "Reminders")] }
        return SidekickWidgetPublisher(fileURL: folder.appending(path: "widgets.json"), store: store, sidekicks: listSidekicks,
                                       now: { fixedNow }, calendar: { calendarPT }, reloadWidget: {},
                                       pendingActionsFileURL: folder.appending(path: "actions.json"))
    }

    private func todaySource() -> JSONValue? {
        let filler = SidekickWidgetFiller(calendar: calendarPT)
        let sidekickRecords = store.query(sidekickId: "care-reminders", keyPrefix: "")
        return filler.sourceValues(description: medsWidget, sidekickRecords: sidekickRecords, at: now)["today"]
    }

    private func todayIds() -> [String] {
        var ids: [String] = []
        for item in todaySource()?["items"]?.arrayValue ?? [] {
            ids.append(item["id"]?.stringValue ?? "")
        }
        return ids
    }

    func testEveryDoseOfTodayCountsAndIsItsOwnRow() {
        // At 10:00: 00:00, 04:00 and 08:00 missed today, 12:00, 16:00 and 20:00 still to come.
        XCTAssertEqual(todayIds(), ["pills", "pills@0400", "pills@0800", "pills@1200", "pills@1600", "pills@2000"])
        XCTAssertEqual(todaySource()?["open"], .number(6))
        XCTAssertEqual(todaySource()?["count"], .number(6))
        XCTAssertEqual(todaySource()?["done"], .number(0))
        let eightOClock = todaySource()?["items"]?.arrayValue?[2]
        XCTAssertEqual(eightOClock?["title"], .string("Pills"))
        XCTAssertEqual(eightOClock?["key"], .string("reminder:pills@0800"))
        XCTAssertEqual(eightOClock?["time"], .string("8:00 AM"))
    }

    func testTakenOnADoseMarksThatTimeDoneOnTheItemAndTheRowLeaves() throws {
        let publisher = makePublisher()
        let taken = WidgetTapAction(kind: .tick, sidekickId: "care-reminders", key: "reminder:pills@0800", field: nil, amount: nil, valueJSON: nil, occurrence: octoberPT(13, 8))
        XCTAssertEqual(SidekickWidgetPublisher.targetKey(for: taken), "reminder:pills")
        publisher.perform(taken)

        let item = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: "reminder:pills"))
        XCTAssertEqual(item["slotsDone"]?["08:00"], .string(ReminderRecord.formatDate(now)))
        XCTAssertNil(item["lastDoneAt"], "the item's own time is not done")
        XCTAssertNil(item["done"]?.boolValue == true ? item["done"] : nil, "the whole item is not done")
        XCTAssertNil(store.get(sidekickId: "care-reminders", key: "reminder:pills@0800"), "no record of its own is written")
        XCTAssertEqual(todayIds(), ["pills", "pills@0400", "pills@1200", "pills@1600", "pills@2000"])
        XCTAssertEqual(todaySource()?["done"], .number(1))
        XCTAssertEqual(todaySource()?["count"], .number(6))

        // Taken on the item's own time is the ordinary Done on a repeat.
        let ownTime = WidgetTapAction(kind: .tick, sidekickId: "care-reminders", key: "reminder:pills", field: nil, amount: nil, valueJSON: nil, occurrence: octoberPT(13, 0))
        publisher.perform(ownTime)
        let ticked = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: "reminder:pills"))
        XCTAssertEqual(ticked["lastDoneAt"], .string(ReminderRecord.formatDate(now)))
        XCTAssertEqual(ticked["doneThrough"], .string(ReminderRecord.formatDate(octoberPT(13, 0))))
        XCTAssertEqual(ticked["slotsDone"]?["08:00"], .string(ReminderRecord.formatDate(now)), "the dose's Done is kept")
        XCTAssertEqual(todayIds(), ["pills@0400", "pills@1200", "pills@1600", "pills@2000"])
    }

    func testTheExpandedDosesCarryTheItemsFieldsAndTheirOwnTimes() {
        let expansion = ReminderExpansion(schedule: ReminderSchedule(calendar: calendarPT))
        let item = store.query(sidekickId: "care-reminders", keyPrefix: "reminder:pills")[0]
        let doses = expansion.slotRecords(of: item)
        XCTAssertEqual(doses.map(\.key), ["reminder:pills@0400", "reminder:pills@0800", "reminder:pills@1200", "reminder:pills@1600", "reminder:pills@2000"])
        let noon = doses[2].value
        XCTAssertEqual(noon["at"], .string(ReminderRecord.formatDate(octoberPT(12, 12))))
        XCTAssertEqual(noon["repeat"], .object(["every": .string("day")]))
        XCTAssertEqual(noon["list"], .string("medicine"))
        XCTAssertEqual(noon["$type"], .string("care.item"))
        XCTAssertNil(noon["everyHours"])
        XCTAssertNil(noon["slotsDone"])
        XCTAssertEqual(expansion.slotRecords(of: LocalRecord(sidekickId: "care-reminders", key: "reminder:plain", value: .object(["title": .string("x"), "at": .string("2026-10-13T20:00:00.000Z")]))), [])
    }
}
