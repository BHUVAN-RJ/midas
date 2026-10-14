import Foundation

// The contract between the Midas app and its widget extension (founder plan, 2026-10-11).
// The app writes the Sidekick list into the App Group container; the widget only reads it.
// A widget tile opens a Sidekick through a midas:// link the app handles.

enum WidgetShared {
    /// The App Group both targets carry in their entitlements. Read from Info.plist
    /// (`MidasAppGroup`), so the "Midas Test" app (2026-10-14) uses its own group and never shares
    /// widget files with the everyday Midas on the same phone.
    static let appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: "MidasAppGroup") as? String ?? "group.com.bhuvanrj.midas"

    /// WidgetKit `kind` of the folder widget.
    static let folderWidgetKind = "com.bhuvanrj.midas.folder"

    /// Where the shared Sidekick list lives; nil when the App Group is not available
    /// (an unsigned build, or the entitlement missing).
    static func sidekickListFileURL(fileManager: FileManager = .default) -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        return container.appending(path: "widget-sidekicks.json")
    }
}

/// The Sidekick list as the widget sees it: the home grid's entries, in home grid order.
struct SharedSidekickList: Codable, Equatable, Sendable {
    /// Bumped when the file's shape changes; a reader ignores a version it does not know.
    static let currentFormatVersion = 1

    let formatVersion: Int
    let savedAt: Date
    let sidekicks: [SidekickEntry]

    init(sidekicks: [SidekickEntry], savedAt: Date) {
        self.formatVersion = Self.currentFormatVersion
        self.savedAt = savedAt
        self.sidekicks = sidekicks
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Nil for unreadable data or an unknown format version.
    static func decoded(from data: Data) -> SharedSidekickList? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode(SharedSidekickList.self, from: data) else {
            return nil
        }
        guard list.formatVersion == currentFormatVersion else {
            return nil
        }
        return list
    }
}

/// midas://open/<sidekickId> opens a Sidekick; midas://home opens the Midas home.
enum MidasLink: Equatable {
    case home
    case openSidekick(id: String)

    static let scheme = "midas"

    var url: URL {
        switch self {
        case .home:
            return URL(string: "\(Self.scheme)://home")!
        case .openSidekick(let sidekickId):
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let escapedId = sidekickId.addingPercentEncoding(withAllowedCharacters: allowed) ?? sidekickId
            return URL(string: "\(Self.scheme)://open/\(escapedId)")!
        }
    }

    /// Nil for any URL that is not one of the two shapes above.
    init?(url: URL) {
        guard url.scheme == Self.scheme else {
            return nil
        }
        let pathParts = url.pathComponents.filter { $0 != "/" }
        switch url.host() {
        case "home" where pathParts.isEmpty:
            self = .home
        case "open" where pathParts.count == 1 && !pathParts[0].isEmpty:
            self = .openSidekick(id: pathParts[0])
        default:
            return nil
        }
    }
}
