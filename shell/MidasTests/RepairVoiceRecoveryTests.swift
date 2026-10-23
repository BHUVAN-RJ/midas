import AVFoundation
import Speech
import UIKit
import XCTest
@testable import Midas

/// Repair voice bug (founder's phone, 2026-10-23): every repair report had no words. The
/// recogniser stopped by itself (an error such as "no speech" while the user was still drawing,
/// or a final result) and the repair layer was never told: the orb showed listening forever and
/// nothing more was heard. Now the layer learns of every end, goes idle, listens again, keeps the
/// words already heard, and sends iOS's error with the report (`voiceError`).

/// Stands in for the microphone and the recogniser; keeps the callbacks handed to iOS.
@MainActor
private final class RecoveryFakeEngine: SpeechRecognitionEngine {
    var isOnDeviceAvailable = true
    private(set) var audioStartCount = 0
    private(set) var recognitionStartCount = 0
    private(set) var tap: VoiceAudioTap?
    private(set) var resultHandler: VoiceRecognitionHandler?

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        audioStartCount += 1
        self.tap = tap
    }

    func stopAudio() {}

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        recognitionStartCount += 1
        self.resultHandler = resultHandler
    }

    func cancelRecognition() {}
}

private struct GrantedPermissions: VoicePermissionSystem {
    let microphone: VoicePermissionAnswer = .granted
    let speech: VoicePermissionAnswer = .granted

    func requestMicrophone() async {}
    func requestSpeech() async {}
}

/// Keeps every report the session sends.
private final class KeepingUploadAPI: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReports: [RepairReport] = []
    let uploaded = XCTestExpectation(description: "report uploaded")

    var reports: [RepairReport] {
        lock.withLock { storedReports }
    }

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        keep(report)
        uploaded.fulfill()
        return .accepted
    }

    private func keep(_ report: RepairReport) {
        lock.withLock { storedReports.append(report) }
    }
}

/// Collects what the transcriber delivers.
@MainActor
private final class EndRecorder {
    private(set) var updates: [VoiceTranscript] = []
    private(set) var ends: [VoiceTranscriptionEnd] = []

    func receiveUpdate(_ transcript: VoiceTranscript) {
        updates.append(transcript)
    }

    func receiveEnd(_ reason: VoiceTranscriptionEnd) {
        ends.append(reason)
    }
}

@MainActor
final class RepairVoiceRecoveryTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-voice-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private static func whiteImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
        func fillWhite(_ context: UIGraphicsImageRendererContext) {
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        return renderer.image(actions: fillWhite)
    }

    private func makeTranscriber(engine: RecoveryFakeEngine) -> OnDeviceSpeechTranscriber {
        OnDeviceSpeechTranscriber(options: .repair, permissions: GrantedPermissions(), engine: engine)
    }

    private func makeSession(transcriber: RepairTranscribing, api: RepairUploadAPI = KeepingUploadAPI()) -> RepairSession {
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: outboxURL))
        return RepairSession(sidekickId: "reminders", snapshot: Self.whiteImage(), viewSize: CGSize(width: 20, height: 30), transcriber: transcriber, uploader: uploader)
    }

    /// Waits up to 3 s for something the main actor will do soon.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Calls the recognition handler the way iOS does: on its own queue, with an error.
    private func failRecognition(_ engine: RecoveryFakeEngine, code: Int) throws {
        let handler = try XCTUnwrap(engine.resultHandler, "recognition never started")
        DispatchQueue.global(qos: .userInitiated).async {
            handler(nil, NSError(domain: "kAFAssistantErrorDomain", code: code))
        }
    }

    private static func heard(_ text: String, startMs: Int) -> VoiceTranscript {
        let word = VoiceWord(word: text, startMs: startMs, endMs: startMs + 200)
        return VoiceTranscript(text: text, words: [word])
    }

    // MARK: Bug 1: the orb no longer shows listening after the recogniser stopped

    func testAFailureListensAgainOnceThenTheOrbGoesIdle() async throws {
        let engine = RecoveryFakeEngine()
        let session = makeSession(transcriber: makeTranscriber(engine: engine))
        await session.startListening()
        XCTAssertTrue(session.isListening)

        try failRecognition(engine, code: 1101)
        func listeningAgain() -> Bool {
            engine.recognitionStartCount == 2 && session.isListening
        }
        let retried = await eventually(listeningAgain)
        XCTAssertTrue(retried, "after the recogniser's first error the layer must listen again")

        try failRecognition(engine, code: 1101)
        func idle() -> Bool {
            !session.isListening
        }
        let wentIdle = await eventually(idle)
        XCTAssertTrue(wentIdle, "after a second quick error the orb must show idle, not listening")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(engine.recognitionStartCount, 2, "a second quick failure must not retry again")
        XCTAssertFalse(session.isListening)
        XCTAssertEqual(session.voiceProblems, ["kAFAssistantErrorDomain 1101"])
    }

    /// The recogniser gives up on silence while the user draws first: a listen that worked for a
    /// while earns its retry back, so the layer keeps listening for as long as it is open.
    func testAListenThatWorkedEarnsItsRetryBack() async throws {
        let engine = RecoveryFakeEngine()
        let session = makeSession(transcriber: makeTranscriber(engine: engine))
        await session.startListening()
        let healthy = Duration.milliseconds(Int(RepairListening.healthyListen * 1000) + 150)

        try await Task.sleep(for: healthy)
        try failRecognition(engine, code: 1110)
        func secondListen() -> Bool {
            engine.recognitionStartCount == 2 && session.isListening
        }
        let second = await eventually(secondListen)
        XCTAssertTrue(second)

        try await Task.sleep(for: healthy)
        try failRecognition(engine, code: 1110)
        func thirdListen() -> Bool {
            engine.recognitionStartCount == 3 && session.isListening
        }
        let third = await eventually(thirdListen)
        XCTAssertTrue(third, "a listen that lasted must get a fresh retry")
        session.cancel()
    }

    func testAFinalResultEndsTheListenAndTheLayerListensAgain() async throws {
        let engine = RecoveryFakeEngine()
        let transcriber = makeTranscriber(engine: engine)
        let session = makeSession(transcriber: transcriber)
        await session.startListening()
        transcriber.receive(.heardFinal(Self.heard("bigger", startMs: 500)))
        func listeningAgain() -> Bool {
            engine.recognitionStartCount == 2 && session.isListening
        }
        let restarted = await eventually(listeningAgain)
        XCTAssertTrue(restarted, "a final result while the layer is open must not leave it deaf")
        XCTAssertEqual(session.transcript.text, "bigger")
        session.cancel()
    }

    func testTheTranscriberReportsAFinalResultAsItsOwnEnd() async throws {
        let engine = RecoveryFakeEngine()
        let transcriber = makeTranscriber(engine: engine)
        let recorder = EndRecorder()
        try await transcriber.start(sessionStartedAt: Date(), onUpdate: recorder.receiveUpdate, onEnd: recorder.receiveEnd)
        let last = Self.heard("done", startMs: 0)
        transcriber.receive(.heardFinal(last))
        XCTAssertEqual(recorder.updates, [last])
        XCTAssertEqual(recorder.ends, [.recognizerFinished])
        XCTAssertFalse(transcriber.isListening)
    }

    func testWordsHeardBeforeARestartAreKept() async throws {
        let engine = RecoveryFakeEngine()
        let transcriber = makeTranscriber(engine: engine)
        let session = makeSession(transcriber: transcriber)
        await session.startListening()
        transcriber.receive(.heard(Self.heard("tag", startMs: 400)))
        transcriber.receive(.failedWith(VoiceFailure(domain: "kAFAssistantErrorDomain", code: 1110)))
        func listeningAgain() -> Bool {
            engine.recognitionStartCount == 2 && session.isListening
        }
        let restarted = await eventually(listeningAgain)
        XCTAssertTrue(restarted)
        transcriber.receive(.heard(Self.heard("bigger", startMs: 3000)))
        XCTAssertEqual(session.transcript.text, "tag bigger")
        XCTAssertEqual(session.transcript.words.map(\.word), ["tag", "bigger"])
        XCTAssertEqual(session.transcript.words.map(\.startMs), [400, 3000])
        session.cancel()
    }

    func testCancelStopsForGoodWithoutListeningAgain() async throws {
        let engine = RecoveryFakeEngine()
        let session = makeSession(transcriber: makeTranscriber(engine: engine))
        await session.startListening()
        session.cancel()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(engine.audioStartCount, 1)
        XCTAssertFalse(session.isListening)
        XCTAssertNil(session.voiceError.flatMap(Self.recogniserPart), "stopping is not an error")
    }

    private static func recogniserPart(_ voiceError: String) -> String? {
        voiceError.contains("ErrorDomain") ? voiceError : nil
    }

    // MARK: The cause travels with the report

    func testTheRecognisersErrorIsKeptWithItsDomainAndCode() async throws {
        let engine = RecoveryFakeEngine()
        let transcriber = makeTranscriber(engine: engine)
        try await transcriber.start(sessionStartedAt: Date(), onUpdate: EndRecorder().receiveUpdate, onEnd: nil)
        try failRecognition(engine, code: 1110)
        func stopped() -> Bool {
            !transcriber.isListening
        }
        let ended = await eventually(stopped)
        XCTAssertTrue(ended)
        XCTAssertEqual(transcriber.lastFailure, VoiceFailure(domain: "kAFAssistantErrorDomain", code: 1110))
    }

    func testTheSentReportCarriesTheVoiceError() async throws {
        let engine = RecoveryFakeEngine()
        let api = KeepingUploadAPI()
        let session = makeSession(transcriber: makeTranscriber(engine: engine), api: api)
        await session.startListening()
        let tap = try XCTUnwrap(engine.tap)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        for sample in 0..<3 {
            tap(buffer, AVAudioTime(sampleTime: AVAudioFramePosition(sample * 160), atRate: 16_000))
        }
        try failRecognition(engine, code: 1101)
        func retried() -> Bool {
            engine.recognitionStartCount == 2
        }
        let listenedAgain = await eventually(retried)
        XCTAssertTrue(listenedAgain)
        session.typedText = "make it bigger"
        session.send()
        await fulfillment(of: [api.uploaded], timeout: 5)
        let report = try XCTUnwrap(api.reports.first)
        XCTAssertEqual(report.voiceError, "kAFAssistantErrorDomain 1101; no words, 3 audio buffers")
    }

    func testAStartRefusalIsNamedInTheVoiceError() async {
        let engine = RecoveryFakeEngine()
        engine.isOnDeviceAvailable = false
        let session = makeSession(transcriber: makeTranscriber(engine: engine))
        await session.startListening()
        XCTAssertFalse(session.isListening)
        XCTAssertEqual(session.voiceError, "start onDeviceUnavailable; no words, 0 audio buffers")
    }

    func testVoiceErrorIsCutToTheServersShortFieldLength() async throws {
        let engine = RecoveryFakeEngine()
        let transcriber = makeTranscriber(engine: engine)
        let session = makeSession(transcriber: transcriber)
        await session.startListening()
        let longDomain = String(repeating: "d", count: 120)
        transcriber.receive(.failedWith(VoiceFailure(domain: longDomain, code: 1)))
        func stoppedOrRetried() -> Bool {
            engine.recognitionStartCount == 2
        }
        _ = await eventually(stoppedOrRetried)
        let voiceError = try XCTUnwrap(session.voiceError)
        XCTAssertEqual(voiceError.count, RepairListening.maxVoiceErrorLength)
        session.cancel()
    }

    func testTheMultipartBodyHasAVoiceErrorPartOnlyWhenThereIsOne() throws {
        let versions = SidekickBundleVersions()
        versions.record(sidekickId: "reminders", version: "v1", scope: "user")
        let device = RepairDeviceInfo(device: "iPhone17,1", iosVersion: "27.0", appVersion: "0.1.0", appBuild: "10")
        func report(voiceError: String?) throws -> RepairReport {
            try RepairReportBuilder.build(clientReportId: "r1", sidekickId: "reminders", bundle: versions.entry(forSidekickId: "reminders"), spokenText: "", typedText: "bigger", words: [], strokes: [], screenshot: Self.whiteImage(), drawing: Self.whiteImage(), viewSize: CGSize(width: 20, height: 30), screenScale: 1, sessionStartedAt: Date(), deviceInfo: device, voiceError: voiceError)
        }
        let withError = try RepairMultipart.body(for: report(voiceError: "kLSRErrorDomain 300"), boundary: "b")
        let withErrorText = String(decoding: withError, as: UTF8.self)
        XCTAssertTrue(withErrorText.contains("name=\"voiceError\"\r\n\r\nkLSRErrorDomain 300\r\n"))
        let without = try RepairMultipart.body(for: report(voiceError: nil), boundary: "b")
        XCTAssertFalse(String(decoding: without, as: UTF8.self).contains("voiceError"))
    }

    func testAQueuedReportKeepsItsVoiceErrorAcrossARelaunch() throws {
        let versions = SidekickBundleVersions()
        let device = RepairDeviceInfo(device: "iPhone17,1", iosVersion: "27.0", appVersion: "0.1.0", appBuild: "10")
        let report = try RepairReportBuilder.build(clientReportId: "queued-1", sidekickId: "reminders", bundle: versions.entry(forSidekickId: "reminders"), spokenText: "", typedText: "bigger", words: [], strokes: [], screenshot: Self.whiteImage(), drawing: Self.whiteImage(), viewSize: CGSize(width: 20, height: 30), screenScale: 1, sessionStartedAt: Date(), deviceInfo: device, voiceError: "kAFAssistantErrorDomain 1110")
        let outbox = RepairOutbox(directoryURL: outboxURL)
        try outbox.enqueue(report)
        XCTAssertEqual(outbox.pending().first?.voiceError, "kAFAssistantErrorDomain 1110")
        XCTAssertEqual(report.resent(clientReportId: "queued-2").voiceError, "kAFAssistantErrorDomain 1110")
    }
}
