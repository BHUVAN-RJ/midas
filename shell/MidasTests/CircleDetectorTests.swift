import UIKit
import XCTest
@testable import Midas

/// The repair circle (founder, 2026-10-15): one finger, either direction, judged when the finger
/// lifts. Circles of a few sizes fire; taps, drags, scrolls, zigzags and the old scribble do not.
/// Thresholds: `CircleThresholds.standard`.
final class CircleDetectorTests: XCTestCase {
    private struct CapturedStroke: Decodable {
        let points: [[Double]]
    }

    private struct Capture: Decodable {
        let strokes: [CapturedStroke]
    }

    /// A drawn loop: an ellipse traced from `startDegrees` through `sweepDegrees` (negative turns
    /// the other way), sampled at `hz`, with a regular wobble of `wobble` points like a finger's.
    private static func loop(centerX: Double = 200, centerY: Double = 400, radiusX: Double, radiusY: Double? = nil, startDegrees: Double = 0, sweepDegrees: Double = 360, durationMs: Double = 700, hz: Double = 120, wobble: Double = 0) -> [RepairGesturePoint] {
        let sampleCount = max(Int(durationMs / 1000 * hz), 2)
        let verticalRadius = radiusY ?? radiusX
        var points: [RepairGesturePoint] = []
        for index in 0...sampleCount {
            let progress = Double(index) / Double(sampleCount)
            let angle = (startDegrees + sweepDegrees * progress) * .pi / 180
            let wobbleOffset = wobble * sin(angle * 7)
            let x = centerX + (radiusX + wobbleOffset) * cos(angle)
            let y = centerY + (verticalRadius + wobbleOffset) * sin(angle)
            points.append(RepairGesturePoint(x: x, y: y, ms: durationMs * progress))
        }
        return points
    }

    private static func stroke(_ coordinates: [(Double, Double)], msApart: Double = 16) -> [RepairGesturePoint] {
        var points: [RepairGesturePoint] = []
        for (index, coordinate) in coordinates.enumerated() {
            points.append(RepairGesturePoint(x: coordinate.0, y: coordinate.1, ms: Double(index) * msApart))
        }
        return points
    }

    private func isCircle(_ points: [RepairGesturePoint]) -> Bool {
        CircleDetector.isCircle(points: points)
    }

    // MARK: Circles fire

    func testCirclesFireInBothDirectionsAtSeveralSizesAndRates() {
        for sweep in [360.0, -360.0] {
            for radius in [45.0, 90.0, 160.0] {
                for hz in [60.0, 120.0] {
                    let points = Self.loop(radiusX: radius, sweepDegrees: sweep, hz: hz)
                    XCTAssertTrue(isCircle(points), "circle of radius \(radius), sweep \(sweep), \(hz) Hz did not fire")
                }
            }
        }
    }

    func testCirclesStartingAnywhereFire() {
        for start in stride(from: 0.0, to: 360.0, by: 45.0) {
            XCTAssertTrue(isCircle(Self.loop(radiusX: 80, startDegrees: start)), "circle starting at \(start)° did not fire")
        }
    }

    func testAHandDrawnCircleFires() {
        // Wider than tall, wobbling 4 pt, overlapping its start by 20°, at the thumb's pace
        let points = Self.loop(radiusX: 75, radiusY: 58, sweepDegrees: -380, durationMs: 900, wobble: 4)
        XCTAssertTrue(isCircle(points))
    }

    func testANearlyClosedCircleFires() {
        // 330°: the end comes back within a third of the width, and it turned over 300°
        XCTAssertTrue(isCircle(Self.loop(radiusX: 80, sweepDegrees: 330)))
    }

    func testTheSmallestCircleFires() {
        XCTAssertTrue(isCircle(Self.loop(radiusX: 41)), "an 82 pt circle is above the 80 pt minimum")
    }

    // MARK: Not a circle

    func testOpenArcsDoNotFire() {
        for sweep in [180.0, 270.0, 290.0] {
            XCTAssertFalse(isCircle(Self.loop(radiusX: 80, sweepDegrees: sweep)), "a \(sweep)° arc fired")
        }
    }

    func testSmallCirclesAndWobblesDoNotFire() {
        XCTAssertFalse(isCircle(Self.loop(radiusX: 35)), "a 70 pt circle is under the minimum")
        XCTAssertFalse(isCircle(Self.loop(radiusX: 8, durationMs: 400)), "a finger wobble fired")
    }

    func testFlatLoopsDoNotFire() {
        // Wide but only 40 pt tall: a scroll that swerved, not a circle
        XCTAssertFalse(isCircle(Self.loop(radiusX: 120, radiusY: 20)))
    }

    func testTooFastAndTooSlowDoNotFire() {
        XCTAssertFalse(isCircle(Self.loop(radiusX: 80, durationMs: 150)), "150 ms is a flick")
        XCTAssertFalse(isCircle(Self.loop(radiusX: 80, durationMs: 2500)), "2.5 s is a slow drag")
    }

    func testFigureEightDoesNotFire() {
        // Turns one way, then the other: no net turn
        let firstLoop = Self.loop(centerX: 150, radiusX: 50, startDegrees: 0, sweepDegrees: 360, durationMs: 500)
        let secondLoop = Self.loop(centerX: 250, radiusX: 50, startDegrees: 180, sweepDegrees: -360, durationMs: 500)
        var points = firstLoop
        for point in secondLoop {
            points.append(RepairGesturePoint(x: point.x, y: point.y, ms: point.ms + 500))
        }
        XCTAssertFalse(isCircle(points))
    }

    func testTapDoesNotFire() {
        XCTAssertFalse(isCircle(Self.stroke([(100, 100), (100.5, 100.2), (100.5, 100.2)])))
        XCTAssertFalse(isCircle([]))
    }

    func testStraightDragsAndSwipesDoNotFire() {
        var horizontal: [(Double, Double)] = []
        var diagonal: [(Double, Double)] = []
        for index in 0..<25 {
            horizontal.append((20 + Double(index) * 12, 300))
            diagonal.append((40 + Double(index) * 10, 200 + Double(index) * 14))
        }
        XCTAssertFalse(isCircle(Self.stroke(horizontal)))
        XCTAssertFalse(isCircle(Self.stroke(diagonal)))
    }

    func testVerticalScrollWithJitterDoesNotFire() {
        // A list scroll: y moves 300 pt, x wobbles ±3 pt, the usual thumb jitter
        var coordinates: [(Double, Double)] = []
        for index in 0..<40 {
            let wobble: Double = index % 2 == 0 ? -3 : 3
            coordinates.append((200 + wobble, 100 + Double(index) * 8))
        }
        XCTAssertFalse(isCircle(Self.stroke(coordinates)))
    }

    func testPullDownThenUpDoesNotFire() {
        // Ends where it started, but turned once by 180° and never left a line
        var coordinates: [(Double, Double)] = []
        for index in 0..<20 {
            coordinates.append((200, 100 + Double(index) * 10))
        }
        for index in 0..<20 {
            coordinates.append((200, 300 - Double(index) * 10))
        }
        XCTAssertFalse(isCircle(Self.stroke(coordinates)))
    }

    func testZigzagDoesNotFire() {
        // The old scribble at phone speed: 5 legs of 150 pt drifting down, back to near the start
        var coordinates: [(Double, Double)] = []
        for index in 0..<30 {
            let leg = index / 6
            let step = Double(index % 6) * 25
            let x: Double = leg % 2 == 0 ? 60 + step : 210 - step
            coordinates.append((x, 300 + Double(index) * 5))
        }
        XCTAssertFalse(isCircle(Self.stroke(coordinates, msApart: 12)))
    }

    func testTheFoundersScribbleSampleDoesNotFire() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sampleURL = repoRoot.appending(path: "docs/briefs/repair-gesture-sample-2026-10-13.json")
        let capture = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: sampleURL))
        let firstStroke = try XCTUnwrap(capture.strokes.first)
        let points = firstStroke.points.compactMap(RepairGesturePoint.init(array:))
        XCTAssertGreaterThan(points.count, 10, "sample did not load")
        XCTAssertFalse(isCircle(points))
    }

    // MARK: Detector and recogniser

    func testDetectorGivesUpOnceTooSlow() {
        var detector = CircleDetector()
        detector.add(RepairGesturePoint(x: 0, y: 0, ms: 0))
        detector.add(RepairGesturePoint(x: 10, y: 0, ms: 1900))
        XCTAssertFalse(detector.hasFailed)
        detector.add(RepairGesturePoint(x: 20, y: 0, ms: 2100))
        XCTAssertTrue(detector.hasFailed, "past 2 s the recogniser should stop watching")
    }

    func testDetectorJudgesTheWholeStroke() {
        var detector = CircleDetector()
        for point in Self.loop(radiusX: 80, sweepDegrees: 180) {
            detector.add(point)
        }
        XCTAssertFalse(detector.isCircle, "half way round is not yet a circle")
        for point in Self.loop(radiusX: 80, startDegrees: 180, sweepDegrees: 180).dropFirst() {
            detector.add(RepairGesturePoint(x: point.x, y: point.y, ms: point.ms + 700))
        }
        XCTAssertTrue(detector.isCircle)
    }

    func testDefaultsAreTheFoundersStartingPoint() {
        let standard = CircleThresholds.standard
        XCTAssertEqual(standard.minTurnDegrees, 300)
        XCTAssertEqual(standard.maxClosureShare, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(standard.minDiameter, 80)
        XCTAssertEqual(standard.minDurationMs, 200)
        XCTAssertEqual(standard.maxDurationMs, 2000)
    }

    @MainActor
    func testRecogniserIsPassive() {
        let recognizer = CircleGestureRecognizer(target: nil, action: nil)
        XCTAssertFalse(recognizer.cancelsTouchesInView, "the circle must never swallow the Sidekick's touches")
        XCTAssertFalse(recognizer.delaysTouchesBegan)
        XCTAssertFalse(recognizer.delaysTouchesEnded)
        let webViewPan = UIPanGestureRecognizer()
        XCTAssertFalse(recognizer.canPrevent(webViewPan), "the circle must never stop the Sidekick's scroll")
        XCTAssertFalse(recognizer.canBePrevented(by: webViewPan))
        XCTAssertTrue(recognizer.gestureRecognizer(recognizer, shouldRecognizeSimultaneouslyWith: webViewPan))
    }

    func testTheSidekickWebViewListensForTheCircle() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let appURL = testsDirectory.deletingLastPathComponent().appending(path: "Midas").appending(path: "MidasApp.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        XCTAssertTrue(appSource.contains("CircleGestureRecognizer(target: coordinator"), "the web view no longer gets the circle")
        XCTAssertFalse(appSource.contains("Scribble"), "the scribble is back")
    }

    func testPointFromArrayRejectsMalformed() {
        XCTAssertNil(RepairGesturePoint(array: [1, 2]))
        XCTAssertEqual(RepairGesturePoint(array: [1, 2, 3]), RepairGesturePoint(x: 1, y: 2, ms: 3))
    }
}
