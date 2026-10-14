import UIKit
import XCTest
@testable import Midas

/// A feature request (founder, 2026-10-13: "I want my reminders to store images") may be voice
/// only: no stroke at all. The shell still sends it, with the screenshot, an undrawn drawing and
/// an empty stroke list, and a kind the contract accepts.
@MainActor
private final class VoiceOnlyTranscriber: RepairTranscribing {
    private var onUpdate: ((RepairTranscript) -> Void)?

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        self.onUpdate = onUpdate
    }

    func stop() {}

    func hear(_ text: String) {
        onUpdate?(RepairTranscript(text: text, words: []))
    }
}

private final class CapturingUploadAPI: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [RepairReport] = []
    let uploaded = XCTestExpectation(description: "report uploaded")

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        capture(report)
        uploaded.fulfill()
        return .accepted
    }

    private func capture(_ report: RepairReport) {
        lock.lock()
        captured.append(report)
        lock.unlock()
    }

    var first: RepairReport? {
        lock.lock()
        defer { lock.unlock() }
        return captured.first
    }
}

@MainActor
final class RepairFeatureRequestTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-feature-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private static func snapshot() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
    }

    func testVoiceOnlyRequestIsSentWithoutAStroke() async throws {
        let transcriber = VoiceOnlyTranscriber()
        let api = CapturingUploadAPI()
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: outboxURL))
        let session = RepairSession(sidekickId: "reminders", snapshot: Self.snapshot(), viewSize: CGSize(width: 20, height: 30), transcriber: transcriber, uploader: uploader, bundleVersions: SidekickBundleVersions(), permissionState: .granted)
        var finishCount = 0
        session.onFinish = { finishCount += 1 }
        await session.startListening()

        XCTAssertFalse(session.canSend)
        transcriber.hear("I want my reminders to store images as well")
        XCTAssertTrue(session.canSend, "words alone must be enough; a feature request has no drawing")
        XCTAssertTrue(session.strokes.isEmpty)

        session.send()
        XCTAssertEqual(finishCount, 1)
        await fulfillment(of: [api.uploaded], timeout: 5)

        let report = try XCTUnwrap(api.first)
        XCTAssertEqual(report.transcript, "I want my reminders to store images as well")
        XCTAssertTrue(RepairReport.contractKinds.contains(report.kind), "kind \(report.kind) is not in the contract")
        XCTAssertEqual(report.kind, "unknown", "the shell sends a hint only; the agent decides the kind")
        let strokes = try RepairStrokesJSON.decode(report.strokesJSON).strokes
        XCTAssertEqual(strokes, [])
        XCTAssertFalse(report.screenshotJPEG.isEmpty, "the screenshot still goes, so the agent sees the Sidekick")
        XCTAssertEqual(UIImage(data: report.drawingPNG)?.size, CGSize(width: 20, height: 30), "the drawing is the plain screenshot when nothing was drawn")
    }

    func testContractKindsAreTheThreePlusUnknown() {
        XCTAssertEqual(RepairReport.contractKinds, ["bug", "change", "feature", "unknown"])
    }

    func testMultipartSendsTheKindPart() throws {
        let report = RepairReport(
            clientReportId: "r", sidekickId: "reminders", kind: RepairReport.unknownKind, bundleVersion: "v1", bundleScope: "base",
            transcript: "store images", spokenText: "store images", typedText: "", words: [],
            strokesJSON: Data("{}".utf8), screenshotJPEG: Data([1]), drawingPNG: Data([2]),
            device: "iPhone17,1", iosVersion: "26.0", appVersion: "0.1.0", appBuild: "2"
        )
        let body = try RepairMultipart.body(for: report, boundary: "b")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"kind\"\r\n\r\nunknown\r\n"))
    }
}
