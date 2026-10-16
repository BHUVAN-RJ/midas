import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The repair gesture on a Sidekick's web view: three fingers swipe down (founder, 2026-10-15).
/// Passive: it never cancels or delays the touches it watches, never prevents WebKit's own
/// recognisers and cannot be prevented by them, so taps, scrolls and a Sidekick's own gestures
/// work exactly as before. Fires as soon as `ThreeFingerSwipeDetector` says all three fingers
/// have gone far enough down, without waiting for the lift. No script is injected
/// (guideline 4.7.2). Clashes with VoiceOver and Zoom: see `ThreeFingerSwipeDetector`.
final class ThreeFingerSwipeRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let thresholds: SwipeDownThresholds
    /// One track per finger, in landing order.
    private var tracks: [[RepairGesturePoint]] = []
    private var trackIndexByTouch: [ObjectIdentifier: Int] = [:]
    private var firstLandingAt: TimeInterval?

    init(thresholds: SwipeDownThresholds = .standard, target: Any?, action: Selector?) {
        self.thresholds = thresholds
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard state == .possible else {
            return
        }
        for touch in touches {
            if firstLandingAt == nil {
                firstLandingAt = touch.timestamp
            }
            trackIndexByTouch[ObjectIdentifier(touch)] = tracks.count
            tracks.append([point(for: touch)])
        }
        judge(at: event.timestamp)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible else {
            return
        }
        for touch in touches {
            guard let index = trackIndexByTouch[ObjectIdentifier(touch)] else {
                continue
            }
            // Coalesced touches keep every sample at 120 Hz
            let samples = event.coalescedTouches(for: touch) ?? [touch]
            for sample in samples {
                tracks[index].append(point(for: sample))
            }
        }
        judge(at: event.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        // A finger lifting before the swipe is complete ends it: a tap, a short swipe
        if state == .possible {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if state == .possible {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        tracks = []
        trackIndexByTouch = [:]
        firstLandingAt = nil
    }

    // Never blocks the web view's recognisers, and they never block this one.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private func judge(at timestamp: TimeInterval) {
        let nowMs = (timestamp - (firstLandingAt ?? timestamp)) * 1000
        switch ThreeFingerSwipeDetector.verdict(tracks: tracks, nowMs: nowMs, thresholds: thresholds) {
        case .possible:
            break
        case .recognized:
            state = .recognized
        case .failed:
            state = .failed
        }
    }

    private func point(for touch: UITouch) -> RepairGesturePoint {
        let location = touch.location(in: view)
        let elapsedMs = (touch.timestamp - (firstLandingAt ?? touch.timestamp)) * 1000
        return RepairGesturePoint(x: location.x, y: location.y, ms: elapsedMs)
    }
}
