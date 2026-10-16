import XCTest
@testable import Midas

// A file reaches the server before the record that points to it (unified data plan, section 7:
// "The upload finishes before the record that points to it is pushed (same outbox, ordered)").
// When the upload cannot happen, the record waits with it.

/// Remembers every call in order; can be switched off like a lost connection.
private final class RecordingFileTransfer: FileTransfer, @unchecked Sendable {
    var uploads: [(fileId: String, size: Int, contentType: String)] = []
    var isOffline = false
    var downloads: [String: (data: Data, contentType: String)] = [:]
    /// Every upload and push in the order they happened ("file <id>" / "push <n> ops").
    let timeline: Timeline

    init(timeline: Timeline) {
        self.timeline = timeline
    }

    func upload(fileId: String, data: Data, contentType: String) async throws {
        if isOffline {
            throw URLError(.notConnectedToInternet)
        }
        uploads.append((fileId, data.count, contentType))
        timeline.record("file \(fileId)")
    }

    func download(fileId: String) async throws -> (data: Data, contentType: String)? {
        downloads[fileId]
    }
}

private final class Timeline: @unchecked Sendable {
    var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private final class AcceptingSyncServer: RecordSyncAPI, @unchecked Sendable {
    let timeline: Timeline
    var storedKeys: [String] = []

    init(timeline: Timeline) {
        self.timeline = timeline
    }

    func push(ops: [PendingOp]) async throws -> PushResult {
        timeline.record("push \(ops.count) ops")
        var accepted: [String] = []
        for op in ops {
            accepted.append(op.opId)
            storedKeys.append(op.key)
        }
        return PushResult(acceptedOpIds: accepted, rejectedOpIds: [])
    }

    func pull(after seq: Int) async throws -> PullPage {
        PullPage(ops: [], lastSeq: seq, more: false)
    }
}

@MainActor
final class RecordSyncFilesTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "sync-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testFilesGoUpBeforeTheRecordsThatPointToThem() async throws {
        let timeline = Timeline()
        let transfer = RecordingFileTransfer(timeline: timeline)
        let server = AcceptingSyncServer(timeline: timeline)
        let files = FileStore(directoryURL: folder.appending(path: "files"))
        let records = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        let shotId = try files.save(Data("shot".utf8), contentType: "image/jpeg")
        try records.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("Fix the sink"), "image": .string(FileStore.reference(for: shotId))]))
        let sync = RecordSync(store: records, api: server, fileStore: files, fileTransfer: transfer)

        let synced = await sync.syncNow()
        XCTAssertTrue(synced)
        XCTAssertEqual(timeline.events, ["file \(shotId)", "push 1 ops"])
        XCTAssertEqual(transfer.uploads.first?.contentType, "image/jpeg")
        XCTAssertEqual(files.pendingUploads(), [])
        XCTAssertEqual(files.meta(for: shotId)?.uploaded, true)
        XCTAssertEqual(records.pendingOpCount, 0)

        // The next sync sends nothing again.
        await sync.syncNow()
        XCTAssertEqual(timeline.events.count, 2)
    }

    func testWhenTheFileCannotBeSentTheRecordWaitsWithIt() async throws {
        let timeline = Timeline()
        let transfer = RecordingFileTransfer(timeline: timeline)
        transfer.isOffline = true
        let server = AcceptingSyncServer(timeline: timeline)
        let files = FileStore(directoryURL: folder.appending(path: "files"))
        let records = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        let shotId = try files.save(Data("shot".utf8), contentType: "image/jpeg")
        try records.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("Fix the sink"), "image": .string(FileStore.reference(for: shotId))]))
        let sync = RecordSync(store: records, api: server, fileStore: files, fileTransfer: transfer)

        let synced = await sync.syncNow()
        XCTAssertFalse(synced)
        XCTAssertTrue(sync.lastSyncFailed)
        XCTAssertEqual(timeline.events, [], "nothing was pushed while the file could not go up")
        XCTAssertEqual(files.pendingUploads(), [shotId])
        XCTAssertEqual(records.pendingOpCount, 1)

        transfer.isOffline = false
        let synedLater = await sync.syncNow()
        XCTAssertTrue(synedLater)
        XCTAssertEqual(timeline.events, ["file \(shotId)", "push 1 ops"])
        XCTAssertEqual(server.storedKeys, ["reminder:1"])
    }

    func testAQueuedFileWhoseBytesAreGoneIsSkippedSoTheRecordsStillGoUp() async throws {
        let timeline = Timeline()
        let transfer = RecordingFileTransfer(timeline: timeline)
        let server = AcceptingSyncServer(timeline: timeline)
        let filesFolder = folder.appending(path: "files")
        let files = FileStore(directoryURL: filesFolder)
        let goneId = try files.save(Data("gone".utf8), contentType: "image/jpeg")
        try FileManager.default.removeItem(at: filesFolder.appending(path: goneId))
        let records = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        try records.set(sidekickId: "notes", key: "note:1", value: .string("hi"))
        let sync = RecordSync(store: records, api: server, fileStore: files, fileTransfer: transfer)

        let synced = await sync.syncNow()
        XCTAssertTrue(synced)
        XCTAssertEqual(timeline.events, ["push 1 ops"])
        XCTAssertEqual(files.pendingUploads(), [])
    }

    func testASyncWithoutFilesBehavesAsBefore() async throws {
        let timeline = Timeline()
        let server = AcceptingSyncServer(timeline: timeline)
        let records = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        try records.set(sidekickId: "notes", key: "note:1", value: .string("hi"))
        let sync = RecordSync(store: records, api: server)
        let synced = await sync.syncNow()
        XCTAssertTrue(synced)
        XCTAssertEqual(timeline.events, ["push 1 ops"])
    }
}
