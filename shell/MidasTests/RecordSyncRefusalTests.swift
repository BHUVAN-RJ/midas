import XCTest
@testable import Midas

// Refused ops are never dropped (founder, 2026-10-15; unified data plan, section 5): an op the
// server refuses stays in the outbox with the reason, is counted on the home screen, and is
// tried again on the next sync.

/// Refuses every write whose key starts with "bad:" with a schema-style reason, like /sync/push
/// does; accepts the rest. `acceptsEverything` turns the refusals off (a fixed schema).
private final class RefusingSyncServer: RecordSyncAPI, @unchecked Sendable {
    var storedOpIds: [String] = []
    var pushCalls: [[PendingOp]] = []
    var acceptsEverything = false

    func push(ops: [PendingOp]) async throws -> PushResult {
        pushCalls.append(ops)
        var accepted: [String] = []
        var rejected: [String] = []
        var reasons: [String: String] = [:]
        for op in ops {
            if op.key.hasPrefix("bad:") && !acceptsEverything {
                rejected.append(op.opId)
                reasons[op.opId] = "no record type is declared for \(op.key)"
                continue
            }
            accepted.append(op.opId)
            if !storedOpIds.contains(op.opId) {
                storedOpIds.append(op.opId)
            }
        }
        return PushResult(acceptedOpIds: accepted, rejectedOpIds: rejected, rejectionReasons: reasons)
    }

    func pull(after seq: Int) async throws -> PullPage {
        PullPage(ops: [], lastSeq: seq, more: false)
    }
}

@MainActor
final class RecordSyncRefusalTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory.appending(path: "refusal-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testARefusedOpStaysInTheOutboxWithItsReasonAndSurvivesARestart() async throws {
        let server = RefusingSyncServer()
        let phone = LocalRecordStore(fileURL: fileURL)
        try phone.set(sidekickId: "notes", key: "bad:1", value: .object(["text": .string("refused")]))
        try phone.set(sidekickId: "notes", key: "note:1", value: .object(["text": .string("fine")]))
        let badOpId = phone.pendingOps()[0].opId
        let sync = RecordSync(store: phone, api: server)

        let synced = await sync.syncNow()
        XCTAssertTrue(synced, "a refusal is not a failed sync")
        XCTAssertEqual(server.storedOpIds.count, 1)
        XCTAssertEqual(phone.pendingOpCount, 1, "the refused op stays queued")
        XCTAssertEqual(phone.pendingOps()[0].key, "bad:1")
        XCTAssertEqual(sync.refusals, [badOpId: "no record type is declared for bad:1"])
        XCTAssertEqual(sync.refusedOpCount, 1)
        XCTAssertNotNil(phone.get(sidekickId: "notes", key: "bad:1"), "still on the phone")
        // The sync finished although the refused op is still pending: no endless loop.
        XCTAssertEqual(server.pushCalls.count, 1)

        let reopened = LocalRecordStore(fileURL: fileURL)
        XCTAssertEqual(reopened.pendingOpCount, 1)
        XCTAssertEqual(reopened.refusals, [badOpId: "no record type is declared for bad:1"])
        XCTAssertEqual(RecordSync(store: reopened, api: server).refusedOpCount, 1)
    }

    func testTheNextSyncTriesTheRefusedOpAgainAndClearsItOnceAccepted() async throws {
        let server = RefusingSyncServer()
        let phone = LocalRecordStore(fileURL: fileURL)
        try phone.set(sidekickId: "notes", key: "bad:1", value: .object(["text": .string("refused")]))
        let sync = RecordSync(store: phone, api: server)
        await sync.syncNow()
        XCTAssertEqual(sync.refusedOpCount, 1)

        // Still refused: tried again, still counted, still one push per sync.
        await sync.syncNow()
        XCTAssertEqual(server.pushCalls.count, 2)
        XCTAssertEqual(server.pushCalls[1].map(\.key), ["bad:1"])
        XCTAssertEqual(sync.refusedOpCount, 1)

        // The schema was fixed: accepted, out of the outbox, no longer counted.
        server.acceptsEverything = true
        await sync.syncNow()
        XCTAssertEqual(phone.pendingOpCount, 0)
        XCTAssertEqual(sync.refusals, [:])
        XCTAssertEqual(phone.refusals, [:])
        XCTAssertEqual(server.storedOpIds.count, 1)
    }

    func testTheHomeScreenLineCountsTheRefusedChanges() {
        XCTAssertEqual(HomeCopy.notBackedUp(count: 1), "1 change not backed up")
        XCTAssertEqual(HomeCopy.notBackedUp(count: 3), "3 changes not backed up")
    }
}

final class RecordSyncVersionAndReasonTests: XCTestCase {
    private let origin = URL(string: "https://midas-api-staging.midas-backend.workers.dev")!

    func testThePushCarriesTheSidekickVersionWhenKnown() throws {
        let versioned = PendingOp(opId: "op-1", sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("x")]), deleted: false, clientTime: "t1", sidekickVersion: "20261015T090000000Z-abcdef12")
        let unversioned = PendingOp(opId: "op-2", sidekickId: "notes", key: "note:1", value: .string("hi"), deleted: false, clientTime: "t2")
        let request = try RemoteRecordSyncAPI.pushRequest(platformOrigin: origin, ops: [versioned, unversioned], token: "abc")
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        let sentOps = body["ops"]?.arrayValue ?? []
        XCTAssertEqual(sentOps[0]["sidekickVersion"], .string("20261015T090000000Z-abcdef12"))
        guard case .object(let unversionedFields) = sentOps[1] else {
            return XCTFail("op is not an object")
        }
        XCTAssertNil(unversionedFields["sidekickVersion"])
    }

    func testThePushReplyKeepsEachRefusalReason() throws {
        let pushReply = #"{"accepted":["a"],"rejected":[{"opId":"c","error":"reminders.item.title must not be empty"},{"opId":"d"},{"opId":null,"error":"op must be an object"}]}"#
        let result = try RemoteRecordSyncAPI.pushResult(from: Data(pushReply.utf8))
        XCTAssertEqual(result.acceptedOpIds, ["a"])
        XCTAssertEqual(result.rejectedOpIds, ["c", "d"])
        XCTAssertEqual(result.rejectionReasons, ["c": "reminders.item.title must not be empty", "d": "refused by the server"])
        XCTAssertEqual(RecordSync.reasons(for: result), ["c": "reminders.item.title must not be empty", "d": "refused by the server"])
    }
}
