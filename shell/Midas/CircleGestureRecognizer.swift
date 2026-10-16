import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The repair circle on a Sidekick's web view (founder, 2026-10-15). Passive: it never cancels or
/// delays the touches it watches, never prevents WebKit's own recognisers and cannot be prevented
/// by them, so taps, scrolls and a Sidekick's own gestures work exactly as before. Fires when the
/// finger lifts, if `CircleDetector` judges the stroke a circle. No script is injected
/// (guideline 4.7.2).
final class CircleGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let thresholds: CircleThresholds
    private var detector: CircleDetector?
    private var touchStartedAt: TimeInterval = 0

    init(thresholds: CircleThresholds = .standard, target: Any?, action: Selector?) {
        self.thresholds = thresholds
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        let allTouches = event.allTouches ?? touches
        guard allTouches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }
        touchStartedAt = touch.timestamp
        detector = CircleDetector(thresholds: thresholds)
        detector?.add(point(for: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let touch = touches.first else {
            return
        }
        if (event.allTouches?.count ?? 1) > 1 {
            state = .failed
            return
        }
        // Coalesced touches keep every sample at 120 Hz; the detector works in points and ms
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            detector?.add(point(for: sample))
        }
        if detector?.hasFailed == true {
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard state == .possible else {
            return
        }
        if let touch = touches.first {
            detector?.add(point(for: touch))
        }
        state = detector?.isCircle == true ? .recognized : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if state == .possible {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        detector = nil
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

    private func point(for touch: UITouch) -> RepairGesturePoint {
        let location = touch.location(in: view)
        let elapsedMs = (touch.timestamp - touchStartedAt) * 1000
        return RepairGesturePoint(x: location.x, y: location.y, ms: elapsedMs)
    }
}
