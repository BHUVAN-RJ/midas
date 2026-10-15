import XCTest
@testable import Midas

// Every write on the phone passes the store's write gate: $type stamped, the record checked
// against its Sidekick's manifest types (or the shell's own types), refused with the reason
// when it does not fit (unified data plan, section 5). The same gate serves the page channel
// and the native writers, so it sits on the store itself.

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
            ]),
        ]),
    ]),
])

@MainActor
final class RecordTypeGateTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory.appending(path: "gate-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    /// A store whose gate knows the reminders types and nothing for any other Sidekick, and
    /// whose ops carry version "v7" for reminders.
    private func makeGatedStore() throws -> LocalRecordStore {
        let engine = try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
        let store = LocalRecordStore(fileURL: fileURL)
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: Self.typesFor)
        store.sidekickVersionProvider = Self.versionFor
        return store
    }

    private static func typesFor(sidekickId: String) -> JSONValue? {
        sidekickId == "reminders" ? remindersTypes : nil
    }

    private static func versionFor(sidekickId: String) -> String? {
        sidekickId == "reminders" ? "v7" : nil
    }

    func testAWriteIsStampedCheckedAndQueuedWithItsVersion() throws {
        let store = try makeGatedStore()
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("Call"), "at": .string("2026-10-15T09:30:00.000Z")]))
        let stored = store.get(sidekickId: "reminders", key: "reminder:1")
        XCTAssertEqual(stored?["$type"], .string("reminders.item"))
        XCTAssertEqual(stored?["title"], .string("Call"))
        let pending = store.pendingOps()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].value?["$type"], .string("reminders.item"))
        XCTAssertEqual(pending[0].sidekickVersion, "v7")

        try store.delete(sidekickId: "reminders", key: "reminder:1")
        XCTAssertEqual(store.pendingOps().last?.sidekickVersion, "v7")
    }

    func testARecordOffItsTypeIsRefusedWithTheReasonAndNothingIsStoredOrQueued() throws {
        let store = try makeGatedStore()
        XCTAssertThrowsError(try store.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("")]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "reminders.item.title must not be empty"))
        }
        XCTAssertThrowsError(try store.set(sidekickId: "reminders", key: "task:1", value: .object(["title": .string("Buy milk")]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "no record type is declared for task:1"))
        }
        XCTAssertThrowsError(try store.set(sidekickId: "reminders", key: "reminder:2", value: .object(["title": .string("x"), "at": .number(1760515200000)]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "reminders.item.at must be a string, not a number"))
        }
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:1"))
        XCTAssertNil(store.get(sidekickId: "reminders", key: "task:1"))
        XCTAssertEqual(store.pendingOpCount, 0)
    }

    func testASidekickWithoutTypesIsStoredAsWrittenAndTheShellTypesStillApply() throws {
        let store = try makeGatedStore()
        try store.set(sidekickId: "notes", key: "note:1", value: .object(["text": .string("hi")]))
        XCTAssertEqual(store.get(sidekickId: "notes", key: "note:1"), .object(["text": .string("hi")]))
        XCTAssertNil(store.pendingOps()[0].sidekickVersion)

        try store.set(sidekickId: "notes", key: "widget:main", value: .object(["name": .string("Notes"), "small": .object([:])]))
        XCTAssertEqual(store.get(sidekickId: "notes", key: "widget:main")?["$type"], .string("midas.widget"))
        XCTAssertThrowsError(try store.set(sidekickId: "notes", key: "widget:bad", value: .object(["small": .object([:])]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "midas.widget.name is required"))
        }
        XCTAssertThrowsError(try store.set(sidekickId: "reminders", key: "request:r1", value: .object(["status": .string("pending")]))) { error in
            XCTAssertEqual(error as? RecordRefusal, RecordRefusal(reason: "midas.request.kind is required"))
        }
    }

    func testTheChannelRefusesWithTheReasonAndStatus400() throws {
        let store = try makeGatedStore()
        let channel = SidekickStoreChannel(store: store)
        let refused = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"set","key":"reminder:1","value":{"title":""}}"#.utf8))
        XCTAssertEqual(refused.statusCode, 400)
        XCTAssertEqual(refused.body["error"], .string("reminders.item.title must not be empty"))
        XCTAssertEqual(store.pendingOpCount, 0)

        let accepted = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"set","key":"reminder:1","value":{"title":"Call"}}"#.utf8))
        XCTAssertEqual(accepted.statusCode, 200)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1")?["$type"], .string("reminders.item"))
    }

    func testUpdateMergesChecksAndRepliesWithTheStoredRecord() throws {
        let store = try makeGatedStore()
        let channel = SidekickStoreChannel(store: store)
        _ = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"set","key":"reminder:1","value":{"title":"Call","at":"2026-10-15T09:30:00.000Z","done":false}}"#.utf8))

        let updated = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"update","key":"reminder:1","patch":{"at":null,"done":true}}"#.utf8))
        XCTAssertEqual(updated.statusCode, 200)
        let stored = store.get(sidekickId: "reminders", key: "reminder:1")
        XCTAssertEqual(stored, .object(["$type": .string("reminders.item"), "title": .string("Call"), "done": .bool(true)]))
        XCTAssertEqual(updated.body["value"], stored)
        XCTAssertEqual(store.pendingOps().count, 2)

        let refused = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"update","key":"reminder:1","patch":{"title":""}}"#.utf8))
        XCTAssertEqual(refused.statusCode, 400)
        XCTAssertEqual(refused.body["error"], .string("reminders.item.title must not be empty"))
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1"), stored)

        let badPatch = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"update","key":"reminder:1","patch":"done"}"#.utf8))
        XCTAssertEqual(badPatch.statusCode, 400)
        XCTAssertEqual(badPatch.body["error"], .string("patch must be an object"))

        // Updating a record that does not exist builds it from the patch, checked like a set.
        let created = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"update","key":"reminder:2","patch":{"title":"New"}}"#.utf8))
        XCTAssertEqual(created.statusCode, 200)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:2")?["$type"], .string("reminders.item"))
        let missingTitle = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"update","key":"reminder:3","patch":{"done":true}}"#.utf8))
        XCTAssertEqual(missingTitle.body["error"], .string("reminders.item.title is required"))
    }

    func testTheReservedReminderCheckStillRunsOnUpdate() throws {
        let store = LocalRecordStore(fileURL: fileURL)
        let validators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        let channel = SidekickStoreChannel(store: store, reservedValidators: validators)
        _ = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"set","key":"reminder:1","value":{"title":"Call","at":"2026-10-15T09:30:00.000Z"}}"#.utf8))
        let refused = channel.handle(sidekickId: "reminders", requestBody: Data(#"{"op":"update","key":"reminder:1","patch":{"at":null}}"#.utf8))
        XCTAssertEqual(refused.statusCode, 400)
        XCTAssertEqual(refused.body["error"], .string("reminder.at must be an ISO 8601 date or epoch milliseconds"))
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1")?["at"], .string("2026-10-15T09:30:00.000Z"))
    }
}
