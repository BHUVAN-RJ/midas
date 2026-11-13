import AVFoundation
import Speech
import XCTest
@testable import Midas

/// Stands in for the microphone and the recogniser; counts what the transcriber asked for.
@MainActor
private final class AwaitFinalFakeEngine: SpeechRecognitionEngine {
    var isOnDeviceAvailable = true
    private(set) var audioStopCount = 0
    private(set) var recognitionCancelCount = 0

    func startAudio(tap: @escaping VoiceAudioTap) throws {}

    func stopAudio() {
        audioStopCount += 1
    }

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {}

    func cancelRecognition() {
        recognitionCancelCount += 1
    }
}

private struct GrantedPermissions: VoicePermissionSystem {
    let microphone: VoicePermissionAnswer = .granted
    let speech: VoicePermissionAnswer = .granted

    func requestMicrophone() async {}
    func requestSpeech() async {}
}

/// Collects what the transcriber delivers.
@MainActor
private final class AwaitFinalRecorder {
    private(set) var texts: [String] = []
    private(set) var ends: [VoiceTranscriptionEnd] = []
    let ended = XCTestExpectation(description: "listening ended")

    func receiveUpdate(_ transcript: VoiceTranscript) {
        texts.append(transcript.text)
    }

    func receiveEnd(_ reason: VoiceTranscriptionEnd) {
        ends.append(reason)
        ended.fulfill()
    }
}

/// `stopAndAwaitFinal` on the shared transcriber (dictation test, founder 2026-11-13): the
/// microphone stops at release, the recogniser keeps going until its final words, so release →
/// final text can be timed. `stop()` is unchanged (VoiceTranscriberTests).
@MainActor
final class VoiceTranscriberAwaitFinalTests: XCTestCase {
    private func startListening(options: VoiceTranscriberOptions, engine: AwaitFinalFakeEngine, recorder: AwaitFinalRecorder) async throws -> OnDeviceSpeechTranscriber {
        let transcriber = OnDeviceSpeechTranscriber(options: options, permissions: GrantedPermissions(), engine: engine)
        try await transcriber.start(sessionStartedAt: Date(), onUpdate: recorder.receiveUpdate, onEnd: recorder.receiveEnd)
        return transcriber
    }

    private static func words(_ text: String) -> VoiceTranscript {
        VoiceTranscript(text: text, words: [])
    }

    func testAwaitFinalStopsTheMicrophoneButKeepsTheRecogniser() async throws {
        let engine = AwaitFinalFakeEngine()
        let recorder = AwaitFinalRecorder()
        let transcriber = try await startListening(options: .longDictation, engine: engine, recorder: recorder)

        transcriber.stopAndAwaitFinal(timeout: .seconds(30))

        XCTAssertEqual(engine.audioStopCount, 1, "the microphone stops at release")
        XCTAssertEqual(engine.recognitionCancelCount, 0, "the recogniser is not cancelled before its final words")
        XCTAssertTrue(transcriber.isListening)
        XCTAssertTrue(transcriber.isAwaitingFinal)
        XCTAssertEqual(recorder.ends, [])
        transcriber.stop()
    }

    func testFinalWordsAfterReleaseAreDeliveredThenTheListenEnds() async throws {
        let engine = AwaitFinalFakeEngine()
        let recorder = AwaitFinalRecorder()
        let transcriber = try await startListening(options: .longDictation, engine: engine, recorder: recorder)
        transcriber.receive(.heard(Self.words("be there at")))

        transcriber.stopAndAwaitFinal(timeout: .seconds(30))
        transcriber.receive(.heard(Self.words("be there at 5")))
        transcriber.receive(.heardFinal(Self.words("be there at 5 no wait 6")))

        XCTAssertEqual(recorder.texts, ["be there at", "be there at 5", "be there at 5 no wait 6"])
        XCTAssertEqual(recorder.ends, [.recognizerFinished])
        XCTAssertFalse(transcriber.isListening)
        XCTAssertFalse(transcriber.isAwaitingFinal)
        XCTAssertEqual(engine.recognitionCancelCount, 1)
    }

    func testNoFinalWordsEndsAtTheTimeoutAsStopped() async throws {
        let engine = AwaitFinalFakeEngine()
        let recorder = AwaitFinalRecorder()
        let transcriber = try await startListening(options: .longDictation, engine: engine, recorder: recorder)
        transcriber.receive(.heard(Self.words("tell mom")))

        transcriber.stopAndAwaitFinal(timeout: .milliseconds(50))
        await fulfillment(of: [recorder.ended], timeout: 2)

        XCTAssertEqual(recorder.ends, [.stopped])
        XCTAssertFalse(transcriber.isListening)
    }

    func testSilenceDoesNotEndTheListenWhileWaitingForTheFinalWords() async throws {
        let engine = AwaitFinalFakeEngine()
        let recorder = AwaitFinalRecorder()
        let options = VoiceTranscriberOptions(endOfSpeechSilence: .milliseconds(30), maximumDuration: .seconds(60))
        let transcriber = try await startListening(options: options, engine: engine, recorder: recorder)

        transcriber.stopAndAwaitFinal(timeout: .seconds(30))
        // A partial result after release would restart the silence count without the guard
        transcriber.receive(.heard(Self.words("buy eggs")))
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(recorder.ends, [], "only the final words or the timeout end it, not silence")
        XCTAssertTrue(transcriber.isListening)
        transcriber.stop()
        XCTAssertEqual(recorder.ends, [.stopped])
    }

    func testAwaitFinalWhenNotListeningDoesNothing() {
        let engine = AwaitFinalFakeEngine()
        let transcriber = OnDeviceSpeechTranscriber(options: .longDictation, permissions: GrantedPermissions(), engine: engine)

        transcriber.stopAndAwaitFinal()

        XCTAssertFalse(transcriber.isAwaitingFinal)
        XCTAssertEqual(engine.audioStopCount, 0)
    }

    func testLongDictationNeverEndsOnSilenceAndAllowsTenMinutes() {
        XCTAssertNil(VoiceTranscriberOptions.longDictation.endOfSpeechSilence)
        XCTAssertEqual(VoiceTranscriberOptions.longDictation.maximumDuration, .seconds(600))
        XCTAssertEqual(VoiceTranscriberOptions.repair, VoiceTranscriberOptions(), "repair's options are unchanged")
    }
}
