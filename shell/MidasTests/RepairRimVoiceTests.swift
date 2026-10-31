import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import Midas

/// L1 (founder, 2026-10-23: "I want to go with L1", docs/mockups/repair-feedback-2026-10-23.html
/// section 1c): the rim also shows jess is listening, from the same microphone level as the orb,
/// smoothed 60 ms up / 260 ms down. Typing: still. Reduce Motion: only the glow changes, in 200 ms.
/// The look values are checked in RepairRimGlowPlusTests (G+1 replaced L1, founder 2026-10-23,
/// docs/briefs/repair-ux-upgrade.md).

/// Listens until stopped, with a microphone meter the test fills.
@MainActor
private final class RimMeteredTranscriber: RepairTranscribing {
    let meter = VoiceAudioLevelMeter()

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {}

    func stop() {}

    var audioLevelMeter: VoiceAudioLevelMeter? {
        meter
    }
}

private struct RimNoUpload: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .retryLater
    }
}

@MainActor
final class RepairRimVoiceTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-rim-voice-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private func makeSession(_ transcriber: RepairTranscribing) -> RepairSession {
        let uploader = RepairUploader(api: RimNoUpload(), outbox: RepairOutbox(directoryURL: outboxURL))
        let size = CGSize(width: 40, height: 80)
        let image = UIGraphicsImageRenderer(size: size).image(actions: Self.fillNothing)
        return RepairSession(sidekickId: "reminders", snapshot: image, viewSize: size, transcriber: transcriber, uploader: uploader)
    }

    private static func fillNothing(_ context: UIGraphicsImageRendererContext) {}

    /// A tenth of a second of sound at one loudness.
    private static func buffer(amplitude: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0..<1600 {
            samples[index] = index.isMultiple(of: 2) ? amplitude : -amplitude
        }
        return buffer
    }

    // MARK: Smoothing

    func testTheRimRisesIn60MsAndSettlesIn260Ms() {
        let follower = RepairRimVoiceFollower()
        let risen = follower.step(target: 1, elapsed: 0.06, reduceMotion: false)
        XCTAssertEqual(risen, 1 - exp(-1), accuracy: 0.01, "one attack time reaches 63%")
        for _ in 0..<40 {
            _ = follower.step(target: 1, elapsed: 0.016, reduceMotion: false)
        }
        XCTAssertEqual(follower.level, 1, accuracy: 0.01)
        let settled = follower.step(target: 0, elapsed: 0.26, reduceMotion: false)
        XCTAssertEqual(settled, exp(-1), accuracy: 0.01, "one release time falls to 37%")
    }

    func testReduceMotionCrossfadesIn200Ms() {
        let follower = RepairRimVoiceFollower()
        XCTAssertEqual(follower.step(target: 0.8, elapsed: 0.1, reduceMotion: true), 0.5, accuracy: 0.01, "halfway after 100 ms")
        XCTAssertEqual(follower.step(target: 0.8, elapsed: 0.1, reduceMotion: true), 1, accuracy: 0.01, "fully on after 200 ms")
        XCTAssertEqual(follower.step(target: 0.02, elapsed: 0.2, reduceMotion: true), 0, accuracy: 0.01, "back off in 200 ms when silent")
    }

    // MARK: The session's level

    func testTheRimFollowsTheOrbsLevelAndGoesStillWhileTyping() async throws {
        let transcriber = RimMeteredTranscriber()
        let session = makeSession(transcriber)
        await session.startListening()
        XCTAssertTrue(session.isListening)
        transcriber.meter.record(try Self.buffer(amplitude: 0.5))
        XCTAssertGreaterThan(session.orbLevel(), 0.9, "the test voice is loud")
        XCTAssertEqual(session.rimLevel(), session.orbLevel(), accuracy: 0.0001, "the rim reads the orb's level")
        session.isTyping = true
        XCTAssertEqual(session.rimLevel(), 0, "typing: the rim goes still, like the orb")
        session.isTyping = false
        XCTAssertFalse(session.isListening, "the keyboard stopped voice; it does not come back by itself")
        XCTAssertEqual(session.rimLevel(), 0, "voice stopped: the rim stays still until the orb is tapped")
        session.listenAgain()
        XCTAssertFalse(session.isTyping, "tapping the orb puts the keyboard down")
        for _ in 0..<100 where !session.isListening {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(session.isListening, "tapping the orb listens again")
        transcriber.meter.record(try Self.buffer(amplitude: 0.5))
        XCTAssertGreaterThan(session.rimLevel(), 0.9)
        transcriber.meter.record(try Self.buffer(amplitude: 0))
        XCTAssertEqual(session.rimLevel(), 0, accuracy: 0.0001, "silence: plain V1")
        transcriber.meter.record(try Self.buffer(amplitude: 0.5))
        session.cancel()
        XCTAssertEqual(session.rimLevel(), 0, "nothing listening: plain V1")
    }

    func testTheRimAndThePillAreWiredToTheSession() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let chrome = try String(contentsOf: root.appending(path: "Midas/RepairChromeView.swift"), encoding: .utf8)
        XCTAssertTrue(chrome.contains("session.rimLevel()"), "the rim must read the session's level")
        XCTAssertTrue(chrome.contains("RepairRimVoice.look("), "the rim must draw L1's look")
        let canvas = try String(contentsOf: root.appending(path: "Midas/RepairCanvasView.swift"), encoding: .utf8)
        XCTAssertTrue(canvas.contains("$session.isTyping"), "the pill's typing must reach the session, so the rim knows")
    }
}
