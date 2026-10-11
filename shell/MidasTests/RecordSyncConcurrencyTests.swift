import XCTest
@testable import Midas

/// A server that answers after a short delay and counts calls, so two syncs can overlap.
private final class SlowSyncServer: RecordSyncAPI, @unchecked Sendable {
    var pushCount = 0
    var pullCount = 0
    var storedCount = 0

    func push(ops: [PendingOp]) async throws -> PushResult {
        pushCount += 1
        try await Task.sleep(for: .milliseconds(200))
        storedCount += ops.count
        var acceptedOpIds: [String] = []
        for op in ops {
            acceptedOpIds.append(op.opId)
        }
        return PushResult(acceptedOpIds: acceptedOpIds, rejectedOpIds: [])
    }

    func pull(after seq: Int) async throws -> PullPage {
        pullCount += 1
        try await Task.sleep(for: .milliseconds(200))
        return PullPage(ops: [], lastSeq: seq, more: false)
    }
}

@MainActor
final class RecordSyncConcurrencyTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory.appending(path: "overlap-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // On launch the foreground sync and the restore screen start together; the second must get
    // the first one's result, not a failure.
    func testASyncStartedDuringAnotherGetsItsResult() async throws {
        let server = SlowSyncServer()
        let store = LocalRecordStore(fileURL: fileURL)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .string("a"))
        let sync = RecordSync(store: store, api: server)

        async let launchSync = sync.syncNow()
        async let restore = sync.completeInitialSync()
        let (launchFinished, restored) = await (launchSync, restore)

        XCTAssertTrue(launchFinished)
        XCTAssertTrue(restored)
        XCTAssertFalse(sync.lastSyncFailed)
        XCTAssertEqual(server.pushCount, 1)
        XCTAssertEqual(server.storedCount, 1)
        XCTAssertTrue(store.hasCompletedInitialPull)
    }

    // A write that lands while the pull is running goes up in the same sync.
    func testAWriteDuringThePullIsPushedBeforeTheSyncEnds() async throws {
        let server = SlowSyncServer()
        let store = LocalRecordStore(fileURL: fileURL)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .string("a"))
        let sync = RecordSync(store: store, api: server)

        let running = Task { @MainActor in
            await sync.syncNow()
        }
        // The push takes 200 ms; write once the pull has started.
        try await Task.sleep(for: .milliseconds(300))
        try store.set(sidekickId: "reminders", key: "reminder:2", value: .string("b"))
        let finished = await running.value

        XCTAssertTrue(finished)
        XCTAssertEqual(store.pendingOpCount, 0)
        XCTAssertEqual(server.storedCount, 2)
    }
}
