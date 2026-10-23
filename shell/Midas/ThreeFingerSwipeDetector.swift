import Foundation

/// One sampled touch point of the repair gesture: screen points and milliseconds since the first
/// finger landed. Same shape as the founder's capture page (`[x, y, ms]`).
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

/// Numbers the three-finger swipe is tuned with, all in one place for the phone captures
/// (defaults proposed 2026-10-15, to tune on the phone).
struct SwipeDownThresholds: Equatable, Sendable {
    /// Exactly this many fingers: fewer never fires, one more fails it.
    var touchCount: Int = 3
    /// Every finger must land within this long of the first.
    var maxLandingGapMs: Double = 250
    /// Every finger must move at least this far down, in points.
    var minDownDistance: Double = 80
    /// Each finger's sideways movement may be at most this share of its downward movement
    /// (0.5 is about 27° off straight down), so undo and redo swipes (left, right) never fire it.
    var maxSidewaysShare: Double = 0.5
    /// A finger moving up more than this, in points, fails it: a pinch or a swipe up.
    var maxUpwardDistance: Double = 20
    /// From the first finger landing to the swipe being complete.
    var maxDurationMs: Double = 1000

    static let standard = SwipeDownThresholds()
}

/// Recognises the repair gesture (founder, 2026-10-15): three fingers swipe down anywhere on the
/// Sidekick, a gesture nobody makes by accident. Judged from every finger's track, and complete
/// as soon as all three have gone far enough down, without waiting for the lift, so the page has
/// as little time to scroll under it as possible (docs/CONCERNS.md item 11).
///
/// Known clashes, not solved here: with VoiceOver on, three-finger swipes up and down scroll and
/// iOS takes the touches, so the swipe never reaches Midas; Zoom uses a three-finger drag and
/// double tap. The iOS edit gestures are three-finger swipe left and right (undo, redo), a
/// three-finger tap and pinches, none of them a swipe down.
enum ThreeFingerSwipeDetector {
    enum Verdict: Equatable, Sendable {
        case possible
        case recognized
        case failed
    }

    /// `tracks` holds one point list per finger that has landed, in landing order, every time
    /// counted from the first finger's landing. `nowMs` is the time of the latest touch event.
    static func verdict(tracks: [[RepairGesturePoint]], nowMs: Double, thresholds: SwipeDownThresholds = .standard) -> Verdict {
        if tracks.count > thresholds.touchCount {
            return .failed
        }
        if nowMs > thresholds.maxDurationMs {
            return .failed
        }
        if tracks.count < thresholds.touchCount {
            // Still waiting for the rest of the fingers, but only briefly
            return nowMs > thresholds.maxLandingGapMs ? .failed : .possible
        }
        var allFarEnough = true
        for track in tracks {
            guard let first = track.first, let last = track.last else {
                return .failed
            }
            if first.ms > thresholds.maxLandingGapMs {
                return .failed
            }
            let down = last.y - first.y
            let sideways = abs(last.x - first.x)
            if -down > thresholds.maxUpwardDistance {
                return .failed
            }
            // Early in the swipe the downward movement is small, so allow sideways drift against
            // the full distance until the finger has gone that far
            let sidewaysAllowance = max(down, thresholds.minDownDistance) * thresholds.maxSidewaysShare
            if sideways > sidewaysAllowance {
                return .failed
            }
            if down < thresholds.minDownDistance {
                allFarEnough = false
            }
        }
        return allFarEnough ? .recognized : .possible
    }

    /// How far the swipe has come, 0...1: the slowest of three fingers' way down, as a share of
    /// `minDownDistance`. 0 until all three fingers are down. The rim traces with it (V1).
    static func progress(tracks: [[RepairGesturePoint]], thresholds: SwipeDownThresholds = .standard) -> Double {
        guard tracks.count == thresholds.touchCount, thresholds.minDownDistance > 0 else {
            return 0
        }
        var slowest = Double.infinity
        for track in tracks {
            guard let first = track.first, let last = track.last else {
                return 0
            }
            slowest = min(slowest, last.y - first.y)
        }
        return min(1, max(0, slowest / thresholds.minDownDistance))
    }
}
