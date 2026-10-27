import AppIntents
import SwiftUI
import WidgetKit

// The Folder widget: Sidekick tiles on the Home Screen like an iOS folder (brief
// docs/briefs/widget-extension.md; mockups midas-intel docs/prototypes/widgets/). The logic is in
// shell/Shared/FolderWidgetLayout.swift; this file is WidgetKit plumbing and the views.

/// The configuration sheet: which Sidekicks fill the folder, in the order picked.
struct FolderWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Sidekicks"
    static let description = IntentDescription("Sidekicks on your Home Screen.")

    @Parameter(title: "Sidekicks", size: [.systemSmall: 4, .systemMedium: 8, .systemLarge: 16])
    var sidekicks: [SidekickEntity]?

    /// The picked ids in picked order; empty when nothing was picked.
    var pickedIds: [String] {
        let pickedEntities = sidekicks ?? []
        return pickedEntities.map(\.id)
    }
}

struct FolderWidgetEntry: TimelineEntry {
    let date: Date
    let content: FolderWidgetContent
}

struct FolderWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FolderWidgetEntry {
        let family = FolderWidgetFamilyMapping.family(for: context.family)
        let content = FolderWidgetLayout.content(pickedIds: [], sharedList: sharedEntries(), family: family)
        return FolderWidgetEntry(date: Date(), content: content)
    }

    func snapshot(for configuration: FolderWidgetIntent, in context: Context) async -> FolderWidgetEntry {
        return entry(for: configuration, in: context)
    }

    // One entry, never refreshed on a schedule: the app reloads the widget when the list changes.
    func timeline(for configuration: FolderWidgetIntent, in context: Context) async -> Timeline<FolderWidgetEntry> {
        let currentEntry = entry(for: configuration, in: context)
        return Timeline(entries: [currentEntry], policy: .never)
    }

    private func entry(for configuration: FolderWidgetIntent, in context: Context) -> FolderWidgetEntry {
        let family = FolderWidgetFamilyMapping.family(for: context.family)
        let content = FolderWidgetLayout.content(pickedIds: configuration.pickedIds, sharedList: sharedEntries(), family: family)
        return FolderWidgetEntry(date: Date(), content: content)
    }

    private func sharedEntries() -> [SidekickEntry]? {
        let sharedList = SharedSidekickListReader.read(from: WidgetShared.sidekickListFileURL())
        return sharedList?.sidekicks
    }
}

enum FolderWidgetFamilyMapping {
    /// WidgetKit's family to ours; anything the widget does not support draws as a large folder.
    static func family(for widgetFamily: WidgetFamily) -> FolderWidgetFamily {
        switch widgetFamily {
        case .systemSmall:
            return .small
        case .systemMedium:
            return .medium
        default:
            return .large
        }
    }
}

struct FolderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.folderWidgetKind, intent: FolderWidgetIntent.self, provider: FolderWidgetProvider()) { entry in
            FolderWidgetView(content: entry.content)
        }
        .configurationDisplayName(FolderWidgetCopy.displayName)
        .description(FolderWidgetCopy.description)
        // Small only (founder, 2026-10-26; tests/guard/test_folder_widget_sizes.py).
        .supportedFamilies([.systemSmall])
    }
}

// MARK: Views

enum FolderWidgetStyle {
    /// Icon side per family; the mockup uses 44 pt for all three.
    static let iconSize: CGFloat = 44
    static let nameFontSize: CGFloat = 11
    static let iconToNameSpacing: CGFloat = 3
    static let rowSpacing: CGFloat = 6
}

struct FolderWidgetView: View {
    let content: FolderWidgetContent

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        Group {
            switch content {
            case .empty:
                FolderEmptyView()
            case .tiles(let tiles):
                FolderTilesView(tiles: tiles, family: FolderWidgetFamilyMapping.family(for: widgetFamily))
            }
        }
        .widgetURL(MidasLink.home.url)
        .containerBackground(Color(uiColor: .systemBackground), for: .widget)
    }
}

/// No shared list, or an empty one. The whole widget opens Midas home (widgetURL above).
struct FolderEmptyView: View {
    var body: some View {
        Text(FolderWidgetCopy.empty)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FolderTilesView: View {
    let tiles: [SidekickEntry]
    let family: FolderWidgetFamily

    var body: some View {
        let rows = FolderWidgetLayout.rows(of: tiles, family: family)
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / CGFloat(family.columnCount)
            VStack(spacing: FolderWidgetStyle.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowTiles in
                    FolderRowView(tiles: rowTiles, cellWidth: cellWidth)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// One row of tiles. Every cell has the full grid's column width, and a short row is centred
/// (founder, 2026-10-11: one Sidekick sat in the top-left corner and looked off).
struct FolderRowView: View {
    let tiles: [SidekickEntry]
    let cellWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tiles) { tile in
                FolderTileView(sidekick: tile)
                    .frame(width: cellWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The icon the home grid draws, the name under it, and a link into that Sidekick.
struct FolderTileView: View {
    let sidekick: SidekickEntry

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Link(destination: MidasLink.openSidekick(id: sidekick.id).url) {
            VStack(spacing: FolderWidgetStyle.iconToNameSpacing) {
                tileIcon
                Text(sidekick.name)
                    .font(.system(size: FolderWidgetStyle.nameFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
            }
        }
    }

    /// In the accented (tinted, clear) mode iOS maps the icon to the accent colour by luminance,
    /// so the icon keeps its shape against the name, which stays in the primary colour.
    @ViewBuilder
    private var tileIcon: some View {
        let iconContent = SidekickIconContent.content(for: sidekick)
        let iconView = SidekickIconView(content: iconContent, size: FolderWidgetStyle.iconSize)
        if renderingMode == .accented {
            iconView.widgetAccentable()
        } else {
            iconView
        }
    }
}
