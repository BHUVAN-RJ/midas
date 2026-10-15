import UIKit
import XCTest
@testable import Midas

/// Fakes the on-device transcriber: words arrive when the test says so.
@MainActor
private final class StubTranscriber: RepairTranscribing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var sessionStartedAt: Date?
    private var onUpdate: ((RepairTranscript) -> Void)?
    var failsToStart = false

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        if failsToStart {
            throw RepairSpeechError.onDeviceUnavailable
        }
        startCount += 1
        self.sessionStartedAt = sessionStartedAt
        self.onUpdate = onUpdate
    }

    func stop() {
        stopCount += 1
    }

    func hear(_ transcript: RepairTranscript) {
        onUpdate?(transcript)
    }
}

private final class RecordingUploadAPI: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var reports: [RepairReport] = []
    let uploaded = XCTestExpectation(description: "report uploaded")

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        record(report)
        uploaded.fulfill()
        return .accepted
    }

    // Swift 6 forbids NSLock.lock()/unlock() inside an async function, so the locked
    // section lives in this synchronous helper.
    private func record(_ report: RepairReport) {
        lock.lock()
        reports.append(report)
        lock.unlock()
    }
}

/// Word and stroke timings share one clock; Send waits for a word; Cancel sends nothing.
@MainActor
final class RepairSessionTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-session-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private static let sessionStart = Date(timeIntervalSince1970: 1_760_000_000)

    private static func snapshot() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
    }

    private func makeSession(transcriber: StubTranscriber, api: RepairUploadAPI = RecordingUploadAPI()) -> RepairSession {
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: outboxURL))
        let versions = SidekickBundleVersions()
        versions.record(sidekickId: "reminders", version: "v7", scope: "user")
        return RepairSession(sidekickId: "reminders", snapshot: Self.snapshot(), viewSize: CGSize(width: 20, height: 30), transcriber: transcriber, uploader: uploader, bundleVersions: versions, startedAt: Self.sessionStart)
    }

    // MARK: One clock

    func testWordTimingsAreRebasedOntoTheSessionClock() {
        let audioStartedAt = Self.sessionStart.addingTimeInterval(0.5)
        let word = RepairWordTiming.word("here", segmentTimestamp: 1.2, segmentDuration: 0.3, audioStartedAt: audioStartedAt, sessionStartedAt: Self.sessionStart)
        XCTAssertEqual(word, RepairWord(word: "here", startMs: 1700, endMs: 2000))
    }

    func testStrokeTimesCountFromTheSameStart() async {
        let transcriber = StubTranscriber()
        let session = makeSession(transcriber: transcriber)
        await session.startListening()
        XCTAssertEqual(transcriber.sessionStartedAt, Self.sessionStart, "transcriber must get the session's clock")
        XCTAssertEqual(session.elapsedMs(at: Self.sessionStart.addingTimeInterval(1.5)), 1500)
    }

    // MARK: Send gate

    func testSendWaitsForAWord() async {
        let transcriber = StubTranscriber()
        let session = makeSession(transcriber: transcriber)
        var finishCount = 0
        session.onFinish = { finishCount += 1 }
        session.beginStroke(at: CGPoint(x: 1, y: 1))
        session.endStroke()
        XCTAssertFalse(session.canSend)
        session.send()
        XCTAssertEqual(finishCount, 0, "Send must do nothing without a transcript")

        session.typedText = "move it"
        XCTAssertTrue(session.canSend)
    }

    func testSpokenWordsEnableSend() async {
        let transcriber = StubTranscriber()
        let session = makeSession(transcriber: transcriber)
        await session.startListening()
        XCTAssertFalse(session.canSend)
        transcriber.hear(RepairTranscript(text: "the tag", words: [RepairWord(word: "the", startMs: 0, endMs: 100), RepairWord(word: "tag", startMs: 100, endMs: 300)]))
        XCTAssertTrue(session.canSend)
    }

    func testSendStopsListeningDismissesAndUploadsTheReport() async {
        let transcriber = StubTranscriber()
        let api = RecordingUploadAPI()
        let session = makeSession(transcriber: transcriber, api: api)
        var finishCount = 0
        session.onFinish = { finishCount += 1 }
        await session.startListening()
        transcriber.hear(RepairTranscript(text: "the tag is wrong", words: [RepairWord(word: "tag", startMs: 400, endMs: 600)]))
        session.beginStroke(at: CGPoint(x: 2, y: 3))
        session.extendStroke(to: CGPoint(x: 10, y: 12))
        session.endStroke()

        session.send()
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(transcriber.stopCount, 1)
        await fulfillment(of: [api.uploaded], timeout: 5)

        let report = try? XCTUnwrap(api.reports.first)
        XCTAssertEqual(report?.sidekickId, "reminders")
        XCTAssertEqual(report?.bundleVersion, "v7")
        XCTAssertEqual(report?.bundleScope, "user")
        XCTAssertEqual(report?.transcript, "the tag is wrong")
        XCTAssertEqual(report?.words, [RepairWord(word: "tag", startMs: 400, endMs: 600)])
        XCTAssertEqual(report?.clientReportId, session.id)
        let strokes = try? RepairStrokesJSON.decode(report?.strokesJSON ?? Data())
        XCTAssertEqual(strokes?.count, 1)
        XCTAssertEqual(strokes?.first?.points.count, 2)
        XCTAssertEqual(strokes?.first?.points.first?[0], 2)
        XCTAssertEqual(strokes?.first?.points.first?[1], 3)
    }

    func testCancelStopsListeningAndSendsNothing() async {
        let transcriber = StubTranscriber()
        let api = RecordingUploadAPI()
        let session = makeSession(transcriber: transcriber, api: api)
        var finishCount = 0
        session.onFinish = { finishCount += 1 }
        await session.startListening()
        transcriber.hear(RepairTranscript(text: "never mind", words: []))
        session.cancel()
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(transcriber.stopCount, 1)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(api.reports.isEmpty)
        XCTAssertEqual(RepairOutbox(directoryURL: outboxURL).pending().count, 0)
    }

    // MARK: Drawing

    func testUndoRemovesTheLastStrokeAndClearRemovesAll() {
        let session = makeSession(transcriber: StubTranscriber())
        session.beginStroke(at: CGPoint(x: 1, y: 1))
        session.endStroke()
        session.beginStroke(at: CGPoint(x: 5, y: 5))
        session.endStroke()
        XCTAssertEqual(session.strokes.count, 2)
        session.undo()
        XCTAssertEqual(session.strokes.count, 1)
        XCTAssertEqual(session.strokes.first?.points.first?[0], 1)
        session.beginStroke(at: CGPoint(x: 9, y: 9))
        session.endStroke()
        session.clear()
        XCTAssertTrue(session.strokes.isEmpty)
    }

    // MARK: Permissions and no speech

    func testNoOnDeviceSpeechStillAllowsDrawingAndTyping() async {
        let transcriber = StubTranscriber()
        transcriber.failsToStart = true
        let session = makeSession(transcriber: transcriber)
        await session.startListening()
        XCTAssertFalse(session.isListening)
        session.typedText = "typed instead"
        XCTAssertTrue(session.canSend)
    }
}
