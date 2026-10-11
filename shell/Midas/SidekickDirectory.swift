import Foundation
import Observation
import SwiftUI

/// One Sidekick in the folder, from its manifest (id, name, SF Symbol, background color).
struct SidekickEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let symbolName: String
    let backgroundHex: String
    let version: String

    var backgroundColor: Color {
        SidekickColor.color(fromHex: backgroundHex)
    }
}

enum SidekickColor {
    /// "#FF9500" to a Color; anything else is gray rather than a crash.
    static func color(fromHex hex: String) -> Color {
        guard let components = rgbComponents(fromHex: hex) else {
            return .gray
        }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func rgbComponents(fromHex hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.count == 7, hex.hasPrefix("#") else {
            return nil
        }
        let digits = hex.dropFirst()
        guard let packed = UInt32(digits, radix: 16) else {
            return nil
        }
        let red = Double((packed >> 16) & 0xFF) / 255
        let green = Double((packed >> 8) & 0xFF) / 255
        let blue = Double(packed & 0xFF) / 255
        return (red, green, blue)
    }
}

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
