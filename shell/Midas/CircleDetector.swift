import Foundation

/// One sampled touch point of the repair gesture: screen points and milliseconds since the touch
/// began. Same shape as the founder's capture page (`[x, y, ms]`).
struct RepairGesturePoint: Equatable, Sendable {
    let x: Double
    let y: Double
    let ms: Double

    init(x: Double, y: Double, ms: Double) {
        self.x = x
        self.y = y
        self.ms = ms
    }

    /// From a `[x, y, ms]` array as the capture page stores it; nil if malformed.
    init?(array: [Double]) {
        guard array.count == 3 else {
            return nil
        }
        self.init(x: array[0], y: array[1], ms: array[2])
    }
}

/// Numbers the circle is tuned with, all in one place for the phone captures (founder,
/// 2026-10-15: defaults to start from).
struct CircleThresholds: Equatable, Sendable {
    /// How far the path must turn, in degrees, either direction. A full circle is 360.
    var minTurnDegrees: Double = 300
    /// The end must come back within this share of the circle's width from the start.
    var maxClosureShare: Double = 1.0 / 3.0
    /// Both the width and the height of the circle, in points: taps, scrolls and small wobbles
    /// are narrower than this on at least one side.
    var minDiameter: Double = 80
    var minDurationMs: Double = 200
    var maxDurationMs: Double = 2000
    /// Samples closer than this to the last kept one are skipped, so finger jitter and the
    /// sample rate (60 to 120 Hz) do not add false turning.
    var minStepDistance: Double = 4

    static let standard = CircleThresholds()
}

/// Recognises the repair gesture (founder, 2026-10-15): one finger draws a circle, either
/// direction, anywhere on the Sidekick. Judged when the finger lifts (founder, 2026-10-15), from
/// the whole stroke: how far it turned, how closed it is, how big and how long.
struct CircleDetector: Sendable {
    let thresholds: CircleThresholds
    private(set) var points: [RepairGesturePoint] = []

    init(thresholds: CircleThresholds = .standard) {
        self.thresholds = thresholds
    }

    mutating func add(_ point: RepairGesturePoint) {
        points.append(point)
    }

    /// True once this stroke has gone on too long to be the circle, so the recogniser can stop
    /// watching before the finger lifts.
    var hasFailed: Bool {
        guard let first = points.first, let last = points.last else {
            return false
        }
        return last.ms - first.ms > thresholds.maxDurationMs
    }

    /// Whether the stroke so far, taken as finished, is the circle.
    var isCircle: Bool {
        Self.isCircle(points: points, thresholds: thresholds)
    }

    static func isCircle(points: [RepairGesturePoint], thresholds: CircleThresholds = .standard) -> Bool {
        guard let first = points.first, let last = points.last else {
            return false
        }
        let durationMs = last.ms - first.ms
        guard durationMs >= thresholds.minDurationMs, durationMs <= thresholds.maxDurationMs else {
            return false
        }
        let bounds = Self.bounds(of: points)
        guard bounds.width >= thresholds.minDiameter, bounds.height >= thresholds.minDiameter else {
            return false
        }
        let diameter = (bounds.width + bounds.height) / 2
        let closure = Self.distance(first, last)
        guard closure <= diameter * thresholds.maxClosureShare else {
            return false
        }
        // Net turn: a zigzag or a figure eight turns back as far as it turns, so it nets out
        let turning = Self.netTurning(of: Self.thinned(points, minStep: thresholds.minStepDistance))
        let netDegrees = abs(turning) * 180 / .pi
        return netDegrees >= thresholds.minTurnDegrees
    }

    private static func bounds(of points: [RepairGesturePoint]) -> (width: Double, height: Double) {
        var minX = Double.infinity
        var maxX = -Double.infinity
        var minY = Double.infinity
        var maxY = -Double.infinity
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return (maxX - minX, maxY - minY)
    }

    private static func distance(_ from: RepairGesturePoint, _ to: RepairGesturePoint) -> Double {
        hypot(to.x - from.x, to.y - from.y)
    }

    private static func thinned(_ points: [RepairGesturePoint], minStep: Double) -> [RepairGesturePoint] {
        guard var lastKept = points.first else {
            return []
        }
        var kept = [lastKept]
        for point in points.dropFirst() where distance(lastKept, point) >= minStep {
            kept.append(point)
            lastKept = point
        }
        return kept
    }

    /// Sums the change of heading between consecutive segments, one way minus the other, in
    /// radians.
    private static func netTurning(of points: [RepairGesturePoint]) -> Double {
        guard points.count >= 3 else {
            return 0
        }
        var signed = 0.0
        var previousHeading = heading(points[0], points[1])
        for index in 2..<points.count {
            let currentHeading = heading(points[index - 1], points[index])
            signed += wrapped(currentHeading - previousHeading)
            previousHeading = currentHeading
        }
        return signed
    }

    private static func heading(_ from: RepairGesturePoint, _ to: RepairGesturePoint) -> Double {
        atan2(to.y - from.y, to.x - from.x)
    }

    /// An angle brought into -π...π, so a turn across the ±180° line counts as the small turn it is.
    private static func wrapped(_ angle: Double) -> Double {
        var result = angle
        while result > .pi {
            result -= 2 * .pi
        }
        while result < -.pi {
            result += 2 * .pi
        }
        return result
    }
}
