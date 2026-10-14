import Foundation

struct SidekickBundle: Sendable {
    let html: Data
    let scriptHashes: [String]
    let version: String
}

enum SidekickBundleError: Error, Equatable {
    case notFound
    case signInRequired
    case serverError(statusCode: Int)
}

protocol SidekickBundleLoading: Sendable {
    func loadBundle(sidekickId: String) async throws -> SidekickBundle
}

/// Fetches the current bundle from the platform with the user's session. The backend serves a
/// bundle only to a signed-in user it is assigned to (D5); anything else is a 404 or 401.
struct RemoteSidekickBundleLoader: SidekickBundleLoading {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        let request = Self.bundleRequest(platformOrigin: platformOrigin, sidekickId: sidekickId, token: sessionToken())
        let (responseBody, response) = try await session.data(for: request)
        let bundle = try Self.bundle(from: responseBody, response: response)
        // A repair report says which version and scope (user copy or base) the user was on.
        let httpResponse = response as? HTTPURLResponse
        let scope = httpResponse?.value(forHTTPHeaderField: SidekickBundleVersions.scopeHeader)
        SidekickBundleVersions.shared.record(sidekickId: sidekickId, version: bundle.version, scope: scope)
        return bundle
    }

    static func bundleRequest(platformOrigin: URL, sidekickId: String, token: String?) -> URLRequest {
        let bundleURL = platformOrigin.appending(path: "sidekicks/\(sidekickId)/bundle")
        var request = URLRequest(url: bundleURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func bundle(from responseBody: Data, response: URLResponse) throws -> SidekickBundle {
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        if statusCode == 404 {
            throw SidekickBundleError.notFound
        }
        if statusCode == 401 {
            throw SidekickBundleError.signInRequired
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
