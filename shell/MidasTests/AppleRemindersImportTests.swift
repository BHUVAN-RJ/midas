import EventKit
import XCTest
@testable import Midas

/// Fake Reminders on the phone: grants or refuses access and returns fixed data.
@MainActor
private final class FakeRemindersSource: PhoneRemindersSource {
    var grantsAccess = true
    var lists: [PhoneReminderList] = []
    var reminders: [PhoneReminder] = []
    var accessRequests = 0
    var reads = 0

    func requestAccess() async -> Bool {
        accessRequests += 1
        return grantsAccess
    }

    func readAll() async throws -> (lists: [PhoneReminderList], reminders: [PhoneReminder]) {
        reads += 1
        return (lists, reminders)
    }
}

/// Native import of Apple Reminders (founder, 2026-10-10): request records, the export's shape,
/// parts under the 64 KB record cap, and results going only to the Sidekick that asked.
@MainActor
final class AppleRemindersImportTests: XCTestCase {
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        storeFileURL = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    // MARK: Export shape (same keys the page reads from the Mac export)

    func testReminderJSONHasTheMacExportFields() {
        let reminder = makeReminder(index: 1)

        let value = AppleRemindersExport.reminderJSON(reminder)

        guard case .object(let fields) = value else {
            return XCTFail("not an object")
        }
        let expectedKeys: Set<String> = ["id", "externalId", "listId", "title", "notes", "url", "completed", "completionDate", "creationDate", "lastModifiedDate", "priority", "due", "alarms", "recurrence"]
        XCTAssertEqual(Set(fields.keys), expectedKeys)
        XCTAssertEqual(value["externalId"]?.stringValue, "external-1")
        XCTAssertEqual(value["due"]?["date"]?.stringValue, "2026-10-12")
        XCTAssertEqual(value["due"]?["time"]?.stringValue, "09:30")
        XCTAssertEqual(value["recurrence"]?.arrayValue?.first?["frequency"]?.stringValue, "weekly")
        XCTAssertEqual(value["recurrence"]?.arrayValue?.first?["daysOfWeek"]?.arrayValue?.first?["weekday"]?.numberValue, 2)
    }

    func testAllDayDueHasNoTimeOrInstant() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7

        let due = EventKitReminderConversion.due(from: components)

        XCTAssertEqual(due, PhoneReminderDue(allDay: true, date: "2026-03-07", time: nil, timeZone: nil, instant: nil))
    }

    func testTimedDueKeepsItsZoneAndInstant() throws {
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 23
        components.hour = 4
        components.minute = 0
        components.timeZone = TimeZone(identifier: "Asia/Kolkata")

        let due = try XCTUnwrap(EventKitReminderConversion.due(from: components))

        XCTAssertFalse(due.allDay)
        XCTAssertEqual(due.time, "04:00")
        XCTAssertEqual(due.timeZone, "Asia/Kolkata")
        let instant = try XCTUnwrap(due.instant.flatMap(ISO8601DateFormatter().date(from:)))
        // 04:00 in Kolkata (UTC+5:30) is 22:30 UTC the day before
        XCTAssertEqual(instant.timeIntervalSince1970, 1_711_146_600, accuracy: 0.5)
    }

    func testWeeklyRuleOnChosenDaysIsConverted() {
        let monday = EKRecurrenceDayOfWeek(.monday)
        let wednesday = EKRecurrenceDayOfWeek(.wednesday)
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, daysOfTheWeek: [monday, wednesday], daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: EKRecurrenceEnd(occurrenceCount: 5))

        let converted = EventKitReminderConversion.recurrenceRule(from: rule, formatter: ISO8601DateFormatter.deviceZone)

        XCTAssertEqual(converted.frequency, "weekly")
        XCTAssertEqual(converted.interval, 2)
        XCTAssertEqual(converted.daysOfWeek, [PhoneRecurrenceDay(weekday: 2, weekNumber: 0), PhoneRecurrenceDay(weekday: 4, weekNumber: 0)])
        XCTAssertEqual(converted.endOccurrenceCount, 5)
        XCTAssertNil(converted.endDate)
    }

    func testRelativeAlarmKeepsItsOffset() {
        let alarm = EKAlarm(relativeOffset: -900)

        let converted = EventKitReminderConversion.alarm(from: alarm, formatter: ISO8601DateFormatter.deviceZone)

        XCTAssertEqual(converted, PhoneReminderAlarm(absoluteDate: nil, relativeOffsetSeconds: -900))
    }

    // MARK: Parts under the record cap

    func testLargeImportIsSplitIntoPartsUnderTheRecordCap() {
        var reminders: [PhoneReminder] = []
        for index in 0..<1500 {
            reminders.append(makeReminder(index: index))
        }
        let lists = [PhoneReminderList(id: "list-a", title: "Reminders", colorHex: "#FF9500")]

        let parts = AppleRemindersExport.parts(lists: lists, reminders: reminders, exportedAt: "2026-10-10T21:00:00-07:00", timeZone: "America/Los_Angeles")

        XCTAssertGreaterThan(parts.count, 1)
        var externalIds: [String] = []
        for (index, part) in parts.enumerated() {
            XCTAssertLessThanOrEqual(RecordSync.valueByteCount(part), SidekickStoreChannel.maxValueBytes)
            XCTAssertEqual(part["part"]?.numberValue, Double(index))
            XCTAssertEqual(part["parts"]?.numberValue, Double(parts.count))
            XCTAssertEqual(part["source"]?.stringValue, "apple-reminders")
            XCTAssertEqual(part["origin"]?.stringValue, "iphone")
            let partListCount = part["lists"]?.arrayValue?.count
            XCTAssertEqual(partListCount, index == 0 ? 1 : 0)
            for reminderValue in part["reminders"]?.arrayValue ?? [] {
                externalIds.append(reminderValue["externalId"]?.stringValue ?? "")
            }
        }
        var expectedIds: [String] = []
        for index in 0..<1500 {
            expectedIds.append("external-\(index)")
        }
        XCTAssertEqual(externalIds, expectedIds)
    }

    func testHugeNotesStillFitInOnePart() {
        let longNotes = String(repeating: "n", count: 200_000)
        let reminder = makeReminder(index: 1, notes: longNotes)

        let parts = AppleRemindersExport.parts(lists: [], reminders: [reminder], exportedAt: "2026-10-10T21:00:00-07:00", timeZone: "UTC")

        XCTAssertEqual(parts.count, 1)
        XCTAssertLessThanOrEqual(RecordSync.valueByteCount(parts[0]), SidekickStoreChannel.maxValueBytes)
    }

    // MARK: Requests

    func testRequestWrittenThroughTheChannelShowsTheSheetForThatSidekick() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let center = AppleRemindersImportCenter(store: store, source: FakeRemindersSource())
        let channel = SidekickStoreChannel(store: store)
        channel.requestObserver = center.handleRequestWritten

        let reply = channel.handle(sidekickId: "reminders", requestBody: try requestBody(key: "request:r1", kind: ShellRequests.importAppleRemindersKind))

        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertEqual(center.shownRequest, AppleRemindersImportRequest(sidekickId: "reminders", requestKey: "request:r1"))
    }

    func testOrdinaryRecordsDoNotReachTheRequestObserver() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let center = AppleRemindersImportCenter(store: store, source: FakeRemindersSource())
        let channel = SidekickStoreChannel(store: store)
        channel.requestObserver = center.handleRequestWritten

        _ = channel.handle(sidekickId: "reminders", requestBody: try requestBody(key: "task:r1", kind: ShellRequests.importAppleRemindersKind))

        XCTAssertNil(center.shownRequest)
    }

    func testAllowedImportWritesPartsOnlyToTheAskingSidekick() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let source = FakeRemindersSource()
        source.lists = [PhoneReminderList(id: "list-a", title: "Reminders", colorHex: "#FF9500")]
        source.reminders = [makeReminder(index: 1), makeReminder(index: 2)]
        let center = AppleRemindersImportCenter(store: store, source: source)
        try store.set(sidekickId: "reminders", key: "request:r1", value: pendingRequestValue())
        center.handleRequestWritten(sidekickId: "reminders", key: "request:r1", value: pendingRequestValue())

        await center.runShownRequest()

        let request = try XCTUnwrap(store.get(sidekickId: "reminders", key: "request:r1"))
        XCTAssertEqual(request["status"]?.stringValue, "done")
        XCTAssertEqual(request["parts"]?.numberValue, 1)
        XCTAssertEqual(request["prefix"]?.stringValue, "import:r1:")
        XCTAssertEqual(request["reminders"]?.numberValue, 2)
        XCTAssertEqual(request["kind"]?.stringValue, ShellRequests.importAppleRemindersKind)
        let parts = store.query(sidekickId: "reminders", keyPrefix: "import:r1:")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.key, "import:r1:0000")
        XCTAssertEqual(parts.first?.value["reminders"]?.arrayValue?.count, 2)
        let otherSidekickRecords = store.queryAllSidekicks(keyPrefix: "import:")
        for record in otherSidekickRecords {
            XCTAssertEqual(record.sidekickId, "reminders")
        }
        XCTAssertNil(center.shownRequest)
    }

    func testRefusedAccessMarksTheRequestDeniedAndReadsNothing() async throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let source = FakeRemindersSource()
        source.grantsAccess = false
        source.reminders = [makeReminder(index: 1)]
        let center = AppleRemindersImportCenter(store: store, source: source)
        center.handleRequestWritten(sidekickId: "reminders", key: "request:r1", value: pendingRequestValue())

        await center.runShownRequest()

        XCTAssertEqual(store.get(sidekickId: "reminders", key: "request:r1")?["status"]?.stringValue, "denied")
        XCTAssertEqual(source.reads, 0)
        XCTAssertTrue(store.query(sidekickId: "reminders", keyPrefix: "import:").isEmpty)
    }

    func testNotNowMarksTheRequestCancelledWithoutAskingIOS() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let source = FakeRemindersSource()
        let center = AppleRemindersImportCenter(store: store, source: source)
        center.handleRequestWritten(sidekickId: "reminders", key: "request:r1", value: pendingRequestValue())

        center.cancelShownRequest()

        XCTAssertEqual(store.get(sidekickId: "reminders", key: "request:r1")?["status"]?.stringValue, "cancelled")
        XCTAssertEqual(source.accessRequests, 0)
        XCTAssertNil(center.shownRequest)
    }

    func testUnknownRequestKindFailsWithoutShowingTheSheet() {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let center = AppleRemindersImportCenter(store: store, source: FakeRemindersSource())
        let unknownRequest = JSONValue.object(["kind": .string("camera.photo"), "status": .string("pending")])

        center.handleRequestWritten(sidekickId: "reminders", key: "request:r2", value: unknownRequest)

        XCTAssertNil(center.shownRequest)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "request:r2")?["status"]?.stringValue, "failed")
    }

    func testFinishedRequestIsNotShownAgain() {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let center = AppleRemindersImportCenter(store: store, source: FakeRemindersSource())
        let finishedRequest = JSONValue.object(["kind": .string(ShellRequests.importAppleRemindersKind), "status": .string("done")])

        center.handleRequestWritten(sidekickId: "reminders", key: "request:r1", value: finishedRequest)

        XCTAssertNil(center.shownRequest)
    }

    func testRemindersPermissionTextIsTheFoundersWording() {
        let usageText = Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") as? String
        XCTAssertEqual(usageText, "Midas imports your Apple Reminders lists and reminders into your Reminders Sidekick.")
    }

    // MARK: Helpers

    private func pendingRequestValue() -> JSONValue {
        return .object(["kind": .string(ShellRequests.importAppleRemindersKind), "status": .string("pending")])
    }

    private func requestBody(key: String, kind: String) throws -> Data {
        let request = JSONValue.object([
            "op": .string("set"),
            "key": .string(key),
            "value": .object(["kind": .string(kind), "status": .string("pending")]),
        ])
        return try JSONEncoder().encode(request)
    }

    private func makeReminder(index: Int, notes: String? = "Bring the card") -> PhoneReminder {
        let due = PhoneReminderDue(allDay: false, date: "2026-10-12", time: "09:30", timeZone: "America/Los_Angeles", instant: "2026-10-12T09:30:00-07:00")
        let rule = PhoneRecurrenceRule(frequency: "weekly", interval: 1, daysOfWeek: [PhoneRecurrenceDay(weekday: 2, weekNumber: 0)], daysOfMonth: nil, monthsOfYear: nil, weeksOfYear: nil, daysOfYear: nil, setPositions: nil, endDate: nil, endOccurrenceCount: nil)
        return PhoneReminder(
            id: "local-\(index)",
            externalId: "external-\(index)",
            listId: "list-a",
            title: "Reminder number \(index)",
            notes: notes,
            url: nil,
            completed: false,
            completionDate: nil,
            creationDate: "2026-10-01T08:00:00-07:00",
            lastModifiedDate: "2026-10-02T08:00:00-07:00",
            priority: 0,
            due: due,
            alarms: [PhoneReminderAlarm(absoluteDate: "2026-10-12T09:30:00-07:00", relativeOffsetSeconds: nil)],
            recurrence: [rule]
        )
    }
}
