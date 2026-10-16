import XCTest
@testable import Midas

// One writer for every native change (unified data plan, section 5, "Native writers"): read,
// merge the patch, run the store's gate, check the size, write. Every native writer keeps the
// Sidekick's unknown fields (plan section 10) because a patch names only what it changes.

private let remindersTypes: JSONValue = .object([
    "reminder:": .object([
        "$type": .string("reminders.item"),
        "schema": .object([
            "type": .string("object"),
            "required": .array([.string("title")]),
            "properties": .object([
                "title": .object(["type": .string("string"), "minLength": .number(1)]),
                "at": .object(["type": .string("string"), "format": .string("date-time")]),
                "done": .object(["type": .string("boolean")]),
                "snoozedUntil": .object(["type": .string("string"), "format": .string("date-time")]),
            ]),
        ]),
    ]),
])

@MainActor
private final class SilentBooking: NotificationBooking {
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func pendingIdentifiers() async -> [String] { [] }
    func book(_ booking: PlannedBooking) async throws {}
    func cancel(identifiers: [String]) {}
}

@MainActor
final class RecordWriterTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "writer-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func date(_ text: String) -> Date {
        ReminderRecord.parseDate(.string(text))!
    }

    private func makeGatedStore() throws -> LocalRecordStore {
        let engine = try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
        let store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: Self.typesFor)
        return store
    }

    private static func typesFor(sidekickId: String) -> JSONValue? {
        sidekickId == "reminders" ? remindersTypes : nil
    }

    func testUpdateMergesStampsKeepsUnknownFieldsAndBuildsAMissingRecord() throws {
        let store = try makeGatedStore()
        let writer = RecordWriter(store: store)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("Call"), "snoozedUntil": .string("2026-10-15T10:00:00.000Z"), "colour": .string("teal"), "repeat": .object(["every": .string("week"), "interval": .number(2)])]))

        let stored = try writer.update(sidekickId: "reminders", key: "reminder:1", patch: .object(["done": .bool(true), "snoozedUntil": .null, "repeat": .object(["interval": .number(3)])]))
        let expected: JSONValue = .object(["$type": .string("reminders.item"), "title": .string("Call"), "done": .bool(true), "colour": .string("teal"), "repeat": .object(["every": .string("week"), "interval": .number(3)])])
        XCTAssertEqual(stored, expected)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1"), expected)
        XCTAssertEqual(store.pendingOps().count, 2)

        let built = try writer.update(sidekickId: "reminders", key: "reminder:2", patch: .object(["title": .string("New")]))
        XCTAssertEqual(built["$type"], .string("reminders.item"))
    }

    func testARefusedPatchWritesNothingAndSaysWhy() throws {
        let store = try makeGatedStore()
        let writer = RecordWriter(store: store)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("Call")]))
        let before = store.get(sidekickId: "reminders", key: "reminder:1")

        XCTAssertThrowsError(try writer.update(sidekickId: "reminders", key: "reminder:1", patch: .object(["title": .string("")]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "reminders.item.title must not be empty"))
        }
        XCTAssertThrowsError(try writer.update(sidekickId: "reminders", key: "reminder:1", patch: .object(["done": .string("yes")]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "reminders.item.done must be true or false, not a string"))
        }
        let tooBig = String(repeating: "x", count: RecordWriter.maxValueBytes)
        XCTAssertThrowsError(try writer.update(sidekickId: "reminders", key: "reminder:1", patch: .object(["notes": .string(tooBig)]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "value is over \(RecordWriter.maxValueBytes) bytes"))
        }
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1"), before)
        XCTAssertEqual(store.pendingOps().count, 1)
    }

    func testTheDonePatchIsTheSameForEveryWriter() {
        let now = date("2026-10-15T17:05:00.000Z")
        let occurrence = date("2026-10-15T17:00:00.000Z")
        let oneTime: JSONValue = .object(["title": .string("Call"), "at": .string("2026-10-15T17:00:00.000Z"), "snoozedUntil": .string("2026-10-15T17:10:00.000Z")])
        XCTAssertEqual(ReminderChange.donePatch(for: oneTime, part: .item, occurrence: occurrence, now: now),
                       .object(["done": .bool(true), "completedAt": .string("2026-10-15T17:05:00.000Z"), "snoozedUntil": .null]))
        XCTAssertEqual(ReminderChange.donePatch(for: oneTime, part: .alert(ruleId: "a1"), occurrence: occurrence, now: now),
                       ReminderChange.donePatch(for: oneTime, part: .item, occurrence: occurrence, now: now), "Done on an early alert completes the event")

        let daily: JSONValue = .object(["title": .string("Pills"), "at": .string("2026-10-01T17:00:00.000Z"), "repeat": .object(["every": .string("day")]), "doneThrough": .string("2026-10-13T17:00:00.000Z")])
        XCTAssertEqual(ReminderChange.donePatch(for: daily, part: .item, occurrence: occurrence, now: now),
                       .object(["lastDoneAt": .string("2026-10-15T17:05:00.000Z"), "doneThrough": .string("2026-10-15T17:00:00.000Z"), "snoozedUntil": .null]))
        // doneThrough never moves back; without an occurrence only lastDoneAt moves.
        XCTAssertEqual(ReminderChange.donePatch(for: daily, part: .item, occurrence: date("2026-10-10T17:00:00.000Z"), now: now)["doneThrough"], .string("2026-10-13T17:00:00.000Z"))
        XCTAssertNil(ReminderChange.donePatch(for: daily, part: .item, occurrence: nil, now: now)["doneThrough"])
        XCTAssertEqual(ReminderChange.donePatch(for: daily, part: .slot(time: "12:00"), occurrence: occurrence, now: now),
                       .object(["slotsDone": .object(["12:00": .string("2026-10-15T17:05:00.000Z")]), "snoozedUntil": .null]))
        XCTAssertEqual(ReminderChange.snoozePatch(until: now), .object(["snoozedUntil": .string("2026-10-15T17:05:00.000Z")]))
    }

    func testTheNotificationDoneGoesThroughTheWriterAndKeepsTheSidekicksFields() async throws {
        let store = try makeGatedStore()
        let now = date("2026-10-15T17:05:00.000Z")
        let calendar = ReminderSchedule.phoneCalendar(timeZone: zone)
        func fixedCalendar() -> Calendar { calendar }
        func fixedNow() -> Date { now }
        let engine = NotificationEngine(store: store, booking: SilentBooking(), stateFileURL: folder.appending(path: "engine.json"), calendarProvider: fixedCalendar, clock: fixedNow)
        try store.set(sidekickId: "reminders", key: "reminder:daily", value: .object([
            "title": .string("Pills"), "at": .string("2026-10-01T17:00:00.000Z"), "repeat": .object(["every": .string("day")]),
            "snoozedUntil": .string("2026-10-15T17:10:00.000Z"), "list": .string("health"), "mine": .object(["kept": .bool(true)]),
        ]))

        await engine.handle(action: .done, for: ReminderIdentity(sidekickId: "reminders", reminderId: "daily"))
        let stored = try XCTUnwrap(store.get(sidekickId: "reminders", key: "reminder:daily"))
        XCTAssertEqual(stored["lastDoneAt"], .string("2026-10-15T17:05:00.000Z"))
        XCTAssertEqual(stored["doneThrough"], .string("2026-10-15T17:00:00.000Z"), "the occurrence that fired is done")
        XCTAssertNil(stored["snoozedUntil"], "the snooze is removed, not set to null")
        XCTAssertEqual(stored["list"], .string("health"))
        XCTAssertEqual(stored["mine"], .object(["kept": .bool(true)]))
        XCTAssertEqual(stored["$type"], .string("reminders.item"))
    }

    func testTheWidgetWritersGoThroughTheWriterAndKeepTheSidekicksFields() throws {
        let store = try makeGatedStore()
        let now = date("2026-10-15T17:05:00.000Z")
        let calendar = ReminderSchedule.phoneCalendar(timeZone: zone)
        try store.set(sidekickId: "reminders", key: "reminder:call", value: .object(["title": .string("Call"), "at": .string("2026-10-15T17:00:00.000Z"), "snoozedUntil": .string("2026-10-15T17:10:00.000Z"), "mine": .string("kept")]))
        try store.set(sidekickId: "water", key: "water:today", value: .object(["glasses": .number(3), "mine": .string("kept")]))

        let remindersWidget = RemindersWidgetPublisher(fileURL: folder.appending(path: "today.json"), store: store, isAvailable: { true }, now: { now }, calendar: { calendar }, reloadWidget: {})
        remindersWidget.tick(reminderId: "call", occurrence: date("2026-10-15T17:00:00.000Z"))
        let call = try XCTUnwrap(store.get(sidekickId: "reminders", key: "reminder:call"))
        XCTAssertEqual(call["done"], .bool(true))
        XCTAssertEqual(call["completedAt"], .string("2026-10-15T17:05:00.000Z"))
        XCTAssertNil(call["snoozedUntil"])
        XCTAssertEqual(call["mine"], .string("kept"))
        XCTAssertEqual(call["$type"], .string("reminders.item"))

        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: "water", name: "Water"), (id: "reminders", name: "Reminders")] }
        let sidekickWidgets = SidekickWidgetPublisher(fileURL: folder.appending(path: "widgets.json"), store: store, sidekicks: listSidekicks, now: { now }, calendar: { calendar }, reloadWidget: {})
        let plus = WidgetTapAction(kind: .increment, sidekickId: "water", key: "water:today", field: "glasses", amount: 2, valueJSON: nil, occurrence: nil)
        XCTAssertTrue(sidekickWidgets.write(plus))
        XCTAssertEqual(store.get(sidekickId: "water", key: "water:today"), .object(["glasses": .number(5), "mine": .string("kept")]))

        // A tap whose result does not fit the record's type is refused: nothing written, tap kept.
        let badNote = WidgetTapAction(kind: .set, sidekickId: "reminders", key: "reminder:call", field: "title", amount: nil, valueJSON: "\"\"", occurrence: nil)
        XCTAssertTrue(sidekickWidgets.write(badNote), "a protected key is skipped, never written")
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:call")?["title"], .string("Call"))
    }

    func testTheImportWritesTheOutcomeAsAPatchAndKeepsThePagesFields() async throws {
        let store = try makeGatedStore()
        let center = AppleRemindersImportCenter(store: store, source: DeniedRemindersSource())
        try store.set(sidekickId: "reminders", key: "request:r1", value: .object(["kind": .string("import.apple-reminders"), "status": .string("pending"), "createdAt": .string("2026-10-15T17:00:00.000Z"), "pageField": .number(7)]))
        center.handleRequestWritten(sidekickId: "reminders", key: "request:r1", value: .object(["kind": .string("import.apple-reminders"), "status": .string("pending")]))
        await center.runShownRequest()
        let request = try XCTUnwrap(store.get(sidekickId: "reminders", key: "request:r1"))
        XCTAssertEqual(request["status"], .string("denied"))
        XCTAssertNotNil(request["finishedAt"])
        XCTAssertEqual(request["pageField"], .number(7))
        XCTAssertEqual(request["createdAt"], .string("2026-10-15T17:00:00.000Z"))
        XCTAssertEqual(request["$type"], .string("midas.request"))
    }
}

/// Reminders access that the person declined.
private struct DeniedRemindersSource: PhoneRemindersSource {
    func requestAccess() async -> Bool { false }
    func readAll() async throws -> (lists: [PhoneReminderList], reminders: [PhoneReminder]) { (lists: [], reminders: []) }
}
