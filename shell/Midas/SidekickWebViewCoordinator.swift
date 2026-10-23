import UIKit
import WebKit

/// The coordinator of one Sidekick's web view: keeps its navigation guard alive, starts a repair
/// when three fingers swipe down (founder, 2026-10-15) and reloads the page when a repair landed.
/// One repair at a time per web view.
@MainActor
final class SidekickWebViewCoordinator: NSObject {
    let sidekickId: String
    let navigationGuard: SidekickNavigationGuard
    weak var webView: WKWebView?
    /// Set by `SidekickScreen`; receives the session to show over the web view.
    var onRepairSession: ((RepairSession) -> Void)?
    /// How far the three-finger swipe has come (0...1): the rim traces with it.
    var onSwipeProgress: ((Double) -> Void)?
    /// The swipe fired but the page could not be frozen: the rim goes away.
    var onRepairUnavailable: (() -> Void)?
    private var isStartingRepair = false

    init(sidekickId: String) {
        self.sidekickId = sidekickId
        self.navigationGuard = SidekickNavigationGuard(sidekickId: sidekickId)
    }

    func swipeProgressed(_ progress: Double) {
        onSwipeProgress?(progress)
    }

    @objc func startRepair(_ recognizer: ThreeFingerSwipeRecognizer) {
        guard recognizer.state == .recognized, !isStartingRepair, let webView else {
            return
        }
        isStartingRepair = true
        // jess's orb pops where the fingers lifted (O4), in window points
        let liftPoint = recognizer.location(in: nil)
        Task { @MainActor in
            let session = await RepairSession.begin(sidekickId: sidekickId, webView: webView, transcriber: OnDeviceSpeechTranscriber(options: .repair), uploader: ShellServices.shared.repairUploader)
            isStartingRepair = false
            guard let session else {
                onRepairUnavailable?()
                return
            }
            session.liftPoint = liftPoint
            onRepairSession?(session)
        }
    }

    /// Loads the Sidekick's current version again and calls back once it has loaded (or failed),
    /// or after `timeout` at the latest, so an update never hangs on a slow network.
    func reloadPage(timeout: Duration = .seconds(3), finished: @escaping @MainActor () -> Void) {
        guard let webView else {
            finished()
            return
        }
        let once = PageLoadOnce(finished: finished)
        let finishOnce = once.finish
        navigationGuard.onNextLoadFinished = finishOnce
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        Task { @MainActor in
            try? await Task.sleep(for: timeout)
            finishOnce()
        }
    }
}

/// Calls back once: the page loaded, failed, or the wait ran out, whichever comes first.
@MainActor
private final class PageLoadOnce {
    private var finished: (@MainActor () -> Void)?

    init(finished: @escaping @MainActor () -> Void) {
        self.finished = finished
    }

    func finish() {
        let callback = finished
        finished = nil
        callback?()
    }
}
