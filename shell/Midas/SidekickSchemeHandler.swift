import Foundation
import WebKit

/// Serves sidekick://<id>/ from the platform and attaches the CSP. Only the root document is
/// served: a bundle is one HTML file with inline scripts and styles.
@MainActor
final class SidekickSchemeHandler: NSObject, WKURLSchemeHandler {
    private let bundleLoader: SidekickBundleLoading
    private let platformOrigin: URL
    // WebKit crashes if a stopped task is answered, so stopped tasks are remembered here.
    private var stoppedTaskIds: Set<ObjectIdentifier> = []

    init(bundleLoader: SidekickBundleLoading, platformOrigin: URL) {
        self.bundleLoader = bundleLoader
        self.platformOrigin = platformOrigin
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url, let sidekickId = requestURL.host() else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let isRootDocument = requestURL.path() == "/" || requestURL.path() == "" || requestURL.path() == "/index.html"
        guard isRootDocument else {
            respond(to: urlSchemeTask, url: requestURL, statusCode: 404, body: Data(), extraHeaders: [:])
            return
        }

        let taskId = ObjectIdentifier(urlSchemeTask)
        Task { @MainActor in
            await self.serveBundle(sidekickId: sidekickId, url: requestURL, task: urlSchemeTask, taskId: taskId)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        stoppedTaskIds.insert(ObjectIdentifier(urlSchemeTask))
    }

    private func serveBundle(sidekickId: String, url: URL, task: WKURLSchemeTask, taskId: ObjectIdentifier) async {
        do {
            let bundle = try await bundleLoader.loadBundle(sidekickId: sidekickId)
            guard !stoppedTaskIds.contains(taskId) else {
                return
            }
            let policy = SidekickContentSecurityPolicy.policy(scriptHashes: bundle.scriptHashes, platformOrigin: platformOrigin)
            let headers = ["Content-Security-Policy": policy]
            respond(to: task, url: url, statusCode: 200, body: bundle.html, extraHeaders: headers)
        } catch {
            guard !stoppedTaskIds.contains(taskId) else {
                return
            }
            let statusCode = (error as? SidekickBundleError) == .notFound ? 404 : 502
            let message = Data("This Sidekick could not be loaded.".utf8)
            respond(to: task, url: url, statusCode: statusCode, body: message, extraHeaders: [:])
        }
    }

    private func respond(to task: WKURLSchemeTask, url: URL, statusCode: Int, body: Data, extraHeaders: [String: String]) {
        var headers = extraHeaders
        headers["Content-Type"] = statusCode == 200 ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
        headers["Content-Length"] = String(body.count)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
