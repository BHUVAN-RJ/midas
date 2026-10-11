import XCTest
@testable import Midas

/// An in-memory stand-in for POST /sync/push and GET /sync/pull with the backend's rules: ops
/// get increasing seq in the order pushed, an op_id already stored is skipped, values over the
/// limit are rejected, pulls page.
private final class FakeSyncServer: RecordSyncAPI, @unchecked Sendable {
    struct StoredOp {
        let seq: Int
        let op: PendingOp
    }

    var storedOps: [StoredOp] = []
    var pushCalls: [[PendingOp]] = []
    var pageSize = 1000
    var isOffline = false
    /// Stores the push but fails the reply, like a connection dropped after the server saved it.
    var dropNextPushReply = false

    func push(ops: [PendingOp]) async throws -> PushResult {
        if isOffline {
            throw URLError(.notConnectedToInternet)
        }
        pushCalls.append(ops)
        var accepted: [String] = []
        var rejected: [String] = []
        for op in ops {
            if RecordSync.valueByteCount(op.value) > 64 * 1024 {
                rejected.append(op.opId)
                continue
            }
            accepted.append(op.opId)
            if !storedOpIds().contains(op.opId) {
                storedOps.append(StoredOp(seq: storedOps.count + 1, op: op))
            }
        }
        if dropNextPushReply {
            dropNextPushReply = false
            throw URLError(.networkConnectionLost)
        }
        return PushResult(acceptedOpIds: accepted, rejectedOpIds: rejected)
    }

    func pull(after seq: Int) async throws -> PullPage {
        if isOffline {
            throw URLError(.notConnectedToInternet)
        }
        var later: [RemoteOp] = []
        for stored in storedOps where stored.seq > seq {
            let op = stored.op
            later.append(RemoteOp(seq: stored.seq, opId: op.opId, sidekickId: op.sidekickId, key: op.key, value: op.deleted ? nil : (op.value ?? .null), deleted: op.deleted))
        }
        let page = Array(later.prefix(pageSize))
        let lastSeq = page.last?.seq ?? seq
        return PullPage(ops: page, lastSeq: lastSeq, more: later.count > pageSize)
    }

    func storedOpIds() -> [String] {
        var opIds: [String] = []
        for stored in storedOps {
            opIds.append(stored.op.opId)
        }
        return opIds
    }
}

private let dentistReminder: JSONValue = .object([
    "at": .string("2026-10-14T16:30:00.000Z"),
    "title": .string("Dentist"),
    "body": .string("Bring the insurance card"),
    "repeat": .object(["every": .string("week"), "interval": .number(2), "weekdays": .array([.number(1), .number(3)])]),
    "timeZone": .string("America/New_York"),
    "snoozedUntil": .string("2026-10-14T16:40:00.000Z"),
    "list": .string("Health"),
])

@MainActor
final class LocalRecordStoreOutboxTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testEverySetAndDeleteIsQueuedInOrderAndSurvivesARestart() throws {
        let store = LocalRecordStore(fileURL: fileURL)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .string("a"))
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .string("b"))
        try store.delete(sidekickId: "reminders", key: "reminder:1")
        try store.delete(sidekickId: "reminders", key: "reminder:never")

        let reopened = LocalRecordStore(fileURL: fileURL)
        let pending = reopened.pendingOps()
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(pending[0].value, .string("a"))
        XCTAssertEqual(pending[1].value, .string("b"))
        XCTAssertTrue(pending[2].deleted)
        XCTAssertNil(pending[2].value)
        XCTAssertEqual(Set(pending.map(\.opId)).count, 3)
    }

    func testAFileFromBeforeSyncKeepsItsRecordsAndQueuesThemForUpload() throws {
        let oldFormat = #"{"reminders":{"reminder:1":{"title":"Old","at":"2026-10-12T09:00:00.000Z"}},"notes":{"note:a":"hi"}}"#
        try Data(oldFormat.utf8).write(to: fileURL)

        let store = LocalRecordStore(fileURL: fileURL)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1")?["title"]?.stringValue, "Old")
        XCTAssertEqual(store.get(sidekickId: "notes", key: "note:a"), .string("hi"))
        XCTAssertFalse(store.hasCompletedInitialPull)
        let queuedKeys = store.pendingOps().map(\.key)
        XCTAssertEqual(queuedKeys, ["note:a", "reminder:1"])
    }

    func testPulledOpsApplyInOrderWithoutBeingQueuedAgain() throws {
        let store = LocalRecordStore(fileURL: fileURL)
        var heard: [LocalRecordChange] = []
        func hear(_ change: LocalRecordChange) {
            heard.append(change)
        }
        store.addChangeObserver(hear)
        let ops = [
            RemoteOp(seq: 1, opId: "o1", sidekickId: "reminders", key: "reminder:1", value: .string("first"), deleted: false),
            RemoteOp(seq: 2, opId: "o2", sidekickId: "reminders", key: "reminder:1", value: .string("second"), deleted: false),
            RemoteOp(seq: 3, opId: "o3", sidekickId: "reminders", key: "reminder:2", value: .string("gone"), deleted: false),
            RemoteOp(seq: 4, opId: "o4", sidekickId: "reminders", key: "reminder:2", value: nil, deleted: true),
        ]
        try store.applyRemote(ops: ops, lastSeq: 4)

        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1"), .string("second"))
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:2"))
        XCTAssertEqual(store.pendingOpCount, 0)
        XCTAssertEqual(store.lastPulledSeq, 4)
        XCTAssertEqual(heard, [LocalRecordChange(sidekickId: "reminders", key: "reminder:1"), LocalRecordChange(sidekickId: "reminders", key: "reminder:2")])
        XCTAssertEqual(LocalRecordStore(fileURL: fileURL).lastPulledSeq, 4)
    }

    func testAnUnsentLocalChangeIsNotOverwrittenByAPull() throws {
        let store = LocalRecordStore(fileURL: fileURL)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .string("mine, not sent yet"))
        let olderRemote = RemoteOp(seq: 7, opId: "o7", sidekickId: "reminders", key: "reminder:1", value: .string("from another phone"), deleted: false)
        try store.applyRemote(ops: [olderRemote], lastSeq: 7)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:1"), .string("mine, not sent yet"))
        XCTAssertEqual(store.lastPulledSeq, 7)
    }

    func testDefaultFilesArePerServerAndLiveKeepsTheOldName() {
        let liveURL = LocalRecordStore.defaultFileURL(platformOrigin: PlatformConfig.origin(forHost: PlatformConfig.liveHost))
        let stagingURL = LocalRecordStore.defaultFileURL(platformOrigin: PlatformConfig.origin(forHost: PlatformConfig.stagingHost))
        XCTAssertEqual(liveURL.lastPathComponent, "midas-local-records.json")
        XCTAssertNotEqual(liveURL, stagingURL)
    }
}

@MainActor
final class RecordSyncTests: XCTestCase {
    private var fileURLs: [URL] = []

    private func newStore() -> LocalRecordStore {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "sync-\(UUID().uuidString).json")
        fileURLs.append(fileURL)
        return LocalRecordStore(fileURL: fileURL)
    }

    override func tearDown() async throws {
        for fileURL in fileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // The done-when line: delete the app, reinstall, sign in, and every record is back.
    func testAReinstallGetsEveryRecordBack() async throws {
        let server = FakeSyncServer()
        let phone = newStore()
        try phone.set(sidekickId: "reminders", key: "reminder:dentist", value: dentistReminder)
        try phone.set(sidekickId: "reminders", key: "reminder:laundry", value: .object(["at": .string("2026-10-14T18:00:00.000Z"), "title": .string("Laundry")]))
        try phone.set(sidekickId: "birthdays", key: "birthday:sam", value: .object(["name": .string("Sam")]))
        try phone.set(sidekickId: "notes", key: "note:empty", value: .null)
        try phone.delete(sidekickId: "reminders", key: "reminder:laundry")
        let phoneSync = RecordSync(store: phone, api: server)
        let phoneSynced = await phoneSync.syncNow()
        XCTAssertTrue(phoneSynced)
        XCTAssertEqual(phone.pendingOpCount, 0)

        let reinstalled = newStore()
        let reinstalledSync = RecordSync(store: reinstalled, api: server)
        let restored = await reinstalledSync.completeInitialSync()
        XCTAssertTrue(restored)
        XCTAssertTrue(reinstalled.hasCompletedInitialPull)
        XCTAssertEqual(reinstalled.queryAllSidekicks(keyPrefix: ""), phone.queryAllSidekicks(keyPrefix: ""))
        XCTAssertEqual(reinstalled.get(sidekickId: "reminders", key: "reminder:dentist"), dentistReminder)
        XCTAssertEqual(reinstalled.get(sidekickId: "notes", key: "note:empty"), .null)
        XCTAssertNil(reinstalled.get(sidekickId: "reminders", key: "reminder:laundry"))
        XCTAssertEqual(reinstalled.pendingOpCount, 0)
    }

    func testOfflineKeepsEverythingQueuedAndTheFirstRestoreWaits() async throws {
        let server = FakeSyncServer()
        server.isOffline = true
        let phone = newStore()
        try phone.set(sidekickId: "reminders", key: "reminder:1", value: .string("kept"))
        let sync = RecordSync(store: phone, api: server)

        let restored = await sync.completeInitialSync()
        XCTAssertFalse(restored)
        XCTAssertTrue(sync.lastSyncFailed)
        XCTAssertFalse(phone.hasCompletedInitialPull)
        XCTAssertEqual(phone.pendingOpCount, 1)
        XCTAssertEqual(phone.get(sidekickId: "reminders", key: "reminder:1"), .string("kept"))

        server.isOffline = false
        let restoredLater = await sync.completeInitialSync()
        XCTAssertTrue(restoredLater)
        XCTAssertEqual(server.storedOps.count, 1)
        XCTAssertEqual(phone.pendingOpCount, 0)
    }

    func testAPushWhoseReplyWasLostIsResentAndStoredOnce() async throws {
        let server = FakeSyncServer()
        server.dropNextPushReply = true
        let phone = newStore()
        try phone.set(sidekickId: "reminders", key: "reminder:1", value: .string("once"))
        let sync = RecordSync(store: phone, api: server)

        let firstTry = await sync.syncNow()
        XCTAssertFalse(firstTry)
        XCTAssertEqual(phone.pendingOpCount, 1)
        let secondTry = await sync.syncNow()
        XCTAssertTrue(secondTry)
        XCTAssertEqual(server.pushCalls.count, 2)
        XCTAssertEqual(server.storedOps.count, 1)
    }

    func testLargeOutboxesGoUpInBatchesInWriteOrder() async throws {
        let server = FakeSyncServer()
        server.pageSize = 40
        let phone = newStore()
        for index in 0..<250 {
            try phone.set(sidekickId: "notes", key: "note:\(index)", value: .number(Double(index)))
        }
        let writtenOpIds = phone.pendingOps().map(\.opId)
        let sync = RecordSync(store: phone, api: server)
        let synced = await sync.syncNow()
        XCTAssertTrue(synced)

        let batchSizes = server.pushCalls.map(\.count)
        XCTAssertEqual(batchSizes, [100, 100, 50])
        XCTAssertEqual(server.storedOpIds(), writtenOpIds)
        XCTAssertEqual(phone.lastPulledSeq, 250)
    }

    func testBatchesStayUnderTheByteLimit() {
        let bigValue = JSONValue.string(String(repeating: "x", count: 60 * 1024))
        var ops: [PendingOp] = []
        for index in 0..<30 {
            ops.append(PendingOp(opId: "op-\(index)", sidekickId: "notes", key: "note:\(index)", value: bigValue, deleted: false, clientTime: "t"))
        }
        let batch = RecordSync.nextBatch(from: ops)
        XCTAssertEqual(batch.count, 14)
        XCTAssertEqual(batch.first?.opId, "op-0")

        let oneHuge = [PendingOp(opId: "huge", sidekickId: "notes", key: "k", value: .string(String(repeating: "x", count: 2_000_000)), deleted: false, clientTime: "t")]
        XCTAssertEqual(RecordSync.nextBatch(from: oneHuge).count, 1)
    }

    func testAnOpTheServerRefusesForGoodLeavesTheOutbox() async throws {
        let server = FakeSyncServer()
        let phone = newStore()
        try phone.set(sidekickId: "notes", key: "note:huge", value: .string(String(repeating: "x", count: 70 * 1024)))
        try phone.set(sidekickId: "notes", key: "note:ok", value: .string("fine"))
        let sync = RecordSync(store: phone, api: server)
        let synced = await sync.syncNow()
        XCTAssertTrue(synced)
        XCTAssertEqual(phone.pendingOpCount, 0)
        XCTAssertEqual(server.storedOps.count, 1)
        // Still on the phone.
        XCTAssertNotNil(phone.get(sidekickId: "notes", key: "note:huge"))
    }

    func testAChangeFromAnotherPhoneArrivesAndWinsByOrder() async throws {
        let server = FakeSyncServer()
        let firstPhone = newStore()
        let secondPhone = newStore()
        let firstSync = RecordSync(store: firstPhone, api: server)
        let secondSync = RecordSync(store: secondPhone, api: server)

        try firstPhone.set(sidekickId: "reminders", key: "reminder:1", value: .string("v1"))
        await firstSync.syncNow()
        await secondSync.syncNow()
        try secondPhone.set(sidekickId: "reminders", key: "reminder:1", value: .string("v2"))
        await secondSync.syncNow()
        await firstSync.syncNow()

        XCTAssertEqual(firstPhone.get(sidekickId: "reminders", key: "reminder:1"), .string("v2"))
        XCTAssertEqual(secondPhone.get(sidekickId: "reminders", key: "reminder:1"), .string("v2"))
    }

    func testAWriteTriggersASyncShortlyAfter() async throws {
        let server = FakeSyncServer()
        let phone = newStore()
        let sync = RecordSync(store: phone, api: server)
        sync.startSyncingAfterWrites()
        try phone.set(sidekickId: "reminders", key: "reminder:1", value: .string("a"))
        try phone.set(sidekickId: "reminders", key: "reminder:2", value: .string("b"))

        let deadline = Date().addingTimeInterval(5)
        while phone.pendingOpCount > 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(phone.pendingOpCount, 0)
        // The two writes went up together.
        XCTAssertEqual(server.pushCalls.map(\.count), [2])
    }
}

final class RemoteRecordSyncAPITests: XCTestCase {
    private let origin = URL(string: "https://midas-api-staging.midas-backend.workers.dev")!

    func testPushRequestCarriesSessionAndOpsAsTheBackendExpects() throws {
        let ops = [
            PendingOp(opId: "op-1", sidekickId: "reminders", key: "reminder:1", value: dentistReminder, deleted: false, clientTime: "t1"),
            PendingOp(opId: "op-2", sidekickId: "notes", key: "note:n", value: nil, deleted: false, clientTime: "t2"),
            PendingOp(opId: "op-3", sidekickId: "reminders", key: "reminder:1", value: nil, deleted: true, clientTime: "t3"),
        ]
        let request = try RemoteRecordSyncAPI.pushRequest(platformOrigin: origin, ops: ops, token: "abc")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api-staging.midas-backend.workers.dev/sync/push")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")

        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        let sentOps = body["ops"]?.arrayValue ?? []
        XCTAssertEqual(sentOps.count, 3)
        XCTAssertEqual(sentOps[0]["value"], dentistReminder)
        XCTAssertEqual(sentOps[0]["deleted"], .bool(false))
        // A write of null still sends "value": null; a delete sends no value.
        XCTAssertEqual(sentOps[1]["value"], .null)
        guard case .object(let deleteFields) = sentOps[2] else {
            return XCTFail("op is not an object")
        }
        XCTAssertNil(deleteFields["value"])
        XCTAssertEqual(deleteFields["deleted"], .bool(true))
    }

    func testPullRequestAndReplies() throws {
        let request = RemoteRecordSyncAPI.pullRequest(platformOrigin: origin, after: 42, token: "abc")
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api-staging.midas-backend.workers.dev/sync/pull?after=42")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")

        let pullReply = #"{"ops":[{"seq":43,"opId":"o","sidekickId":"reminders","key":"reminder:1","value":{"title":"x"},"deleted":false,"clientTime":null},{"seq":44,"opId":"p","sidekickId":"notes","key":"n","value":null,"deleted":false,"clientTime":null},{"seq":45,"opId":"q","sidekickId":"notes","key":"m","value":null,"deleted":true,"clientTime":null}],"lastSeq":45,"more":false}"#
        let page = try RemoteRecordSyncAPI.pullPage(from: Data(pullReply.utf8))
        XCTAssertEqual(page.lastSeq, 45)
        XCTAssertEqual(page.ops[0].value, .object(["title": .string("x")]))
        XCTAssertEqual(page.ops[1].value, .null)
        XCTAssertNil(page.ops[2].value)
        XCTAssertTrue(page.ops[2].deleted)

        let pushReply = #"{"accepted":["a","b"],"rejected":[{"opId":"c","error":"too big"},{"opId":null,"error":"op must be an object"}]}"#
        let result = try RemoteRecordSyncAPI.pushResult(from: Data(pushReply.utf8))
        XCTAssertEqual(result, PushResult(acceptedOpIds: ["a", "b"], rejectedOpIds: ["c"]))
        XCTAssertThrowsError(try RemoteRecordSyncAPI.pushResult(from: Data("{}".utf8)))
    }
}

@MainActor
final class StoreChannelSizeLimitTests: XCTestCase {
    func testAValueTooLargeToBackUpIsRefusedAtWriteTime() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "limit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = LocalRecordStore(fileURL: fileURL)
        let channel = SidekickStoreChannel(store: store)

        let tooBig = String(repeating: "x", count: 64 * 1024)
        let tooBigRequest = try JSONEncoder().encode(JSONValue.object(["op": .string("set"), "key": .string("note:big"), "value": .string(tooBig)]))
        let refused = channel.handle(sidekickId: "notes", requestBody: tooBigRequest)
        XCTAssertEqual(refused.statusCode, 400)
        XCTAssertNil(store.get(sidekickId: "notes", key: "note:big"))
        XCTAssertEqual(store.pendingOpCount, 0)

        let fits = String(repeating: "x", count: 60 * 1024)
        let fitsRequest = try JSONEncoder().encode(JSONValue.object(["op": .string("set"), "key": .string("note:ok"), "value": .string(fits)]))
        XCTAssertEqual(channel.handle(sidekickId: "notes", requestBody: fitsRequest).statusCode, 200)
    }
}
