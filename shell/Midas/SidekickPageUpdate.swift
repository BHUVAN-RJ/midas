import UIKit
import WebKit

// "Repair done. Tap to update" → the page updates (founder, 2026-10-23, U4 "Tag grows into the
// page"): the tag presses to 94% for 120 ms (the tag's own view), then the new page scales from 7%
// to 100% out of the tag's position over 600 ms with a strong ease-out and fades in over the first
// 30% of that; the old page shrinks to 97% and fades to 50% under it. Reduce Motion: a 200 ms
// cross-fade. Every update after a repair goes through `SidekickPageUpdate.play`.

/// The numbers of U4.
enum SidekickPageUpdateSpec {
    static let tagPressScale: CGFloat = 0.94
    static let tagPress = 0.12
    static let newPageStartScale: CGFloat = 0.07
    static let grow = 0.60
    /// The new page is fully shown after this share of the grow.
    static let fadeInShare = 0.30
    static let oldPageScale: CGFloat = 0.97
    static let oldPageAlpha: CGFloat = 0.5
    static let reduceMotionFade = 0.20
    /// Strong ease-out.
    static let growControlPoint1 = CGPoint(x: 0.16, y: 1)
    static let growControlPoint2 = CGPoint(x: 0.3, y: 1)

    /// A transform that scales a view by `scale` about `point` (in the view's own bounds), so the
    /// new page grows out of the tag instead of out of the screen's centre.
    static func scaling(_ scale: CGFloat, about point: CGPoint, in bounds: CGRect) -> CGAffineTransform {
        let offsetX = point.x - bounds.midX
        let offsetY = point.y - bounds.midY
        let toPoint = CGAffineTransform(translationX: offsetX, y: offsetY)
        let scaled = toPoint.scaledBy(x: scale, y: scale)
        return scaled.translatedBy(x: -offsetX, y: -offsetY)
    }
}

@MainActor
enum SidekickPageUpdate {
    /// Loads the new version into `webView` and shows it growing out of `tagCenterInWindow`.
    /// `reload` loads the page and calls back once it is in; the old page stays on screen until then.
    static func play(webView: WKWebView, tagCenterInWindow: CGPoint, reduceMotion: Bool, reload: (@escaping @MainActor () -> Void) -> Void) {
        let oldPage = webView.snapshotView(afterScreenUpdates: false) ?? UIView()
        oldPage.frame = webView.frame
        oldPage.isUserInteractionEnabled = false
        webView.superview?.insertSubview(oldPage, belowSubview: webView)
        webView.alpha = 0
        func showNewPage() {
            if reduceMotion {
                crossFade(webView: webView, oldPage: oldPage)
            } else {
                grow(webView: webView, oldPage: oldPage, from: webView.convert(tagCenterInWindow, from: nil))
            }
        }
        reload(showNewPage)
    }

    private static func grow(webView: WKWebView, oldPage: UIView, from origin: CGPoint) {
        webView.transform = SidekickPageUpdateSpec.scaling(SidekickPageUpdateSpec.newPageStartScale, about: origin, in: webView.bounds)
        let growAnimator = UIViewPropertyAnimator(duration: SidekickPageUpdateSpec.grow, controlPoint1: SidekickPageUpdateSpec.growControlPoint1, controlPoint2: SidekickPageUpdateSpec.growControlPoint2)
        func settle() {
            webView.transform = .identity
            oldPage.transform = CGAffineTransform(scaleX: SidekickPageUpdateSpec.oldPageScale, y: SidekickPageUpdateSpec.oldPageScale)
            oldPage.alpha = SidekickPageUpdateSpec.oldPageAlpha
        }
        func finish(_ position: UIViewAnimatingPosition) {
            oldPage.removeFromSuperview()
            webView.transform = .identity
            webView.alpha = 1
        }
        growAnimator.addAnimations(settle)
        growAnimator.addCompletion(finish)
        func fadeIn() {
            webView.alpha = 1
        }
        UIView.animate(withDuration: SidekickPageUpdateSpec.grow * SidekickPageUpdateSpec.fadeInShare, delay: 0, options: [.curveLinear], animations: fadeIn)
        growAnimator.startAnimation()
    }

    private static func crossFade(webView: WKWebView, oldPage: UIView) {
        func swap() {
            webView.alpha = 1
            oldPage.alpha = 0
        }
        func finish(_ finished: Bool) {
            oldPage.removeFromSuperview()
        }
        UIView.animate(withDuration: SidekickPageUpdateSpec.reduceMotionFade, delay: 0, options: [.curveEaseInOut], animations: swap, completion: finish)
    }
}
