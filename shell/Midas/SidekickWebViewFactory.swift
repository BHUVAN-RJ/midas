import WebKit

/// Builds the web view a Sidekick runs in. No script message handlers and no injected user
/// scripts: Sidekicks get what Safari gives a web page, nothing native (guideline 4.7.2).
@MainActor
enum SidekickWebViewFactory {
    static func makeWebView(bundleLoader: SidekickBundleLoading, platformOrigin: URL, storeChannel: SidekickStoreChannel? = nil) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let schemeHandler = SidekickSchemeHandler(bundleLoader: bundleLoader, platformOrigin: platformOrigin, storeChannel: storeChannel)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: PlatformConfig.sidekickScheme)
        // Non-persistent: localStorage and IndexedDB do not survive, so all data goes through the SDK.
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    static func sidekickURL(sidekickId: String) -> URL {
        URL(string: "\(PlatformConfig.sidekickScheme)://\(sidekickId)/")!
    }
}

/// Keeps a Sidekick on its own origin: any navigation elsewhere is cancelled.
final class SidekickNavigationGuard: NSObject, WKNavigationDelegate {
    let sidekickId: String

    init(sidekickId: String) {
        self.sidekickId = sidekickId
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let targetURL = navigationAction.request.url
        let staysOnSidekick = targetURL?.scheme == PlatformConfig.sidekickScheme && targetURL?.host() == sidekickId
        return staysOnSidekick ? .allow : .cancel
    }
}
