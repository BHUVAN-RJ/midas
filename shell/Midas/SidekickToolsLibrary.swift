import Foundation

enum SidekickToolsFetchError: Error, Equatable {
    case signInRequired
    case noTools
    /// The server runs a different version now; refresh the directory, then ask again.
    case versionChanged
    case serverError(statusCode: Int)
}

protocol SidekickToolsFetching: Sendable {
    func fetchTools(sidekickId: String, version: String) async throws -> String
}

/// GET /sidekicks/<id>/tools.js?version=<v> (backend/src/sidekicks.ts handleSidekickTools).
struct RemoteSidekickToolsFetcher: SidekickToolsFetching {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func fetchTools(sidekickId: String, version: String) async throws -> String {
        let request = Self.toolsRequest(platformOrigin: platformOrigin, sidekickId: sidekickId, version: version, token: sessionToken())
        let (responseBody, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch statusCode {
        case 200:
            guard let source = String(data: responseBody, encoding: .utf8) else {
                throw SidekickToolsFetchError.serverError(statusCode: statusCode)
            }
            return source
        case 401:
            throw SidekickToolsFetchError.signInRequired
        case 404:
            throw SidekickToolsFetchError.noTools
        case 409:
            throw SidekickToolsFetchError.versionChanged
        default:
            throw SidekickToolsFetchError.serverError(statusCode: statusCode)
        }
    }

    static func toolsRequest(platformOrigin: URL, sidekickId: String, version: String, token: String?) -> URLRequest {
        var components = URLComponents(url: platformOrigin.appending(path: "sidekicks/\(sidekickId)/tools.js"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "version", value: version)]
        var request = URLRequest(url: components?.url ?? platformOrigin)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

/// Each Sidekick's tools.js, kept per version (jess router, founder 2026-10-21). A version's
/// tools never change once deployed, so a file saved on the phone is used as is, offline too; a
/// new version (a repair, a base deploy) is fetched once. Engines are made once per version.
@MainActor
final class SidekickToolsLibrary {
    private let cacheDirectoryURL: URL
    private let fetcher: SidekickToolsFetching
    private var enginesByVersionKey: [String: SidekickToolsEngine] = [:]

    init(cacheDirectoryURL: URL, fetcher: SidekickToolsFetching) {
        self.cacheDirectoryURL = cacheDirectoryURL
        self.fetcher = fetcher
    }

    /// One folder per server, like the directory cache.
    static func defaultCacheDirectoryURL(platformOrigin: URL) -> URL {
        let host = platformOrigin.host() ?? "unknown"
        return URL.applicationSupportDirectory.appending(path: "midas-tools-\(host)")
    }

    /// The engine for this version's tools.js: from memory, else from the phone's copy, else
    /// fetched and saved. Throws `SidekickToolsFetchError` or `SidekickToolsError`.
    func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
        let versionKey = Self.versionKey(sidekickId: sidekickId, version: version)
        if let engine = enginesByVersionKey[versionKey] {
            return engine
        }
        let source = try await source(sidekickId: sidekickId, version: version)
        let engine = try SidekickToolsEngine(source: source)
        enginesByVersionKey[versionKey] = engine
        return engine
    }

    func source(sidekickId: String, version: String) async throws -> String {
        let fileURL = cacheFileURL(sidekickId: sidekickId, version: version)
        if let savedData = try? Data(contentsOf: fileURL), let savedSource = String(data: savedData, encoding: .utf8) {
            return savedSource
        }
        let fetchedSource = try await fetcher.fetchTools(sidekickId: sidekickId, version: version)
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try? Data(fetchedSource.utf8).write(to: fileURL, options: [.atomic])
        return fetchedSource
    }

    func cacheFileURL(sidekickId: String, version: String) -> URL {
        cacheDirectoryURL.appending(path: "\(Self.versionKey(sidekickId: sidekickId, version: version)).js")
    }

    // Sidekick ids are [a-z0-9-] and versions are the deploy's own names; anything else is
    // replaced so the file name stays inside the folder.
    private static func versionKey(sidekickId: String, version: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let joined = "\(sidekickId)--\(version)"
        var safeName = ""
        for scalar in joined.unicodeScalars {
            safeName.unicodeScalars.append(allowed.contains(scalar) ? scalar : "_")
        }
        return safeName
    }
}
