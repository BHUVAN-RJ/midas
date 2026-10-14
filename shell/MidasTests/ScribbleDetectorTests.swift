import XCTest
@testable import Midas

/// The repair scribble (founder, 2026-10-13): the founder's recorded sample is accepted, mid-stroke;
/// ordinary scrolls, swipes, taps and drags are not. Thresholds: `ScribbleThresholds.standard`.
final class ScribbleDetectorTests: XCTestCase {
    private struct CapturedStroke: Decodable {
        let points: [[Double]]
    }

    private struct Capture: Decodable {
        let strokes: [CapturedStroke]
    }

    /// docs/briefs/repair-gesture-sample-2026-10-13.json: one mouse stroke, ~1.1 s, 3 zigzags.
    private func founderSample() throws -> [ScribblePoint] {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sampleURL = repoRoot.appending(path: "docs/briefs/repair-gesture-sample-2026-10-13.json")
        let data = try Data(contentsOf: sampleURL)
        let capture = try JSONDecoder().decode(Capture.self, from: data)
        let firstStroke = try XCTUnwrap(capture.strokes.first)
        return firstStroke.points.compactMap(ScribblePoint.init(array:))
    }

    // MARK: Founder's sample

    func testFounderSampleIsRecognised() throws {
        let points = try founderSample()
        XCTAssertGreaterThan(points.count, 10, "sample did not load")
        XCTAssertTrue(ScribbleDetector.recognises(points: points))
    }

    func testFounderSampleFiresBeforeTheFingerLifts() throws {
        let points = try founderSample()
        let lastMs = try XCTUnwrap(points.last).ms
        let firedAt = try XCTUnwrap(ScribbleDetector.firingTime(points: points))
        XCTAssertLessThan(firedAt, lastMs, "should fire mid-stroke, not on lift")
        XCTAssertGreaterThanOrEqual(firedAt, ScribbleThresholds.standard.minDurationMs)
    }

    func testDetectorFiresExactlyOnce() throws {
        var detector = ScribbleDetector()
        var fireCount = 0
        for point in try founderSample() {
            if detector.add(point) {
                fireCount += 1
            }
        }
        XCTAssertEqual(fireCount, 1)
        XCTAssertTrue(detector.isRecognised)
    }

    // MARK: Things that are not the scribble

    private func makeStroke(_ coordinates: [(Double, Double)], msApart: Double = 16) -> [ScribblePoint] {
        var points: [ScribblePoint] = []
        for (index, coordinate) in coordinates.enumerated() {
            points.append(ScribblePoint(x: coordinate.0, y: coordinate.1, ms: Double(index) * msApart))
        }
        return points
    }

    func testVerticalScrollWithJitterIsRejected() {
        // A list scroll: y moves 300 pt, x wobbles ±3 pt, the usual thumb jitter.
        var coordinates: [(Double, Double)] = []
        for index in 0..<40 {
            let wobble: Double = index % 2 == 0 ? -3 : 3
            coordinates.append((200 + wobble, 100 + Double(index) * 8))
        }
        XCTAssertFalse(ScribbleDetector.recognises(points: makeStroke(coordinates)))
    }

    func testPullDownThenUpIsRejected() {
        // Reminders pulls between lists: down then back up, reversing on y only.
        var coordinates: [(Double, Double)] = []
        for index in 0..<20 {
            coordinates.append((200, 100 + Double(index) * 10))
        }
        for index in 0..<20 {
            coordinates.append((200, 300 - Double(index) * 10))
        }
        XCTAssertFalse(ScribbleDetector.recognises(points: makeStroke(coordinates)))
    }

    func testHorizontalSwipeIsRejected() {
        var coordinates: [(Double, Double)] = []
        for index in 0..<25 {
            coordinates.append((20 + Double(index) * 12, 300))
        }
        XCTAssertFalse(ScribbleDetector.recognises(points: makeStroke(coordinates)))
    }

    func testTapIsRejected() {
        let tap = makeStroke([(100, 100), (100.5, 100.2), (100.5, 100.2)])
        XCTAssertFalse(ScribbleDetector.recognises(points: tap))
    }

    func testSingleVIsRejected() {
        // One reversal: right 140 pt, then back.
        var coordinates: [(Double, Double)] = []
        for index in 0..<15 {
            coordinates.append((50 + Double(index) * 10, 300))
        }
        for index in 0..<15 {
            coordinates.append((200 - Double(index) * 10, 300))
        }
        XCTAssertFalse(ScribbleDetector.recognises(points: makeStroke(coordinates)))
    }

    func testTinyZigzagIsRejected() {
        // Legs of 30 pt: a wobble, under the 60 pt minimum.
        var coordinates: [(Double, Double)] = []
        for index in 0..<12 {
            let x: Double = index % 2 == 0 ? 100 : 130
            coordinates.append((x, 300))
        }
        XCTAssertFalse(ScribbleDetector.recognises(points: makeStroke(coordinates, msApart: 50)))
    }

    func testSlowZigzagIsRejected() {
        // The right shape over 4.8 s: a drag, not a scribble.
        var coordinates: [(Double, Double)] = []
        for index in 0..<40 {
            let x: Double = (index / 10) % 2 == 0 ? 100 : 250
            coordinates.append((x, 300))
        }
        XCTAssertFalse(ScribbleDetector.recognises(points: makeStroke(coordinates, msApart: 120)))
    }

    func testFastThumbZigzagIsRecognised() {
        // A phone scribble: 5 legs of 150 pt at 120 Hz, drifting down the screen.
        var coordinates: [(Double, Double)] = []
        for index in 0..<30 {
            let leg = index / 6
            let step = Double(index % 6) * 25
            let x: Double = leg % 2 == 0 ? 60 + step : 210 - step
            coordinates.append((x, 300 + Double(index) * 5))
        }
        let points = makeStroke(coordinates, msApart: 12)
        XCTAssertTrue(ScribbleDetector.recognises(points: points))
    }

    func testTwoFingersNeverReachTheDetector() {
        // Guarded by the recogniser, not the detector; the detector itself has no finger count.
        // Documented here so the rule is not lost: see ScribbleGestureRecognizer.touchesBegan.
        let recognizer = ScribbleGestureRecognizer(target: nil, action: nil)
        XCTAssertFalse(recognizer.cancelsTouchesInView, "the scribble must never swallow the Sidekick's touches")
        XCTAssertFalse(recognizer.delaysTouchesBegan)
    }

    func testPointFromArrayRejectsMalformed() {
        XCTAssertNil(ScribblePoint(array: [1, 2]))
        XCTAssertEqual(ScribblePoint(array: [1, 2, 3]), ScribblePoint(x: 1, y: 2, ms: 3))
    }
}
