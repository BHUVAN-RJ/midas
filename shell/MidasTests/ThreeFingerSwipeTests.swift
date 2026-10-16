import UIKit
import XCTest
@testable import Midas

/// The repair gesture (founder, 2026-10-15): three fingers swipe down, a gesture nobody makes by
/// accident. Fires once all three have gone far enough down; one or two fingers, a fourth finger,
/// swipes up or sideways (undo, redo), pinches, taps, short and slow swipes do not.
/// Thresholds: `SwipeDownThresholds.standard`.
final class ThreeFingerSwipeTests: XCTestCase {
    private struct CapturedStroke: Decodable {
        let points: [[Double]]
    }

    private struct Capture: Decodable {
        let strokes: [CapturedStroke]
    }

    /// One finger's straight move: lands at `landingMs`, travels `dx`, `dy` over `durationMs`.
    private struct FingerMove {
        var startX: Double
        var startY: Double = 300
        var dx: Double = 0
        var dy: Double
        var landingMs: Double = 0
        var durationMs: Double = 400
    }

    private struct Outcome {
        let verdict: ThreeFingerSwipeDetector.Verdict
        let atMs: Double
    }

    /// `count` fingers side by side, landing `landingGapMs` apart, each moving the same way.
    private static func swipe(count: Int = 3, dx: Double = 0, dy: Double, durationMs: Double = 400, landingGapMs: Double = 30) -> [FingerMove] {
        var fingers: [FingerMove] = []
        for index in 0..<count {
            fingers.append(FingerMove(startX: 120 + Double(index) * 55, dx: dx, dy: dy, landingMs: Double(index) * landingGapMs, durationMs: durationMs))
        }
        return fingers
    }

    /// Plays the fingers as touch events at `hz`, judging after each event the way the
    /// recogniser does; the fingers lift at the end, which fails anything still possible.
    private static func play(_ fingers: [FingerMove], hz: Double = 120) -> Outcome {
        let stepMs = 1000 / hz
        var endMs = 0.0
        for finger in fingers {
            endMs = max(endMs, finger.landingMs + finger.durationMs)
        }
        var nowMs = 0.0
        while nowMs <= endMs + stepMs {
            let tracks = tracksAt(fingers, nowMs: min(nowMs, endMs), stepMs: stepMs)
            let verdict = ThreeFingerSwipeDetector.verdict(tracks: tracks, nowMs: min(nowMs, endMs))
            if verdict != .possible {
                return Outcome(verdict: verdict, atMs: nowMs)
            }
            nowMs += stepMs
        }
        return Outcome(verdict: .failed, atMs: endMs)
    }

    private static func tracksAt(_ fingers: [FingerMove], nowMs: Double, stepMs: Double) -> [[RepairGesturePoint]] {
        var tracks: [[RepairGesturePoint]] = []
        for finger in fingers where finger.landingMs <= nowMs {
            var track: [RepairGesturePoint] = []
            var sampleMs = finger.landingMs
            while sampleMs <= nowMs {
                let progress = finger.durationMs > 0 ? min((sampleMs - finger.landingMs) / finger.durationMs, 1) : 1
                track.append(RepairGesturePoint(x: finger.startX + finger.dx * progress, y: finger.startY + finger.dy * progress, ms: sampleMs))
                sampleMs += stepMs
            }
            tracks.append(track)
        }
        return tracks
    }

    private func fires(_ fingers: [FingerMove], hz: Double = 120) -> Bool {
        Self.play(fingers, hz: hz).verdict == .recognized
    }

    // MARK: The swipe fires

    func testSwipeDownFiresAtSeveralSpeedsAndRates() {
        for durationMs in [200.0, 500.0, 800.0] {
            for hz in [60.0, 120.0] {
                XCTAssertTrue(fires(Self.swipe(dy: 150, durationMs: durationMs), hz: hz), "\(durationMs) ms at \(hz) Hz did not fire")
            }
        }
    }

    func testFiresOnceFarEnoughWithoutWaitingForTheLift() {
        // 300 pt over 600 ms passes 80 pt at about 160 ms
        let outcome = Self.play(Self.swipe(dy: 300, durationMs: 600))
        XCTAssertEqual(outcome.verdict, .recognized)
        XCTAssertLessThan(outcome.atMs, 300, "waited for the swipe to finish")
    }

    func testSlightlyAngledSwipeFires() {
        // About 18° off straight down, as a hand drags
        XCTAssertTrue(fires(Self.swipe(dx: 50, dy: 150)))
        XCTAssertTrue(fires(Self.swipe(dx: -50, dy: 150)))
    }

    func testFingersLandingAtSlightlyDifferentTimesFire() {
        XCTAssertTrue(fires(Self.swipe(dy: 150, landingGapMs: 90)))
    }

    func testTheShortestSwipeFires() {
        XCTAssertTrue(fires(Self.swipe(dy: 82)), "82 pt is above the 80 pt minimum")
    }

    // MARK: Not the swipe

    func testOneAndTwoFingerSwipesDoNotFire() {
        XCTAssertFalse(fires(Self.swipe(count: 1, dy: 200)), "a one-finger scroll fired")
        XCTAssertFalse(fires(Self.swipe(count: 2, dy: 200)), "a two-finger scroll fired")
    }

    func testFourFingersDoNotFire() {
        XCTAssertFalse(fires(Self.swipe(count: 4, dy: 200)))
    }

    func testThreeFingerSwipeUpDoesNotFire() {
        XCTAssertFalse(fires(Self.swipe(dy: -150)))
    }

    func testUndoAndRedoSwipesDoNotFire() {
        // iOS: three fingers left undo, right redo
        XCTAssertFalse(fires(Self.swipe(dx: -150, dy: 0)))
        XCTAssertFalse(fires(Self.swipe(dx: 150, dy: 0)))
        XCTAssertFalse(fires(Self.swipe(dx: 150, dy: 30)), "a sideways swipe drifting down fired")
    }

    func testSteepDiagonalDoesNotFire() {
        // About 39° off straight down
        XCTAssertFalse(fires(Self.swipe(dx: 120, dy: 150)))
    }

    func testShortSwipeDoesNotFire() {
        XCTAssertFalse(fires(Self.swipe(dy: 60)))
    }

    func testSlowSwipeDoesNotFire() {
        // Reaches 80 pt only at 1.6 s, past the 1 s window
        XCTAssertFalse(fires(Self.swipe(dy: 100, durationMs: 2000)))
    }

    func testFingersLandingFarApartDoNotFire() {
        XCTAssertFalse(fires(Self.swipe(dy: 150, landingGapMs: 300)))
    }

    func testThreeFingerTapDoesNotFire() {
        // iOS: a three-finger tap opens the edit shortcut bar
        XCTAssertFalse(fires(Self.swipe(dy: 1, durationMs: 80)))
    }

    func testPinchDoesNotFire() {
        // Fingers close in on each other: the bottom finger moves up
        let fingers = [
            FingerMove(startX: 120, startY: 200, dx: 40, dy: 100),
            FingerMove(startX: 200, startY: 250, dy: 100),
            FingerMove(startX: 280, startY: 500, dx: -40, dy: -100),
        ]
        XCTAssertFalse(fires(fingers))
    }

    func testOneFingerLaggingBehindDoesNotFire() {
        var fingers = Self.swipe(dy: 150)
        fingers[2].dy = 30
        XCTAssertFalse(fires(fingers))
    }

    func testTheFoundersScribbleSampleDoesNotFire() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sampleURL = repoRoot.appending(path: "docs/briefs/repair-gesture-sample-2026-10-13.json")
        let capture = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: sampleURL))
        let firstStroke = try XCTUnwrap(capture.strokes.first)
        let points = firstStroke.points.compactMap(RepairGesturePoint.init(array:))
        XCTAssertGreaterThan(points.count, 10, "sample did not load")
        let lastMs = try XCTUnwrap(points.last).ms
        XCTAssertEqual(ThreeFingerSwipeDetector.verdict(tracks: [points], nowMs: lastMs), .failed, "one finger, held past the landing window")
    }

    // MARK: Detector and recogniser

    func testDetectorWaitsBrieflyForTheOtherFingers() {
        let oneFinger = [[RepairGesturePoint(x: 100, y: 100, ms: 0)]]
        XCTAssertEqual(ThreeFingerSwipeDetector.verdict(tracks: oneFinger, nowMs: 100), .possible)
        XCTAssertEqual(ThreeFingerSwipeDetector.verdict(tracks: oneFinger, nowMs: 300), .failed)
        XCTAssertEqual(ThreeFingerSwipeDetector.verdict(tracks: [], nowMs: 0), .possible)
        XCTAssertEqual(ThreeFingerSwipeDetector.verdict(tracks: [[], [], []], nowMs: 0), .failed, "a finger with no points")
    }

    func testAFingerMovingUpEndsItAtOnce() {
        // A pinch or swipe up gives up early instead of waiting for the lift
        let tracks = [
            [RepairGesturePoint(x: 100, y: 300, ms: 0), RepairGesturePoint(x: 100, y: 330, ms: 100)],
            [RepairGesturePoint(x: 160, y: 300, ms: 20), RepairGesturePoint(x: 160, y: 330, ms: 100)],
            [RepairGesturePoint(x: 220, y: 300, ms: 40), RepairGesturePoint(x: 220, y: 270, ms: 100)],
        ]
        XCTAssertEqual(ThreeFingerSwipeDetector.verdict(tracks: tracks, nowMs: 100), .failed)
        var allDown = tracks
        allDown[2][1] = RepairGesturePoint(x: 220, y: 330, ms: 100)
        XCTAssertEqual(ThreeFingerSwipeDetector.verdict(tracks: allDown, nowMs: 100), .possible)
    }

    func testDefaultsAreTheProposedStartingPoint() {
        let standard = SwipeDownThresholds.standard
        XCTAssertEqual(standard.touchCount, 3)
        XCTAssertEqual(standard.maxLandingGapMs, 250)
        XCTAssertEqual(standard.minDownDistance, 80)
        XCTAssertEqual(standard.maxSidewaysShare, 0.5)
        XCTAssertEqual(standard.maxUpwardDistance, 20)
        XCTAssertEqual(standard.maxDurationMs, 1000)
    }

    @MainActor
    func testRecogniserIsPassive() {
        let recognizer = ThreeFingerSwipeRecognizer(target: nil, action: nil)
        XCTAssertFalse(recognizer.cancelsTouchesInView, "the swipe must never swallow the Sidekick's touches")
        XCTAssertFalse(recognizer.delaysTouchesBegan)
        XCTAssertFalse(recognizer.delaysTouchesEnded)
        let webViewPan = UIPanGestureRecognizer()
        XCTAssertFalse(recognizer.canPrevent(webViewPan), "the swipe must never stop the Sidekick's scroll")
        XCTAssertFalse(recognizer.canBePrevented(by: webViewPan))
        XCTAssertTrue(recognizer.gestureRecognizer(recognizer, shouldRecognizeSimultaneouslyWith: webViewPan))
    }

    func testTheSidekickWebViewListensForTheSwipe() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let appURL = testsDirectory.deletingLastPathComponent().appending(path: "Midas").appending(path: "MidasApp.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        XCTAssertTrue(appSource.contains("ThreeFingerSwipeRecognizer(target: coordinator"), "the web view no longer gets the swipe")
        XCTAssertFalse(appSource.contains("CircleGestureRecognizer"), "the circle is back")
        XCTAssertFalse(appSource.contains("Scribble"), "the scribble is back")
    }

    func testPointFromArrayRejectsMalformed() {
        XCTAssertNil(RepairGesturePoint(array: [1, 2]))
        XCTAssertEqual(RepairGesturePoint(array: [1, 2, 3]), RepairGesturePoint(x: 1, y: 2, ms: 3))
    }
}
