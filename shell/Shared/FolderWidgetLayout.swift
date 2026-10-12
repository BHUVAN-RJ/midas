import Foundation

// The Folder widget's logic, free of WidgetKit so MidasTests can test it through the app module
// (brief docs/briefs/widget-extension.md, founder plan 2026-10-11). The views live in
// shell/MidasWidgets/.

/// The words the Folder widget shows. Only these four; docs/WRITING.md rules.
enum FolderWidgetCopy {
    /// Not "Folder" (founder, 2026-10-11): no name that borrows an Apple Home Screen feature.
    static let displayName = "Sidekicks"
    static let description = "Sidekicks on your Home Screen."
    static let sidekicksParameterTitle = "Sidekicks"
    static let empty = "Open Midas"
}

/// The three home screen sizes the Folder widget supports, with their tile grids.
enum FolderWidgetFamily: CaseIterable, Sendable {
    case small
    case medium
    case large

    /// How many Sidekick tiles fit: 2x2, 4x2, 4x4.
    var tileLimit: Int {
        switch self {
        case .small:
            return 4
        case .medium:
            return 8
        case .large:
            return 16
        }
    }

    var columnCount: Int {
        switch self {
        case .small:
            return 2
        case .medium, .large:
            return 4
        }
    }

    var rowCount: Int {
        return tileLimit / columnCount
    }
}

/// What the widget draws for one configuration and one shared list.
enum FolderWidgetContent: Equatable, Sendable {
    /// No shared list, or an empty one: "Open Midas".
    case empty
    /// Up to the family's limit, in the order the person picked (or home grid order by default).
    case tiles([SidekickEntry])
}

enum FolderWidgetLayout {
    /// The tiles for a family: nothing picked gives the first tiles of the shared list in home
    /// grid order; picked ids keep their order and ids no longer in the list are dropped.
    static func tiles(pickedIds: [String], sharedList: [SidekickEntry], family: FolderWidgetFamily) -> [SidekickEntry] {
        let orderedTiles: [SidekickEntry]
        if pickedIds.isEmpty {
            orderedTiles = sharedList
        } else {
            orderedTiles = pickedEntries(pickedIds: pickedIds, sharedList: sharedList)
        }
        return Array(orderedTiles.prefix(family.tileLimit))
    }

    /// The content for a family. An empty shared list is the empty state even when ids were picked;
    /// picked ids that are all gone from the list fall back to the default fill.
    static func content(pickedIds: [String], sharedList: [SidekickEntry]?, family: FolderWidgetFamily) -> FolderWidgetContent {
        guard let sharedList, !sharedList.isEmpty else {
            return .empty
        }
        let pickedTiles = tiles(pickedIds: pickedIds, sharedList: sharedList, family: family)
        if pickedTiles.isEmpty {
            let defaultTiles = tiles(pickedIds: [], sharedList: sharedList, family: family)
            return .tiles(defaultTiles)
        }
        return .tiles(pickedTiles)
    }

    /// Tiles split into rows of the family's column count; the last row may be short.
    static func rows(of tiles: [SidekickEntry], family: FolderWidgetFamily) -> [[SidekickEntry]] {
        let columnCount = family.columnCount
        var rows: [[SidekickEntry]] = []
        var rowStart = 0
        while rowStart < tiles.count {
            let rowEnd = min(rowStart + columnCount, tiles.count)
            rows.append(Array(tiles[rowStart..<rowEnd]))
            rowStart = rowEnd
        }
        return rows
    }

    /// Picked ids in picked order, each resolved against the shared list; unknown ids dropped,
    /// an id picked twice shown once.
    private static func pickedEntries(pickedIds: [String], sharedList: [SidekickEntry]) -> [SidekickEntry] {
        var entriesById: [String: SidekickEntry] = [:]
        for entry in sharedList {
            entriesById[entry.id] = entry
        }
        var seenIds: Set<String> = []
        var pickedEntries: [SidekickEntry] = []
        for pickedId in pickedIds {
            guard let entry = entriesById[pickedId] else {
                continue
            }
            guard seenIds.insert(pickedId).inserted else {
                continue
            }
            pickedEntries.append(entry)
        }
        return pickedEntries
    }
}

/// Reads the shared Sidekick list the app writes into the App Group container.
enum SharedSidekickListReader {
    /// Nil when there is no file, it cannot be read, or its format is unknown.
    static func read(from fileURL: URL?) -> SharedSidekickList? {
        guard let fileURL else {
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return SharedSidekickList.decoded(from: data)
    }
}
