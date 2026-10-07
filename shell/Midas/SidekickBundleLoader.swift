import Foundation

struct SidekickBundle: Sendable {
    let html: Data
    let scriptHashes: [String]
    let version: String
}

enum SidekickBundleError: Error, Equatable {
    case notFound
    case serverError(statusCode: Int)
}

protocol SidekickBundleLoading: Sendable {
    func loadBundle(sidekickId: String) async throws -> SidekickBundle
}

/// Fetches the current bundle from the platform.
/// TODO(D3/D5): send the shell's token once the route requires one.
struct RemoteSidekickBundleLoader: SidekickBundleLoading {
    let platformOrigin: URL
    let session: URLSession

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        let bundleURL = platformOrigin.appending(path: "sidekicks/\(sidekickId)/bundle")
        var request = URLRequest(url: bundleURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (responseBody, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        if statusCode == 404 {
            throw SidekickBundleError.notFound
        }
        guard statusCode == 200, let httpResponse else {
            throw SidekickBundleError.serverError(statusCode: statusCode)
        }

        let hashHeader = httpResponse.value(forHTTPHeaderField: "X-Midas-Script-Hashes")
        let scriptHashes = SidekickContentSecurityPolicy.validScriptHashes(fromHeader: hashHeader)
        let version = httpResponse.value(forHTTPHeaderField: "X-Midas-Bundle-Version") ?? "unknown"
        return SidekickBundle(html: responseBody, scriptHashes: scriptHashes, version: version)
    }
}
