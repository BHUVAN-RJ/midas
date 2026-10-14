import Foundation

/// One sampled touch point of the repair gesture: screen points and milliseconds since the touch
/// began. Same shape as the founder's capture page (`[x, y, ms]`).
struct ScribblePoint: Equatable, Sendable {
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

/// Numbers the recogniser is tuned with. One place to change when phone captures arrive
/// (founder, 2026-10-13: mouse sample is the general shape; tuned on the phone later).
struct ScribbleThresholds: Equatable, Sendable {
    /// Direction changes on the x axis before the gesture fires (3 = two full zigzags).
    var minReversals = 3
    /// Movement against the current direction that counts as a turn, not jitter.
    var hysteresis: Double = 15
    /// A leg shorter than this breaks the chain: a wobble, not a scribble.
    var minLegLength: Double = 60
    /// Total horizontal extent at the moment of firing.
    var minSpan: Double = 100
    /// Fires no earlier than this many ms after the touch began.
    var minDurationMs: Double = 150
    /// A stroke still unrecognised after this is a drag, never a scribble.
    var maxDurationMs: Double = 2000

    static let standard = ScribbleThresholds()
}

/// Recognises the repair scribble (founder, 2026-10-13): one finger, two or three zigzags,
/// anywhere on the screen. Counts direction reversals along x with hysteresis, so a vertical
/// scroll (which may reverse on y but not on x), an edge swipe and a tap never match. Fed one
/// point at a time; `add` returns true the moment the gesture is recognised, while the finger
/// is still down. Thresholds are in points and milliseconds, never in point counts, so the
/// sample rate (mouse ~30 Hz, phone 60–120 Hz) does not matter.
struct ScribbleDetector: Sendable {
    let thresholds: ScribbleThresholds

    private var direction = 0
    private var legStartX: Double?
    private var extremeX: Double?
    private var minX: Double?
    private var maxX: Double?
    private var reversals = 0
    private var hasFired = false
    private var isDead = false

    init(thresholds: ScribbleThresholds = .standard) {
        self.thresholds = thresholds
    }

    var isRecognised: Bool {
        hasFired
    }

    /// True once this stroke can no longer become a scribble (too slow).
    var hasFailed: Bool {
        isDead
    }

    /// Feeds the next point. Returns true exactly once, on the point that completes the gesture.
    mutating func add(_ point: ScribblePoint) -> Bool {
        if hasFired || isDead {
            return false
        }
        if point.ms > thresholds.maxDurationMs {
            isDead = true
            return false
        }
        trackSpan(point.x)
        guard let currentExtreme = extremeX, let currentLegStart = legStartX else {
            legStartX = point.x
            extremeX = point.x
            return false
        }
        if direction == 0 {
            startFirstLeg(at: point.x, from: currentLegStart)
            return false
        }
        let movedWithDirection = direction > 0 ? point.x > currentExtreme : point.x < currentExtreme
        if movedWithDirection {
            extremeX = point.x
            return false
        }
        let movedBack = direction > 0 ? currentExtreme - point.x : point.x - currentExtreme
        guard movedBack >= thresholds.hysteresis else {
            return false
        }
        completeLeg(endingAt: currentExtreme, from: currentLegStart, turningTo: point.x)
        return checkFired(at: point.ms)
    }

    /// Whole-stroke check, for tests and tuning: does this point list contain the scribble?
    static func recognises(points: [ScribblePoint], thresholds: ScribbleThresholds = .standard) -> Bool {
        var detector = ScribbleDetector(thresholds: thresholds)
        for point in points {
            if detector.add(point) {
                return true
            }
        }
        return false
    }

    /// Milliseconds into the stroke at which the gesture fires, or nil if it never does.
    static func firingTime(points: [ScribblePoint], thresholds: ScribbleThresholds = .standard) -> Double? {
        var detector = ScribbleDetector(thresholds: thresholds)
        for point in points {
            if detector.add(point) {
                return point.ms
            }
        }
        return nil
    }

    private mutating func trackSpan(_ x: Double) {
        minX = min(minX ?? x, x)
        maxX = max(maxX ?? x, x)
    }

    // The first leg has no direction until the finger has moved past the hysteresis.
    private mutating func startFirstLeg(at x: Double, from legStart: Double) {
        let displacement = x - legStart
        if abs(displacement) >= thresholds.hysteresis {
            direction = displacement > 0 ? 1 : -1
            extremeX = x
        }
    }

    // A leg that was long enough counts as one reversal; a short wobble resets the chain, so a
    // jittery scroll never accumulates reversals.
    private mutating func completeLeg(endingAt legEnd: Double, from legStart: Double, turningTo x: Double) {
        let legLength = abs(legEnd - legStart)
        if legLength >= thresholds.minLegLength {
            reversals += 1
        } else {
            reversals = 0
        }
        direction = -direction
        legStartX = legEnd
        extremeX = x
    }

    private mutating func checkFired(at ms: Double) -> Bool {
        guard reversals >= thresholds.minReversals, ms >= thresholds.minDurationMs else {
            return false
        }
        let span = (maxX ?? 0) - (minX ?? 0)
        guard span >= thresholds.minSpan else {
            return false
        }
        hasFired = true
        return true
    }
}
