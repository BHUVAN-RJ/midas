import Foundation
import Observation
import SwiftUI

// SidekickEntry and SidekickColor live in shell/Shared/SidekickEntry.swift (shared with the widget).

enum SidekickDirectoryError: Error, Equatable {
    case signInRequired
    case badResponse
    case serverError(statusCode: Int)
}

/// One Sidekick as GET /sidekicks lists it: the entry for the grid plus the record types its
/// manifest declares (`types`, unified data 2026-10-15), which the write gate checks against.
struct SidekickListing: Equatable, Sendable {
    let entry: SidekickEntry
    let types: JSONValue?
}

protocol SidekickDirectoryFetching: Sendable {
    func fetchSidekicks() async throws -> [SidekickEntry]
    func fetchListings() async throws -> [SidekickListing]
}

extension SidekickDirectoryFetching {
    /// A fetcher that knows only entries lists them with no types.
    func fetchListings() async throws -> [SidekickListing] {
        let entries = try await fetchSidekicks()
        var listings: [SidekickListing] = []
        for entry in entries {
            listings.append(SidekickListing(entry: entry, types: nil))
        }
        return listings
    }
}

/// GET /sidekicks: the signed-in user's assigned Sidekicks with their manifests.
struct RemoteSidekickDirectoryFetcher: SidekickDirectoryFetching {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func fetchSidekicks() async throws -> [SidekickEntry] {
        let listings = try await fetchListings()
        var entries: [SidekickEntry] = []
        for listing in listings {
            entries.append(listing.entry)
        }
        return entries
    }

    func fetchListings() async throws -> [SidekickListing] {
        let request = Self.directoryRequest(platformOrigin: platformOrigin, token: sessionToken())
        let (responseBody, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 {
            throw SidekickDirectoryError.signInRequired
        }
        guard statusCode == 200 else {
            throw SidekickDirectoryError.serverError(statusCode: statusCode)
        }
        return try Self.listings(from: responseBody)
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
            /// The manifest's record types; absent on a version deployed before schemas.
            let types: JSONValue?
        }
        let sidekicks: [Listing]
    }

    static func entries(from responseBody: Data) throws -> [SidekickEntry] {
        let listings = try listings(from: responseBody)
        var entries: [SidekickEntry] = []
        for listing in listings {
            entries.append(listing.entry)
        }
        return entries
    }

    static func listings(from responseBody: Data) throws -> [SidekickListing] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: responseBody) else {
            throw SidekickDirectoryError.badResponse
        }
        var listings: [SidekickListing] = []
        for listing in reply.sidekicks {
            let entry = SidekickEntry(id: listing.id, name: listing.name, symbolName: listing.icon.symbol, backgroundHex: listing.icon.background, version: listing.version)
            // A manifest without types decodes as nil or JSON null; both mean "no schemas".
            let types = listing.types == .null ? nil : listing.types
            listings.append(SidekickListing(entry: entry, types: types))
        }
        return listings
    }
}

/// The Sidekicks shown in the folder. Starts from the last list saved on the phone, so the folder
/// shows without a connection, and replaces it whenever the server answers.
@MainActor
@Observable
final class SidekickDirectory {
    private(set) var entries: [SidekickEntry]
    private(set) var hasLoadedFromServer = false
    /// Each Sidekick's record types from its manifest, kept next to the entries so writes are
    /// checked offline too.
    private(set) var typesBySidekickId: [String: JSONValue]

    private let cacheFileURL: URL
    private let typesCacheFileURL: URL
    private let fetcher: SidekickDirectoryFetching
    private let sharedListWriter: SharedSidekickListWriter

    /// `sharedListWriter` hands every list to the widget; the cached list goes out at once, so a
    /// widget shows Sidekicks before the first server answer.
    init(cacheFileURL: URL, fetcher: SidekickDirectoryFetching, sharedListWriter: SharedSidekickListWriter = .live()) {
        self.cacheFileURL = cacheFileURL
        self.typesCacheFileURL = Self.typesCacheFileURL(besides: cacheFileURL)
        self.fetcher = fetcher
        self.sharedListWriter = sharedListWriter
        self.entries = Self.loadCachedEntries(from: cacheFileURL)
        self.typesBySidekickId = Self.loadCachedTypes(from: typesCacheFileURL)
        sharedListWriter.write(entries: entries)
    }

    /// One file per server, so a staging build never shows live's list or the other way round.
    static func defaultCacheFileURL(platformOrigin: URL) -> URL {
        let host = platformOrigin.host() ?? "unknown"
        let supportDirectory = URL.applicationSupportDirectory
        return supportDirectory.appending(path: "midas-sidekicks-\(host).json")
    }

    /// The types live in a second file next to the entries file ("...-types.json"), so the
    /// entries file keeps the shape the widget and older installs know.
    static func typesCacheFileURL(besides cacheFileURL: URL) -> URL {
        let baseName = cacheFileURL.deletingPathExtension().lastPathComponent
        return cacheFileURL.deletingLastPathComponent().appending(path: "\(baseName)-types.json")
    }

    /// A failed fetch keeps the list already shown.
    func refresh() async {
        guard let fetchedListings = try? await fetcher.fetchListings() else {
            return
        }
        var fetchedEntries: [SidekickEntry] = []
        var fetchedTypes: [String: JSONValue] = [:]
        for listing in fetchedListings {
            fetchedEntries.append(listing.entry)
            if let types = listing.types {
                fetchedTypes[listing.entry.id] = types
            }
        }
        entries = fetchedEntries
        typesBySidekickId = fetchedTypes
        hasLoadedFromServer = true
        saveCache()
        sharedListWriter.write(entries: entries)
    }

    func entry(withId sidekickId: String) -> SidekickEntry? {
        for entry in entries where entry.id == sidekickId {
            return entry
        }
        return nil
    }

    /// The record types of this Sidekick's current version, or nil when it declares none.
    func types(forSidekickId sidekickId: String) -> JSONValue? {
        typesBySidekickId[sidekickId]
    }

    /// The bundle version the user runs for this Sidekick, or nil when it is not listed.
    func version(forSidekickId sidekickId: String) -> String? {
        entry(withId: sidekickId)?.version
    }

    private func saveCache() {
        let directory = cacheFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let encodedEntries = try? JSONEncoder().encode(entries) {
            try? encodedEntries.write(to: cacheFileURL, options: [.atomic])
        }
        if let encodedTypes = try? JSONEncoder().encode(typesBySidekickId) {
            try? encodedTypes.write(to: typesCacheFileURL, options: [.atomic])
        }
    }

    private static func loadCachedEntries(from fileURL: URL) -> [SidekickEntry] {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decodedEntries = try? JSONDecoder().decode([SidekickEntry].self, from: fileData)
        return decodedEntries ?? []
    }

    private static func loadCachedTypes(from fileURL: URL) -> [String: JSONValue] {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        let decodedTypes = try? JSONDecoder().decode([String: JSONValue].self, from: fileData)
        return decodedTypes ?? [:]
    }
}
