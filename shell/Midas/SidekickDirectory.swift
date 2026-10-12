import Foundation
import Observation
import SwiftUI

// SidekickEntry and SidekickColor live in shell/Shared/SidekickEntry.swift (shared with the widget).

enum SidekickDirectoryError: Error, Equatable {
    case signInRequired
    case badResponse
    case serverError(statusCode: Int)
}

protocol SidekickDirectoryFetching: Sendable {
    func fetchSidekicks() async throws -> [SidekickEntry]
}

/// GET /sidekicks: the signed-in user's assigned Sidekicks with their manifests.
struct RemoteSidekickDirectoryFetcher: SidekickDirectoryFetching {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func fetchSidekicks() async throws -> [SidekickEntry] {
        let request = Self.directoryRequest(platformOrigin: platformOrigin, token: sessionToken())
        let (responseBody, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 {
            throw SidekickDirectoryError.signInRequired
        }
        guard statusCode == 200 else {
            throw SidekickDirectoryError.serverError(statusCode: statusCode)
        }
        return try Self.entries(from: responseBody)
    }

    static func directoryRequest(platformOrigin: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: platformOrigin.appending(path: "sidekicks"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private struct Reply: Decodable {
        struct Listing: Decodable {
            struct Icon: Decodable {
                let symbol: String
                let background: String
            }
            let id: String
            let name: String
            let icon: Icon
            let version: String
        }
        let sidekicks: [Listing]
    }

    static func entries(from responseBody: Data) throws -> [SidekickEntry] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: responseBody) else {
            throw SidekickDirectoryError.badResponse
        }
        var entries: [SidekickEntry] = []
        for listing in reply.sidekicks {
            let entry = SidekickEntry(id: listing.id, name: listing.name, symbolName: listing.icon.symbol, backgroundHex: listing.icon.background, version: listing.version)
            entries.append(entry)
        }
        return entries
    }
}

/// The Sidekicks shown in the folder. Starts from the last list saved on the phone, so the folder
/// shows without a connection, and replaces it whenever the server answers.
@MainActor
@Observable
final class SidekickDirectory {
    private(set) var entries: [SidekickEntry]
    private(set) var hasLoadedFromServer = false

    private let cacheFileURL: URL
    private let fetcher: SidekickDirectoryFetching

    init(cacheFileURL: URL, fetcher: SidekickDirectoryFetching) {
        self.cacheFileURL = cacheFileURL
        self.fetcher = fetcher
        self.entries = Self.loadCachedEntries(from: cacheFileURL)
    }

    /// One file per server, so a staging build never shows live's list or the other way round.
    static func defaultCacheFileURL(platformOrigin: URL) -> URL {
        let host = platformOrigin.host() ?? "unknown"
        let supportDirectory = URL.applicationSupportDirectory
        return supportDirectory.appending(path: "midas-sidekicks-\(host).json")
    }

    /// A failed fetch keeps the list already shown.
    func refresh() async {
        guard let fetchedEntries = try? await fetcher.fetchSidekicks() else {
            return
        }
        entries = fetchedEntries
        hasLoadedFromServer = true
        saveCache()
    }

    func entry(withId sidekickId: String) -> SidekickEntry? {
        for entry in entries where entry.id == sidekickId {
            return entry
        }
        return nil
    }

    private func saveCache() {
        let directory = cacheFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let encodedEntries = try? JSONEncoder().encode(entries) else {
            return
        }
        try? encodedEntries.write(to: cacheFileURL, options: [.atomic])
    }

    private static func loadCachedEntries(from fileURL: URL) -> [SidekickEntry] {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decodedEntries = try? JSONDecoder().decode([SidekickEntry].self, from: fileData)
        return decodedEntries ?? []
    }
}
