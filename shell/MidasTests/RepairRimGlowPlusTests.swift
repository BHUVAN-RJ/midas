import SwiftUI
import UIKit
import XCTest
@testable import Midas

/// Build 14 on the phone (founder, 2026-10-23): "the L1 voice glow is not visible" and Undo /
/// Clear "can't be seen". Picked from docs/mockups/repair-feedback-2026-10-23.html section 1d:
/// G+1 "Thick rim + bloom" for the voice glow, B+2 "Frosted, like iOS controls" for Undo and Clear.

/// G+1: silent 4 pt Volt, 18 pt blur (shadow radius 9), glow 85% light / 80% dark, over an 8 pt
/// ink line in light mode; at full voice 8 pt, 40 pt blur (radius 20), glow 100%, ink line 12 pt,
/// and a Volt halo 2.6 × the line at 60%. Reduce Motion: width fixed, no halo, glow only.
@MainActor
final class RepairRimGlowPlusTests: XCTestCase {
    private func assertLook(_ look: RepairRimVoice.Look, width: CGFloat, keyline: CGFloat, glow: Double, radius: CGFloat, haloWidth: CGFloat, haloOpacity: Double, haloRadius: CGFloat, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(look.lineWidth, width, accuracy: 0.01, "\(what): line width", file: file, line: line)
        XCTAssertEqual(look.keylineWidth, keyline, accuracy: 0.01, "\(what): ink line width", file: file, line: line)
        XCTAssertEqual(look.glowOpacity, glow, accuracy: 0.001, "\(what): glow", file: file, line: line)
        XCTAssertEqual(look.glowRadius, radius, accuracy: 0.01, "\(what): glow radius", file: file, line: line)
        XCTAssertEqual(look.haloWidth, haloWidth, accuracy: 0.01, "\(what): halo width", file: file, line: line)
        XCTAssertEqual(look.haloOpacity, haloOpacity, accuracy: 0.001, "\(what): halo", file: file, line: line)
        XCTAssertEqual(look.haloRadius, haloRadius, accuracy: 0.01, "\(what): halo radius", file: file, line: line)
    }

    func testSilentRimIsBrighterThanV1() {
        let light = RepairRimVoice.look(level: 0, scheme: .light, reduceMotion: false)
        assertLook(light, width: 4, keyline: 8, glow: 0.85, radius: 9, haloWidth: 10.4, haloOpacity: 0, haloRadius: 10.8, "silent, light")
        let dark = RepairRimVoice.look(level: 0, scheme: .dark, reduceMotion: false)
        assertLook(dark, width: 4, keyline: 8, glow: 0.8, radius: 9, haloWidth: 10.4, haloOpacity: 0, haloRadius: 10.8, "silent, dark")
    }

    func testFullVoiceIsTheThickRimWithItsHalo() {
        let light = RepairRimVoice.look(level: 1, scheme: .light, reduceMotion: false)
        assertLook(light, width: 8, keyline: 12, glow: 1, radius: 20, haloWidth: 20.8, haloOpacity: 0.6, haloRadius: 24, "full voice, light")
        let dark = RepairRimVoice.look(level: 1, scheme: .dark, reduceMotion: false)
        assertLook(dark, width: 8, keyline: 12, glow: 1, radius: 20, haloWidth: 20.8, haloOpacity: 0.6, haloRadius: 24, "full voice, dark")
    }

    func testTheRimGrowsInStepAndStopsAtFull() {
        let half = RepairRimVoice.look(level: 0.5, scheme: .light, reduceMotion: false)
        assertLook(half, width: 6, keyline: 10, glow: 0.925, radius: 14.5, haloWidth: 15.6, haloOpacity: 0.3, haloRadius: 17.4, "half voice")
        let tooLoud = RepairRimVoice.look(level: 3, scheme: .light, reduceMotion: false)
        assertLook(tooLoud, width: 8, keyline: 12, glow: 1, radius: 20, haloWidth: 20.8, haloOpacity: 0.6, haloRadius: 24, "levels above 1 are 1")
    }

    func testReduceMotionKeepsTheWidthAndDropsTheHalo() {
        let light = RepairRimVoice.look(level: 1, scheme: .light, reduceMotion: true)
        assertLook(light, width: 4, keyline: 8, glow: 1, radius: 9, haloWidth: 10.4, haloOpacity: 0, haloRadius: 10.8, "Reduce Motion, light")
        let dark = RepairRimVoice.look(level: 0, scheme: .dark, reduceMotion: true)
        assertLook(dark, width: 4, keyline: 8, glow: 0.8, radius: 9, haloWidth: 10.4, haloOpacity: 0, haloRadius: 10.8, "Reduce Motion silent, dark")
    }

    // MARK: How loud is loud

    /// The meter maps −50…−10 dB RMS onto 0…1, so normal speech near the phone (about −32 to
    /// −25 dB RMS) reads 0.45–0.63: the rim was never near its full look. The rim takes the level
    /// over 0.7 (−22 dB) as full; the orb keeps the meter's own level.
    func testNormalSpeechDrivesTheRimTo60To90Percent() {
        for decibels in stride(from: Float(-32), through: -25, by: 1) {
            let rootMeanSquare = pow(10, decibels / 20)
            let meter = Double(VoiceAudioLevelMeter.level(fromRootMeanSquare: rootMeanSquare))
            let drive = RepairRimVoice.drive(meter)
            XCTAssertGreaterThanOrEqual(drive, 0.6, "\(decibels) dB is normal speech: the rim must show it")
            XCTAssertLessThanOrEqual(drive, 0.9, "\(decibels) dB is normal speech, not shouting")
        }
    }

    func testTheRimsCurve() {
        XCTAssertEqual(RepairRimVoice.drive(0), 0)
        XCTAssertEqual(RepairRimVoice.drive(0.35), 0.5, accuracy: 0.001)
        XCTAssertEqual(RepairRimVoice.drive(0.7), 1, accuracy: 0.001)
        XCTAssertEqual(RepairRimVoice.drive(1), 1)
        XCTAssertEqual(RepairRimVoice.drive(-1), 0)
    }

    /// The orb's own level is the meter's, unchanged.
    func testTheOrbKeepsTheMetersMapping() {
        let rootMeanSquare = pow(Float(10), -30 / 20)
        XCTAssertEqual(VoiceAudioLevelMeter.level(fromRootMeanSquare: rootMeanSquare), 0.5, accuracy: 0.001)
        XCTAssertEqual(VoiceAudioLevelMeter.quietDecibels, -50)
        XCTAssertEqual(VoiceAudioLevelMeter.loudDecibels, -10)
    }

    func testTheRimDrawsTheCurveAndTheHalo() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let chrome = try String(contentsOf: root.appending(path: "Midas/RepairChromeView.swift"), encoding: .utf8)
        XCTAssertTrue(chrome.contains("RepairRimVoice.drive("), "the rim must take the session's level through its curve")
        XCTAssertTrue(chrome.contains("look.haloWidth"), "the rim must draw G+1's halo")
    }
}

/// B+2: Undo and Clear as frosted pills (`.regularMaterial`), a hairline edge (ink 12% light,
/// white 18% dark), ink words in light and white in dark. On only when something is drawn; off
/// they stay readable at 60% (light) / 50% (dark).
@MainActor
final class RepairUndoClearPillTests: XCTestCase {
    func testOnOnlyWhenSomethingIsDrawn() {
        XCTAssertFalse(RepairMiniPillStyle.isOn(strokeCount: 0))
        XCTAssertTrue(RepairMiniPillStyle.isOn(strokeCount: 1))
        XCTAssertTrue(RepairMiniPillStyle.isOn(strokeCount: 7))
    }

    func testWordsAreFullOnAndDimmedButReadableOff() {
        XCTAssertEqual(RepairMiniPillStyle.wordOpacity(isOn: true, scheme: .light), 1)
        XCTAssertEqual(RepairMiniPillStyle.wordOpacity(isOn: true, scheme: .dark), 1)
        XCTAssertEqual(RepairMiniPillStyle.wordOpacity(isOn: false, scheme: .light), 0.6, accuracy: 0.001)
        XCTAssertEqual(RepairMiniPillStyle.wordOpacity(isOn: false, scheme: .dark), 0.5, accuracy: 0.001)
    }

    /// WCAG contrast of the off words on the pill: light #111111 at 60% on white, dark white at
    /// 50% on the dark frost (#2C2C2E at 78% over black).
    func testOffWordsStillReach45To1() {
        let lightOff = Self.mix(0x11, over: 0xFF, alpha: RepairMiniPillStyle.wordOpacity(isOn: false, scheme: .light))
        XCTAssertGreaterThanOrEqual(Self.contrast(lightOff, 0xFF), 4.4, "off words in light mode must stay readable")
        let frost = Self.mix(0x2D, over: 0x00, alpha: 0.78)
        let darkOff = Self.mix(0xFF, over: frost, alpha: RepairMiniPillStyle.wordOpacity(isOn: false, scheme: .dark))
        XCTAssertGreaterThanOrEqual(Self.contrast(darkOff, frost), 4.5, "off words in dark mode must stay readable")
    }

    func testTheEdgeIsAHairline() {
        let light = RepairMiniPillStyle.edge(for: .light)
        XCTAssertEqual(light, JessOrbColor(hex: 0x111111, alpha: 0.12))
        let dark = RepairMiniPillStyle.edge(for: .dark)
        XCTAssertEqual(dark, JessOrbColor(hex: 0xFFFFFF, alpha: 0.18))
    }

    func testThePillsAreFrostedAndFollowTheStrokes() throws {
        XCTAssertTrue(RepairMiniPillStyle.usesMaterial)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let canvas = try String(contentsOf: root.appending(path: "Midas/RepairCanvasView.swift"), encoding: .utf8)
        XCTAssertTrue(canvas.contains(".regularMaterial"), "Undo and Clear must be frosted")
        XCTAssertTrue(canvas.contains("RepairMiniPillStyle.isOn(strokeCount: session.strokes.count)"), "on only when something is drawn")
        XCTAssertTrue(canvas.contains("RepairMiniPillStyle.wordOpacity("), "off words dim, not grey out")
        XCTAssertFalse(canvas.contains("isOff ? tokens.ink3.color"), "the 2.8:1 grey is gone")
    }

    // MARK: Contrast

    private static func mix(_ foreground: Double, over background: Double, alpha: Double) -> Double {
        foreground * alpha + background * (1 - alpha)
    }

    private static func luminance(_ channel: Double) -> Double {
        let value = channel / 255
        let linear = value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        return linear
    }

    private static func contrast(_ first: Double, _ second: Double) -> Double {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
