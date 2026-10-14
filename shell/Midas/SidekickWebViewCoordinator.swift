import UIKit
import WebKit

/// The coordinator of one Sidekick's web view: keeps its navigation guard alive and starts a
/// repair when the scribble fires (founder, 2026-10-13). One repair at a time per web view.
@MainActor
final class SidekickWebViewCoordinator: NSObject {
    let sidekickId: String
    let navigationGuard: SidekickNavigationGuard
    weak var webView: WKWebView?
    /// Set by `SidekickScreen`; receives the session to show over the web view.
    var onRepairSession: ((RepairSession) -> Void)?
    private var isStartingRepair = false

    init(sidekickId: String) {
        self.sidekickId = sidekickId
        self.navigationGuard = SidekickNavigationGuard(sidekickId: sidekickId)
    }

    @objc func startRepair(_ recognizer: ScribbleGestureRecognizer) {
        guard recognizer.state == .recognized, !isStartingRepair, let webView else {
            return
        }
        isStartingRepair = true
        Task { @MainActor in
            let session = await RepairSession.begin(sidekickId: sidekickId, webView: webView, transcriber: OnDeviceSpeechTranscriber(), uploader: ShellServices.shared.repairUploader)
            isStartingRepair = false
            if let session {
                onRepairSession?(session)
            }
        }
    }
}
