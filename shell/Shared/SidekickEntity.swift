import AppIntents
import Foundation

// A Sidekick as the widget configuration sheet offers it (brief docs/briefs/widget-extension.md).
// Compiled into both targets so MidasTests can run the query against a sample list file.

/// One Sidekick the person can pick for the Folder widget.
struct SidekickEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sidekick")
    static let defaultQuery = SidekickEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: "\(name)")
    }

    init(entry: SidekickEntry) {
        self.id = entry.id
        self.name = entry.name
    }
}

/// Answers the configuration sheet from the shared list the app writes.
struct SidekickEntityQuery: EntityQuery {
    /// Where the shared list lives; nil when the App Group container is not available.
    let listFileURL: URL?

    init() {
        self.listFileURL = WidgetShared.sidekickListFileURL()
    }

    init(listFileURL: URL?) {
        self.listFileURL = listFileURL
    }

    /// The shared list's entries, in home grid order; empty when there is no list.
    func sharedEntries() -> [SidekickEntry] {
        let sharedList = SharedSidekickListReader.read(from: listFileURL)
        return sharedList?.sidekicks ?? []
    }

    func entities(for identifiers: [String]) async throws -> [SidekickEntity] {
        let entries = sharedEntries()
        var entriesById: [String: SidekickEntry] = [:]
        for entry in entries {
            entriesById[entry.id] = entry
        }
        var matchedEntities: [SidekickEntity] = []
        for identifier in identifiers {
            guard let entry = entriesById[identifier] else {
                continue
            }
            matchedEntities.append(SidekickEntity(entry: entry))
        }
        return matchedEntities
    }

    func suggestedEntities() async throws -> [SidekickEntity] {
        let entries = sharedEntries()
        return entries.map(SidekickEntity.init(entry:))
    }
}
