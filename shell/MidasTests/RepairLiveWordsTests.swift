import AVFoundation
import Speech
import UIKit
import XCTest
@testable import Midas

/// Staging report 06ed8ab8 (build 11, founder's iPhone, 2026-10-23): voice was captured (23 words)
/// but nothing showed in the pill while speaking, the orb did not move with the voice, and every
/// word had startMs = endMs = 209. Also: a late callback from the recogniser of an earlier listen
/// could end the listen that replaced it.

/// Stands in for the microphone and the recogniser; keeps every callback handed to iOS.
@MainActor
private final class KeepingSpeechEngine: SpeechRecognitionEngine {
    var isOnDeviceAvailable = true
    private(set) var tap: VoiceAudioTap?
    private(set) var resultHandlers: [VoiceRecognitionHandler] = []

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        self.tap = tap
    }

    func stopAudio() {}

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        resultHandlers.append(resultHandler)
    }

    func cancelRecognition() {}
}

private struct AllowedVoice: VoicePermissionSystem {
    let microphone: VoicePermissionAnswer = .granted
    let speech: VoicePermissionAnswer = .granted

    func requestMicrophone() async {}
    func requestSpeech() async {}
}

private struct NeverUploads: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .retryLater
    }
}

@MainActor
private final class UpdateRecorder {
    private(set) var updates: [VoiceTranscript] = []

    func receive(_ transcript: VoiceTranscript) {
        updates.append(transcript)
    }
}

@MainActor
private func makeTranscriber(_ engine: KeepingSpeechEngine) -> OnDeviceSpeechTranscriber {
    OnDeviceSpeechTranscriber(options: .repair, permissions: AllowedVoice(), engine: engine)
}

@MainActor
private func makeSession(_ transcriber: RepairTranscribing) -> RepairSession {
    let folder = FileManager.default.temporaryDirectory.appending(path: "repair-words-\(UUID().uuidString)")
    let uploader = RepairUploader(api: NeverUploads(), outbox: RepairOutbox(directoryURL: folder))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
    func fillWhite(_ context: UIGraphicsImageRendererContext) {
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
    }
    let snapshot = renderer.image(actions: fillWhite)
    return RepairSession(sidekickId: "reminders", snapshot: snapshot, viewSize: CGSize(width: 20, height: 30), transcriber: transcriber, uploader: uploader)
}

/// Words as iOS's partial results give them: every word at the listen's start, no length.
private func untimed(_ text: String, atMs: Int) -> VoiceTranscript {
    let pieces = text.split(separator: " ")
    var words: [VoiceWord] = []
    for piece in pieces {
        words.append(VoiceWord(word: String(piece), startMs: atMs, endMs: atMs))
    }
    return VoiceTranscript(text: text, words: words)
}

/// Waits up to 3 s for something the main actor will do soon.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<300 {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

// MARK: 1. Live words in the B3 pill

@MainActor
final class RepairPillWordsTests: XCTestCase {
    func testSpokenWordsShowInThePillAsTheyArrive() async throws {
        let engine = KeepingSpeechEngine()
        let transcriber = makeTranscriber(engine)
        let session = makeSession(transcriber)
        await session.startListening()
        transcriber.receive(.heard(VoiceTranscript(text: "the last", words: [VoiceWord(word: "the", startMs: 100, endMs: 200), VoiceWord(word: "last", startMs: 200, endMs: 400)])))
        let first = session.pillText(isTyping: false)
        XCTAssertEqual(first.settled, "the")
        XCTAssertEqual(first.pending, "last", "the newest word shows while jess may still change it")
        transcriber.receive(.heard(VoiceTranscript(text: "the last row", words: [VoiceWord(word: "the", startMs: 100, endMs: 200), VoiceWord(word: "last", startMs: 200, endMs: 400), VoiceWord(word: "row", startMs: 400, endMs: 600)])))
        let second = session.pillText(isTyping: false)
        XCTAssertEqual(second.settled, "the last")
        XCTAssertEqual(second.pending, "row")
        XCTAssertTrue(second.hasSpoken)
        XCTAssertEqual(second.placeholder, "", "no placeholder over spoken words")
        XCTAssertFalse(second.showsField, "only the spoken words show until the user taps to type")
        session.cancel()
    }

    func testTypingKeepsTheSpokenWordsAndSendsBoth() async throws {
        let engine = KeepingSpeechEngine()
        let transcriber = makeTranscriber(engine)
        let session = makeSession(transcriber)
        await session.startListening()
        transcriber.receive(.heard(VoiceTranscript(text: "the row is cut off", words: [VoiceWord(word: "the", startMs: 100, endMs: 200)])))
        let typing = session.pillText(isTyping: true)
        XCTAssertTrue(typing.showsField)
        XCTAssertTrue(typing.hasSpoken, "the spoken words stay while typing")
        XCTAssertEqual(typing.spokenLineLimit, RepairPillText.maxSpokenLines - 1)
        session.typedText = "on the right"
        let afterTyping = session.pillText(isTyping: false)
        XCTAssertTrue(afterTyping.showsField, "typed words stay visible after the keyboard goes")
        XCTAssertTrue(afterTyping.hasSpoken)
        let combined = RepairReportBuilder.combinedTranscript(spokenText: session.transcript.text, typedText: session.typedText)
        XCTAssertTrue(combined.contains("the row is cut off"))
        XCTAssertTrue(combined.contains("on the right"))
        session.cancel()
    }

    func testOnceListeningEndsEveryWordIsSettled() {
        let text = RepairPillText(spoken: "make it bigger", typed: "", isListening: false, isTyping: false)
        XCTAssertEqual(text.settled, "make it bigger")
        XCTAssertEqual(text.pending, "")
        XCTAssertEqual(text.spokenLineLimit, RepairPillText.maxSpokenLines)
    }

    func testWhatToFixOnlyWhenThereIsNeitherSpokenNorTyped() {
        let empty = RepairPillText(spoken: "", typed: "", isListening: true, isTyping: false)
        XCTAssertEqual(empty.placeholder, RepairCopy.textPlaceholder)
        XCTAssertTrue(empty.showsField)
        XCTAssertFalse(empty.hasSpoken)
        let spoken = RepairPillText(spoken: "bigger", typed: "", isListening: true, isTyping: false)
        XCTAssertEqual(spoken.placeholder, "")
        let spokenAndTyping = RepairPillText(spoken: "bigger", typed: "", isListening: true, isTyping: true)
        XCTAssertEqual(spokenAndTyping.placeholder, "")
    }

    /// The pill's source shows the spoken words, not only the typed text.
    func testThePillDrawsTheSpokenWords() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Midas/RepairCanvasView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("session.pillText(isTyping: isTyping)"), "the pill must draw RepairPillText")
        XCTAssertTrue(source.contains("spokenWords(text)"), "the pill must show the spoken words")
    }
}

// MARK: 2. The orb moves with the voice

@MainActor
final class RepairOrbLevelTests: XCTestCase {
    func testTheRepairOrbReadsTheMicrophonesLevel() async throws {
        let engine = KeepingSpeechEngine()
        let transcriber = makeTranscriber(engine)
        let session = makeSession(transcriber)
        await session.startListening()
        XCTAssertEqual(session.orbLevel(), 0, accuracy: 0.0001)
        let tap = try XCTUnwrap(engine.tap)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0..<160 {
            samples[index] = 0.5
        }
        tap(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
        XCTAssertGreaterThan(session.orbLevel(), 0.9, "a loud voice must reach the repair orb")
        session.cancel()
        XCTAssertEqual(session.orbLevel(), 0, accuracy: 0.0001, "silence once listening stops")
    }

    func testBothRepairOrbsAreGivenTheLevel() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Midas/RepairCanvasView.swift"), encoding: .utf8)
        let withLevel = source.components(separatedBy: "JessOrb(state: orbState, level: session.orbLevel)").count - 1
        let withoutLevel = source.components(separatedBy: "JessOrb(state: orbState)").count - 1
        XCTAssertEqual(withLevel, 2, "the floating orb and the pill's orb both move with the voice")
        XCTAssertEqual(withoutLevel, 0)
    }
}

// MARK: 3. Every word has its own time

@MainActor
final class RepairWordTimingTests: XCTestCase {
    func testUntimedWordsAreSpreadInOrderFromTheListensStart() {
        var clock = VoiceWordClock(listenStartMs: 209)
        let first = clock.timed(untimed("so what", atMs: 209), heardAtMs: 1209)
        XCTAssertEqual(first.words, [VoiceWord(word: "so", startMs: 209, endMs: 709), VoiceWord(word: "what", startMs: 709, endMs: 1209)])
        let second = clock.timed(untimed("so what I'm trying", atMs: 209), heardAtMs: 2009)
        XCTAssertEqual(second.words.map(\.word), ["so", "what", "I'm", "trying"])
        XCTAssertEqual(second.words.map(\.startMs), [209, 709, 1209, 1609])
        XCTAssertEqual(second.words.map(\.endMs), [709, 1209, 1609, 2009])
    }

    func testAWordRevisedLaterKeepsItsTime() {
        var clock = VoiceWordClock(listenStartMs: 0)
        _ = clock.timed(untimed("to big", atMs: 0), heardAtMs: 1000)
        let revised = clock.timed(untimed("too big", atMs: 0), heardAtMs: 3000)
        XCTAssertEqual(revised.words, [VoiceWord(word: "too", startMs: 0, endMs: 500), VoiceWord(word: "big", startMs: 500, endMs: 1000)])
    }

    func testRealTimingsAreKeptAsTheyAre() {
        var clock = VoiceWordClock(listenStartMs: 209)
        let timed = VoiceTranscript(text: "the tag", words: [VoiceWord(word: "the", startMs: 400, endMs: 600), VoiceWord(word: "tag", startMs: 600, endMs: 900)])
        XCTAssertEqual(clock.timed(timed, heardAtMs: 5000), timed)
    }

    /// The bug as the phone showed it: partial results with every word at 209 ms.
    func testWordsHeardOverTimeGetDifferentTimesInTheSession() async throws {
        let engine = KeepingSpeechEngine()
        let transcriber = makeTranscriber(engine)
        let session = makeSession(transcriber)
        await session.startListening()
        try await Task.sleep(for: .milliseconds(150))
        transcriber.receive(.heard(untimed("so what", atMs: 209)))
        try await Task.sleep(for: .milliseconds(300))
        transcriber.receive(.heard(untimed("so what I'm trying", atMs: 209)))
        try await Task.sleep(for: .milliseconds(300))
        transcriber.receive(.heard(untimed("so what I'm trying to send", atMs: 209)))
        let words = session.transcript.words
        XCTAssertEqual(words.map(\.word), ["so", "what", "I'm", "trying", "to", "send"])
        let starts = words.map(\.startMs)
        XCTAssertEqual(starts, starts.sorted(), "times must be in order")
        XCTAssertGreaterThan(Set(starts).count, 4, "words must not share one time")
        let spread = (words.last?.endMs ?? 0) - (words.first?.startMs ?? 0)
        XCTAssertGreaterThan(spread, 500, "times must spread over the listen")
        for word in words {
            XCTAssertGreaterThanOrEqual(word.endMs, word.startMs)
        }
        session.cancel()
    }
}

// MARK: A late callback from an earlier listen

@MainActor
final class RepairStaleCallbackTests: XCTestCase {
    func testALateErrorFromTheEarlierListenDoesNotEndTheNewOne() async throws {
        let engine = KeepingSpeechEngine()
        let transcriber = makeTranscriber(engine)
        let recorder = UpdateRecorder()
        try await transcriber.start(sessionStartedAt: Date(), onUpdate: recorder.receive, onEnd: nil)
        transcriber.stop()
        try await transcriber.start(sessionStartedAt: Date(), onUpdate: recorder.receive, onEnd: nil)
        XCTAssertEqual(engine.resultHandlers.count, 2)
        let earlier = engine.resultHandlers[0]
        // iOS reports the cancelled task's error on its own queue, after the new listen began
        DispatchQueue.global(qos: .userInitiated).async {
            earlier(nil, NSError(domain: "kLSRErrorDomain", code: 301))
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(transcriber.isListening, "the earlier listen's error ended the new one")
        XCTAssertNil(transcriber.lastFailure)
        transcriber.stop()
    }

    func testAfterARestartTheEarlierListensErrorLeavesTheLayerListening() async throws {
        let engine = KeepingSpeechEngine()
        let session = makeSession(makeTranscriber(engine))
        await session.startListening()
        let first = try XCTUnwrap(engine.resultHandlers.first)
        DispatchQueue.global(qos: .userInitiated).async {
            first(nil, NSError(domain: "kAFAssistantErrorDomain", code: 1101))
        }
        func listeningAgain() -> Bool {
            engine.resultHandlers.count == 2 && session.isListening
        }
        let restarted = await eventually(listeningAgain)
        XCTAssertTrue(restarted)
        // The first task's late cancellation error arrives after the restart
        DispatchQueue.global(qos: .userInitiated).async {
            first(nil, NSError(domain: "kLSRErrorDomain", code: 301))
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(session.isListening, "a stale error left the layer deaf")
        XCTAssertEqual(engine.resultHandlers.count, 2)
        XCTAssertEqual(session.voiceProblems, ["kAFAssistantErrorDomain 1101"])
        session.cancel()
    }
}
