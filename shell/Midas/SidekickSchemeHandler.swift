import Foundation
import WebKit

/// Serves sidekick://<id>/ from the platform and attaches the CSP. Only the root document is
/// served: a bundle is one HTML file with inline scripts and styles. POSTs to
/// sidekick://<id>/_midas/store go to the local store channel, so a Sidekick can read and write
/// its records on the phone without a connection.
@MainActor
final class SidekickSchemeHandler: NSObject, WKURLSchemeHandler {
    private let bundleLoader: SidekickBundleLoading
    private let platformOrigin: URL
    private let storeChannel: SidekickStoreChannel?
    // WebKit crashes if a stopped task is answered, so stopped tasks are remembered here.
    private var stoppedTaskIds: Set<ObjectIdentifier> = []

    init(bundleLoader: SidekickBundleLoading, platformOrigin: URL, storeChannel: SidekickStoreChannel? = nil) {
        self.bundleLoader = bundleLoader
        self.platformOrigin = platformOrigin
        self.storeChannel = storeChannel
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url, let sidekickId = requestURL.host() else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let isStoreRequest = requestURL.path() == SidekickStoreChannel.path
        if isStoreRequest {
            answerStoreRequest(sidekickId: sidekickId, url: requestURL, task: urlSchemeTask)
            return
        }
        let requestPath = requestURL.path()
        if requestPath == SidekickStoreChannel.filesPath {
            answerFilePut(sidekickId: sidekickId, url: requestURL, task: urlSchemeTask)
            return
        }
        if requestPath.hasPrefix(SidekickStoreChannel.filesPath + "/") {
            let fileId = String(requestPath.dropFirst(SidekickStoreChannel.filesPath.count + 1))
            let taskId = ObjectIdentifier(urlSchemeTask)
            Task { @MainActor in
                await self.serveFile(fileId: fileId, url: requestURL, task: urlSchemeTask, taskId: taskId)
            }
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

    // The Sidekick id comes from the request's origin, never from the body, so a Sidekick can
    // only reach its own records. CSP stops it from calling another Sidekick's origin.
    private func answerStoreRequest(sidekickId: String, url: URL, task: WKURLSchemeTask) {
        let jsonHeaders = ["Content-Type": "application/json"]
        guard let storeChannel, task.request.httpMethod == "POST" else {
            respond(to: task, url: url, statusCode: 404, body: Data(), extraHeaders: [:])
            return
        }
        let requestBody = Self.readBody(of: task.request)
        let reply = storeChannel.handle(sidekickId: sidekickId, requestBody: requestBody)
        let replyBody = (try? JSONEncoder().encode(reply.body)) ?? Data()
        respond(to: task, url: url, statusCode: reply.statusCode, body: replyBody, extraHeaders: jsonHeaders)
    }

    // A file from the page (store.putFile): the body is the bytes, Content-Type their type.
    private func answerFilePut(sidekickId: String, url: URL, task: WKURLSchemeTask) {
        let jsonHeaders = ["Content-Type": "application/json"]
        guard let storeChannel, task.request.httpMethod == "POST" else {
            respond(to: task, url: url, statusCode: 404, body: Data(), extraHeaders: [:])
            return
        }
        let body = Self.readBody(of: task.request)
        let contentType = task.request.value(forHTTPHeaderField: "Content-Type")
        let reply = storeChannel.handleFilePut(sidekickId: sidekickId, body: body, contentType: contentType)
        let replyBody = (try? JSONEncoder().encode(reply.body)) ?? Data()
        respond(to: task, url: url, statusCode: reply.statusCode, body: replyBody, extraHeaders: jsonHeaders)
    }

    // A file for the page (store.fileUrl): the bytes with their type, 404 when there is none.
    private func serveFile(fileId: String, url: URL, task: WKURLSchemeTask, taskId: ObjectIdentifier) async {
        guard let storeChannel, task.request.httpMethod == "GET" else {
            respond(to: task, url: url, statusCode: 404, body: Data(), extraHeaders: [:])
            return
        }
        let file = await storeChannel.fileData(fileId: fileId)
        guard !stoppedTaskIds.contains(taskId) else {
            return
        }
        guard let file else {
            respond(to: task, url: url, statusCode: 404, body: Data(), extraHeaders: [:])
            return
        }
        respond(to: task, url: url, statusCode: 200, body: file.data, extraHeaders: ["Content-Type": file.contentType, "Cache-Control": "no-store"])
    }

    // WebKit hands the body over either as data or as a stream, depending on its size.
    private static func readBody(of request: URLRequest) -> Data {
        if let bodyData = request.httpBody {
            return bodyData
        }
        guard let bodyStream = request.httpBodyStream else {
            return Data()
        }
        var collectedBody = Data()
        let chunkSize = 16_384
        var chunkBuffer = [UInt8](repeating: 0, count: chunkSize)
        bodyStream.open()
        defer { bodyStream.close() }
        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(&chunkBuffer, maxLength: chunkSize)
            guard bytesRead > 0 else {
                break
            }
            collectedBody.append(chunkBuffer, count: bytesRead)
        }
        return collectedBody
    }

    private func serveBundle(sidekickId: String, url: URL, task: WKURLSchemeTask, taskId: ObjectIdentifier) async {
        do {
            let bundle = try await bundleLoader.loadBundle(sidekickId: sidekickId)
            guard !stoppedTaskIds.contains(taskId) else {
                return
            }
            let sidekickOrigin = "\(PlatformConfig.sidekickScheme)://\(sidekickId)"
            let policy = SidekickContentSecurityPolicy.policy(scriptHashes: bundle.scriptHashes, platformOrigin: platformOrigin, sidekickOrigin: sidekickOrigin)
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
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = statusCode == 200 ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
        }
        headers["Content-Length"] = String(body.count)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
