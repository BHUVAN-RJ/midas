import UIKit
import XCTest
@testable import Midas

/// A report made offline waits on disk and goes up later; the server's verdict decides whether
/// it leaves the queue.
private final class StubRepairUploadAPI: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [Result<RepairUploadOutcome, Error>]
    private(set) var uploadedIds: [String] = []

    init(outcomes: [Result<RepairUploadOutcome, Error>]) {
        self.outcomes = outcomes
    }

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        try takeNextOutcome(for: report)
    }

    // Swift 6 forbids NSLock.lock()/unlock() inside an async function, so the locked
    // section lives in this synchronous helper.
    private func takeNextOutcome(for report: RepairReport) throws -> RepairUploadOutcome {
        lock.lock()
        defer { lock.unlock() }
        uploadedIds.append(report.clientReportId)
        guard !outcomes.isEmpty else {
            return .retryLater
        }
        return try outcomes.removeFirst().get()
    }
}

private struct Offline: Error {}

@MainActor
final class RepairOutboxTests: XCTestCase {
    private var directoryURL: URL!

    override func setUp() {
        super.setUp()
        directoryURL = FileManager.default.temporaryDirectory.appending(path: "repair-outbox-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directoryURL)
        super.tearDown()
    }

    private func makeReport(id: String) -> RepairReport {
        RepairReport(
            clientReportId: id,
            sidekickId: "reminders",
            kind: "unknown",
            bundleVersion: "v1",
            bundleScope: "base",
            transcript: "the tag is wrong",
            spokenText: "the tag is wrong",
            typedText: "",
            words: [RepairWord(word: "tag", startMs: 10, endMs: 20)],
            strokesJSON: Data("{\"strokes\":[]}".utf8),
            screenshotJPEG: Data([0xFF, 0xD8, 0xFF]),
            drawingPNG: Data([0x89, 0x50, 0x4E, 0x47]),
            device: "iPhone17,1",
            iosVersion: "26.0",
            appVersion: "0.1.0",
            appBuild: "2"
        )
    }

    func testOfflineReportIsQueued() async {
        let api = StubRepairUploadAPI(outcomes: [.failure(Offline())])
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: directoryURL))
        await uploader.send(makeReport(id: "a"))
        XCTAssertEqual(uploader.pendingCount, 1)
    }

    func testAcceptedReportLeavesTheQueue() async {
        let api = StubRepairUploadAPI(outcomes: [.success(.accepted)])
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: directoryURL))
        await uploader.send(makeReport(id: "a"))
        XCTAssertEqual(uploader.pendingCount, 0)
    }

    func testServerErrorKeepsTheReport() async {
        let api = StubRepairUploadAPI(outcomes: [.success(.retryLater)])
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: directoryURL))
        await uploader.send(makeReport(id: "a"))
        XCTAssertEqual(uploader.pendingCount, 1)
    }

    func testRejectedReportIsDropped() async {
        let api = StubRepairUploadAPI(outcomes: [.success(.rejected(statusCode: 400))])
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: directoryURL))
        await uploader.send(makeReport(id: "a"))
        XCTAssertEqual(uploader.pendingCount, 0)
    }

    func testQueuedReportSurvivesRelaunchAndIsRetriedIntact() async {
        let firstLaunchAPI = StubRepairUploadAPI(outcomes: [.failure(Offline())])
        let firstUploader = RepairUploader(api: firstLaunchAPI, outbox: RepairOutbox(directoryURL: directoryURL))
        await firstUploader.send(makeReport(id: "a"))

        // A new uploader over the same folder, as after a relaunch.
        let secondLaunchAPI = StubRepairUploadAPI(outcomes: [.success(.accepted)])
        let outbox = RepairOutbox(directoryURL: directoryURL)
        let restored = outbox.pending()
        XCTAssertEqual(restored, [makeReport(id: "a")], "report did not come back from disk unchanged")

        let secondUploader = RepairUploader(api: secondLaunchAPI, outbox: outbox)
        await secondUploader.retryQueued()
        XCTAssertEqual(secondLaunchAPI.uploadedIds, ["a"])
        XCTAssertEqual(secondUploader.pendingCount, 0)
    }

    func testRetryGoesOldestFirst() async throws {
        let outbox = RepairOutbox(directoryURL: directoryURL)
        try outbox.enqueue(makeReport(id: "first"))
        try await Task.sleep(for: .milliseconds(20))
        try outbox.enqueue(makeReport(id: "second"))
        let api = StubRepairUploadAPI(outcomes: [.success(.accepted), .success(.accepted)])
        let uploader = RepairUploader(api: api, outbox: outbox)
        await uploader.retryQueued()
        XCTAssertEqual(api.uploadedIds, ["first", "second"])
    }

    func testStatusCodesMapToOutcomes() {
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 201), .accepted)
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 200), .accepted)
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 400), .rejected(statusCode: 400))
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 413), .rejected(statusCode: 413))
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 401), .retryLater)
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 429), .retryLater)
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 500), .retryLater)
        XCTAssertEqual(RemoteRepairUploadAPI.outcome(forStatusCode: 0), .retryLater)
    }

    func testSignedOutUploadWaits() async throws {
        let api = RemoteRepairUploadAPI(platformOrigin: URL(string: "https://example.invalid")!, session: .shared, sessionToken: { nil })
        let outcome = try await api.upload(makeReport(id: "a"))
        XCTAssertEqual(outcome, .retryLater)
    }
}
