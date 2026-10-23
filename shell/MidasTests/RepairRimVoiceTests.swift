import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import Midas

/// L1 (founder, 2026-10-23: "I want to go with L1", docs/mockups/repair-feedback-2026-10-23.html
/// section 1c): the V1 rim also shows jess is listening. While the user speaks its line goes
/// 3 → 5.5 pt and its glow 70% → 100% (dark 60% → 95%), from the same microphone level as the
/// orb, smoothed 60 ms up / 260 ms down. Silent: plain V1. Typing: still. Reduce Motion: the width
/// stays, only the glow changes, in 200 ms.

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

    private func assertLook(_ look: RepairRimVoice.Look, width: CGFloat, keyline: CGFloat, glow: Double, radius: CGFloat, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(look.lineWidth, width, accuracy: 0.01, "\(what): line width", file: file, line: line)
        XCTAssertEqual(look.keylineWidth, keyline, accuracy: 0.01, "\(what): ink line width", file: file, line: line)
        XCTAssertEqual(look.glowOpacity, glow, accuracy: 0.001, "\(what): glow", file: file, line: line)
        XCTAssertEqual(look.glowRadius, radius, accuracy: 0.01, "\(what): glow radius", file: file, line: line)
    }

    // MARK: The look

    func testSilenceIsPlainV1() {
        let light = RepairRimVoice.look(level: 0, scheme: .light, reduceMotion: false)
        assertLook(light, width: 3, keyline: 6, glow: 0.7, radius: 6, "silent, light")
        let dark = RepairRimVoice.look(level: 0, scheme: .dark, reduceMotion: false)
        assertLook(dark, width: 3, keyline: 6, glow: 0.6, radius: 6, "silent, dark")
    }

    func testAFullVoiceGivesTheThickBrightRim() {
        let light = RepairRimVoice.look(level: 1, scheme: .light, reduceMotion: false)
        // 5.5 pt Volt over an ink line 3 pt wider; canvas blur 26 pt ≈ shadow radius 13
        assertLook(light, width: 5.5, keyline: 8.5, glow: 1, radius: 13, "full voice, light")
        let dark = RepairRimVoice.look(level: 1, scheme: .dark, reduceMotion: false)
        assertLook(dark, width: 5.5, keyline: 8.5, glow: 0.95, radius: 13, "full voice, dark")
    }

    func testTheRimGrowsInStepWithTheLevel() {
        let half = RepairRimVoice.look(level: 0.5, scheme: .light, reduceMotion: false)
        assertLook(half, width: 4.25, keyline: 7.25, glow: 0.85, radius: 9.5, "half voice")
        let tooLoud = RepairRimVoice.look(level: 3, scheme: .light, reduceMotion: false)
        assertLook(tooLoud, width: 5.5, keyline: 8.5, glow: 1, radius: 13, "levels above 1 are 1")
    }

    func testReduceMotionKeepsTheWidthAndChangesOnlyTheGlow() {
        let light = RepairRimVoice.look(level: 1, scheme: .light, reduceMotion: true)
        assertLook(light, width: 3, keyline: 6, glow: 1, radius: 6, "Reduce Motion, light")
        let dark = RepairRimVoice.look(level: 1, scheme: .dark, reduceMotion: true)
        assertLook(dark, width: 3, keyline: 6, glow: 0.95, radius: 6, "Reduce Motion, dark")
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
