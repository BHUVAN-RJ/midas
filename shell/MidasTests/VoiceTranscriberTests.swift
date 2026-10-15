import AVFoundation
import Speech
import XCTest
@testable import Midas

/// Stands in for the microphone and the recogniser: records what the transcriber asked for and
/// keeps the callbacks it handed to iOS, so a test can call them the way iOS does.
@MainActor
private final class FakeSpeechEngine: SpeechRecognitionEngine {
    var isOnDeviceAvailable = true
    var failsToStartAudio = false
    private(set) var audioStartCount = 0
    private(set) var audioStopCount = 0
    private(set) var recognitionStartCount = 0
    private(set) var recognitionCancelCount = 0
    private(set) var request: SFSpeechAudioBufferRecognitionRequest?
    private(set) var tap: VoiceAudioTap?
    private(set) var resultHandler: VoiceRecognitionHandler?

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        if failsToStartAudio {
            throw NSError(domain: "FakeSpeechEngine", code: 1)
        }
        audioStartCount += 1
        self.tap = tap
    }

    func stopAudio() {
        audioStopCount += 1
    }

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        recognitionStartCount += 1
        self.request = request
        self.resultHandler = resultHandler
    }

    func cancelRecognition() {
        recognitionCancelCount += 1
    }
}

/// Fixed answers for both permissions; never shows a prompt.
private struct FixedVoicePermissions: VoicePermissionSystem {
    let microphone: VoicePermissionAnswer
    let speech: VoicePermissionAnswer

    static let granted = FixedVoicePermissions(microphone: .granted, speech: .granted)

    func requestMicrophone() async {}
    func requestSpeech() async {}
}

/// Collects what the transcriber delivers on the main actor.
@MainActor
private final class TranscriptionRecorder {
    private(set) var updates: [VoiceTranscript] = []
    private(set) var ends: [VoiceTranscriptionEnd] = []
    let ended = XCTestExpectation(description: "listening ended")

    func receiveUpdate(_ transcript: VoiceTranscript) {
        updates.append(transcript)
    }

    func receiveEnd(_ reason: VoiceTranscriptionEnd) {
        ends.append(reason)
        ended.fulfill()
    }
}

/// The shared on-device transcriber (founder, 2026-10-15): the Swift 6 crash of the first phone
/// test, permissions, and each per-use option.
@MainActor
final class VoiceTranscriberTests: XCTestCase {
    private static let sessionStart = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeTranscriber(options: VoiceTranscriberOptions = .repair, permissions: FixedVoicePermissions = .granted, engine: FakeSpeechEngine) -> OnDeviceSpeechTranscriber {
        OnDeviceSpeechTranscriber(options: options, permissions: permissions, engine: engine)
    }

    private func startListening(_ transcriber: OnDeviceSpeechTranscriber, recorder: TranscriptionRecorder) async throws {
        try await transcriber.start(sessionStartedAt: Self.sessionStart, onUpdate: recorder.receiveUpdate, onEnd: recorder.receiveEnd)
    }

    private static func heard(_ text: String) -> VoiceRecognitionEvent {
        .heard(VoiceTranscript(text: text, words: []))
    }

    // MARK: Swift 6 crash (bug 1, 2026-10-14)

    /// iOS calls the audio tap on its audio thread and the recognition handler on its own queue.
    /// Calls both callbacks the transcriber hands the engine from a background queue, and checks
    /// the recogniser's error still reaches the main actor and ends listening.
    func testAudioTapAndRecognitionHandlerRunOffTheMainThreadWithoutTrapping() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = makeTranscriber(engine: engine)
        let recorder = TranscriptionRecorder()
        try await startListening(transcriber, recorder: recorder)
        let tap = try XCTUnwrap(engine.tap, "the transcriber never installed an audio tap")
        let resultHandler = try XCTUnwrap(engine.resultHandler, "the transcriber never started recognition")

        let calledInBackground = XCTestExpectation(description: "callbacks called on a background queue")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
            buffer.frameLength = 160
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
            resultHandler(nil, NSError(domain: "kAFAssistantErrorDomain", code: 1110))
            calledInBackground.fulfill()
        }
        await fulfillment(of: [calledInBackground, recorder.ended], timeout: 5)
        XCTAssertEqual(recorder.ends, [.failed], "the recogniser's error must reach the main actor and end listening")
        XCTAssertFalse(transcriber.isListening)
    }

    /// The same, through iOS itself: the live engine installs the transcriber's tap on a real
    /// `AVAudioEngine` (offline rendering, so no microphone), and rendering on a background thread
    /// makes iOS call it there, as the microphone does on the phone. A closure written inside the
    /// main-actor engine around the tap traps here with `EXC_BREAKPOINT` in
    /// `_swift_task_checkIsolatedSwift`, the founder's crash (checked 2026-10-15).
    func testTheLiveEngineHandsTheTapToIOSWithoutAMainActorWrapper() async throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let audioEngine = AVAudioEngine()
        try audioEngine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        silence.frameLength = 1024
        let silentInput = SilentInput(buffer: silence)
        let acceptsInput = audioEngine.inputNode.setManualRenderingInputPCMFormat(format, inputBlock: silentInput.provide)
        XCTAssertTrue(acceptsInput)
        audioEngine.connect(audioEngine.inputNode, to: audioEngine.mainMixerNode, format: format)

        let box = VoiceRecognitionRequestBox(request: OnDeviceSpeechTranscriber.makeRequest(options: .repair))
        let transcriberTap = OnDeviceSpeechTranscriber.makeAudioTap(feeding: box)
        let tapCalled = XCTestExpectation(description: "iOS called the tap")
        tapCalled.assertForOverFulfill = false
        let observedTap: VoiceAudioTap = { buffer, time in
            transcriberTap(buffer, time)
            tapCalled.fulfill()
        }
        let liveEngine = LiveSpeechRecognitionEngine(audioEngine: audioEngine)
        try liveEngine.installTapAndStart(observedTap)

        let renderer = OfflineRenderer(engine: audioEngine)
        let rendered = XCTestExpectation(description: "rendered on a background thread")
        DispatchQueue.global(qos: .userInitiated).async {
            renderer.render(times: 20)
            rendered.fulfill()
        }
        await fulfillment(of: [rendered, tapCalled], timeout: 5)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: Permissions (docs/CONCERNS.md item 10)

    func testPermissionDeniedThrowsAndNothingListens() async {
        let deniedCases = [
            FixedVoicePermissions(microphone: .denied, speech: .granted),
            FixedVoicePermissions(microphone: .granted, speech: .denied),
            FixedVoicePermissions(microphone: .notAsked, speech: .granted),
        ]
        for permissions in deniedCases {
            let engine = FakeSpeechEngine()
            let transcriber = makeTranscriber(permissions: permissions, engine: engine)
            do {
                try await startListening(transcriber, recorder: TranscriptionRecorder())
                XCTFail("start must throw when permission is \(permissions)")
            } catch {
                XCTAssertEqual(error as? VoiceTranscriberError, .notAuthorized)
            }
            XCTAssertEqual(engine.audioStartCount, 0, "the microphone must stay off without permission")
            XCTAssertEqual(engine.recognitionStartCount, 0)
            XCTAssertFalse(transcriber.isListening)
        }
    }

    func testNoOnDeviceModelThrowsAndNothingListens() async {
        let engine = FakeSpeechEngine()
        engine.isOnDeviceAvailable = false
        let transcriber = makeTranscriber(engine: engine)
        do {
            try await startListening(transcriber, recorder: TranscriptionRecorder())
            XCTFail("start must throw without an on-device model; audio never goes to a server")
        } catch {
            XCTAssertEqual(error as? VoiceTranscriberError, .onDeviceUnavailable)
        }
        XCTAssertEqual(engine.audioStartCount, 0)
        XCTAssertEqual(engine.recognitionStartCount, 0)
    }

    func testAudioFailureThrowsAndNothingRecognises() async {
        let engine = FakeSpeechEngine()
        engine.failsToStartAudio = true
        let transcriber = makeTranscriber(engine: engine)
        do {
            try await startListening(transcriber, recorder: TranscriptionRecorder())
            XCTFail("start must throw when the microphone cannot start")
        } catch {
            XCTAssertEqual(error as? VoiceTranscriberError, .audioFailed)
        }
        XCTAssertEqual(engine.recognitionStartCount, 0)
        XCTAssertFalse(transcriber.isListening)
    }

    func testTheSharedTranscriberNeverAsksForPermission() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory.deletingLastPathComponent().appending(path: "Midas").appending(path: "VoiceTranscriber.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("requestRecordPermission"), "the transcriber asks for the microphone")
        XCTAssertFalse(source.contains("requestAuthorization"), "the transcriber asks for speech recognition")
        XCTAssertFalse(source.contains("askAtLaunch"), "the transcriber shows the launch prompts")
    }

    // MARK: Options

    func testRequestIsAlwaysOnDeviceAndCarriesTheHintWords() async throws {
        let engine = FakeSpeechEngine()
        var options = VoiceTranscriberOptions()
        options.hintWords = ["Groceries", "Work"]
        let transcriber = makeTranscriber(options: options, engine: engine)
        try await startListening(transcriber, recorder: TranscriptionRecorder())
        let request = try XCTUnwrap(engine.request)
        XCTAssertTrue(request.requiresOnDeviceRecognition, "audio must never go to Apple's servers")
        XCTAssertTrue(request.shouldReportPartialResults)
        XCTAssertEqual(request.contextualStrings, ["Groceries", "Work"])
        transcriber.stop()
    }

    func testRepairSetsNoHintWordsNoSilenceEndAndAFiveMinuteBackstop() async throws {
        XCTAssertEqual(VoiceTranscriberOptions.repair.hintWords, [])
        XCTAssertNil(VoiceTranscriberOptions.repair.endOfSpeechSilence)
        XCTAssertEqual(VoiceTranscriberOptions.repair.maximumDuration, .seconds(5 * 60))
        XCTAssertEqual(OnDeviceSpeechTranscriber(engine: FakeSpeechEngine()).options, .repair, "the default must stay repair's")

        let engine = FakeSpeechEngine()
        let transcriber = makeTranscriber(options: .repair, engine: engine)
        try await startListening(transcriber, recorder: TranscriptionRecorder())
        XCTAssertEqual(engine.request?.contextualStrings, [])
        transcriber.stop()
    }

    func testUpdatesReachTheCaller() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = makeTranscriber(engine: engine)
        let recorder = TranscriptionRecorder()
        try await startListening(transcriber, recorder: recorder)
        let transcript = VoiceTranscript(text: "the tag", words: [VoiceWord(word: "the", startMs: 0, endMs: 100), VoiceWord(word: "tag", startMs: 100, endMs: 300)])
        transcriber.receive(.heard(transcript))
        XCTAssertEqual(recorder.updates, [transcript])
        transcriber.stop()
    }

    func testSilenceAfterTheLastWordEndsListening() async throws {
        let engine = FakeSpeechEngine()
        var options = VoiceTranscriberOptions()
        options.endOfSpeechSilence = .milliseconds(150)
        let transcriber = makeTranscriber(options: options, engine: engine)
        let recorder = TranscriptionRecorder()
        try await startListening(transcriber, recorder: recorder)
        transcriber.receive(Self.heard("buy milk"))
        await fulfillment(of: [recorder.ended], timeout: 3)
        XCTAssertEqual(recorder.ends, [.silence])
        XCTAssertFalse(transcriber.isListening)
        XCTAssertEqual(engine.audioStopCount, 1, "the microphone must turn off when speech ends")
        XCTAssertEqual(engine.recognitionCancelCount, 1)
    }

    func testSilenceCountsOnlyOnceAWordWasHeard() async throws {
        let engine = FakeSpeechEngine()
        var options = VoiceTranscriberOptions()
        options.endOfSpeechSilence = .milliseconds(100)
        let transcriber = makeTranscriber(options: options, engine: engine)
        let recorder = TranscriptionRecorder()
        try await startListening(transcriber, recorder: recorder)
        transcriber.receive(Self.heard(""))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(transcriber.isListening, "silence before the first word must not end listening")
        XCTAssertEqual(recorder.ends, [])
        transcriber.stop()
    }

    func testNewWordsRestartTheSilenceCount() async throws {
        let engine = FakeSpeechEngine()
        var options = VoiceTranscriberOptions()
        options.endOfSpeechSilence = .milliseconds(600)
        let transcriber = makeTranscriber(options: options, engine: engine)
        let recorder = TranscriptionRecorder()
        try await startListening(transcriber, recorder: recorder)
        transcriber.receive(Self.heard("call"))
        try await Task.sleep(for: .milliseconds(400))
        transcriber.receive(Self.heard("call mom"))
        // A repeated partial result is not a new word and must not restart the count
        transcriber.receive(Self.heard("call mom"))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(transcriber.isListening, "800 ms after the first word but 400 ms after the last: still listening")
        await fulfillment(of: [recorder.ended], timeout: 3)
        XCTAssertEqual(recorder.ends, [.silence])
    }

    func testMaximumLengthEndsListeningWhileTheUserIsStillTalking() async throws {
        let engine = FakeSpeechEngine()
        var options = VoiceTranscriberOptions()
        options.maximumDuration = .milliseconds(200)
        let transcriber = makeTranscriber(options: options, engine: engine)
        let recorder = TranscriptionRecorder()
        try await startListening(transcriber, recorder: recorder)
        transcriber.receive(Self.heard("and another"))
        await fulfillment(of: [recorder.ended], timeout: 3)
        XCTAssertEqual(recorder.ends, [.maximumLength])
        XCTAssertFalse(transcriber.isListening)
        XCTAssertEqual(engine.audioStopCount, 1)
    }

    func testStopOnDemandEndsOnceAndIgnoresLateWords() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = makeTranscriber(engine: engine)
        let recorder = TranscriptionRecorder()
        try await startListening(transcriber, recorder: recorder)
        transcriber.stop()
        XCTAssertEqual(recorder.ends, [.stopped])
        XCTAssertEqual(engine.audioStopCount, 1)
        XCTAssertEqual(engine.recognitionCancelCount, 1)

        transcriber.receive(Self.heard("too late"))
        transcriber.stop()
        XCTAssertEqual(recorder.updates, [], "words after stop must not be delivered")
        XCTAssertEqual(recorder.ends, [.stopped], "a second stop must not end again")
        XCTAssertEqual(engine.audioStopCount, 1)
    }

    // MARK: Repair uses it unchanged

    func testRepairSessionListensThroughTheSharedTranscriber() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = makeTranscriber(options: .repair, engine: engine)
        let outboxURL = FileManager.default.temporaryDirectory.appending(path: "voice-transcriber-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxURL)
        }
        let uploader = RepairUploader(api: NeverUploadAPI(), outbox: RepairOutbox(directoryURL: outboxURL))
        let session = RepairSession(sidekickId: "reminders", snapshot: UIImage(), viewSize: CGSize(width: 20, height: 30), transcriber: transcriber, uploader: uploader, startedAt: Self.sessionStart)
        await session.startListening()
        XCTAssertTrue(session.isListening)
        XCTAssertEqual(engine.audioStartCount, 1)
        transcriber.receive(Self.heard("the tag is wrong"))
        XCTAssertEqual(session.transcript.text, "the tag is wrong")
        session.cancel()
        XCTAssertFalse(transcriber.isListening)
        XCTAssertEqual(engine.audioStopCount, 1)
    }
}

/// Feeds the same silent buffer to an offline engine's input on every render.
private final class SilentInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(_ frameCount: AVAudioFrameCount) -> UnsafePointer<AudioBufferList>? {
        buffer.audioBufferList
    }
}

/// Renders an offline engine from whatever thread calls it.
private final class OfflineRenderer: @unchecked Sendable {
    private let engine: AVAudioEngine

    init(engine: AVAudioEngine) {
        self.engine = engine
    }

    func render(times: Int) {
        guard let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024) else {
            return
        }
        for _ in 0..<times {
            _ = try? engine.renderOffline(1024, to: output)
        }
    }
}

/// Cancel sends nothing, so this is never called.
private struct NeverUploadAPI: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .retryLater
    }
}
