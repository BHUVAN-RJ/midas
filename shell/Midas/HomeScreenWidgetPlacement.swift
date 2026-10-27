import Foundation
import WidgetKit

// "Is my widget on the Home Screen?" (founder, 2026-10-27: Water's Widget button shows "only until
// the widget is added"; docs/mockups/water-add-widget-entry-2026-10-27.html, option A). A page asks
// `{ op: "widget-placed" }` on its store and gets `{ ok: true, placed: true | false }`; an older
// build answers "unknown op widget-placed" and the page shows no button (docs/WIDGETS.md).

/// One Sidekick widget on the Home Screen, as its settings pick it (nil: nothing picked).
struct PlacedSidekickWidget: Equatable, Sendable {
    let pickedSidekickId: String?
    let pickedWidgetChoiceId: String?
}

/// Where the placed Sidekick widgets come from: WidgetKit in the app, a list in tests.
protocol PlacedSidekickWidgetsSource: Sendable {
    func placedSidekickWidgets() async -> [PlacedSidekickWidget]
}

/// The Sidekick widgets WidgetKit says are on the Home Screen. Only the Sidekick widget's kind
/// counts; the Sidekicks folder does not.
struct WidgetCenterPlacedSidekickWidgets: PlacedSidekickWidgetsSource {
    // The completion-handler form: the async `currentConfigurations()` is iOS 18 and the app is 17
    func placedSidekickWidgets() async -> [PlacedSidekickWidget] {
        return await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: Self.sidekickWidgets(in: result))
            }
        }
    }

    private static func sidekickWidgets(in result: Result<[WidgetInfo], any Error>) -> [PlacedSidekickWidget] {
        guard case .success(let widgetInfos) = result else {
            return []
        }
        var placedWidgets: [PlacedSidekickWidget] = []
        for widgetInfo in widgetInfos where widgetInfo.kind == SidekickWidgetShared.kind {
            let intent = widgetInfo.widgetConfigurationIntent(of: SidekickWidgetIntent.self)
            placedWidgets.append(PlacedSidekickWidget(pickedSidekickId: intent?.sidekick?.id, pickedWidgetChoiceId: intent?.widget?.id))
        }
        return placedWidgets
    }
}

/// Whether a Sidekick's own widget is on the Home Screen.
struct HomeScreenWidgetPlacement: Sendable {
    let source: any PlacedSidekickWidgetsSource
    /// Where the last Sidekick opened that has a widget is kept (LastOpenedSidekickFile).
    let lastOpenedFileURL: URL?

    static func live() -> HomeScreenWidgetPlacement {
        return HomeScreenWidgetPlacement(source: WidgetCenterPlacedSidekickWidgets(), lastOpenedFileURL: SidekickWidgetShared.lastOpenedFileURL())
    }

    func isPlaced(sidekickId: String) async -> Bool {
        let placedWidgets = await source.placedSidekickWidgets()
        let lastOpenedSidekickId = LastOpenedSidekickFile.read(from: lastOpenedFileURL)
        return Self.isPlaced(sidekickId: sidekickId, among: placedWidgets, lastOpenedSidekickId: lastOpenedSidekickId)
    }

    /// A widget counts when its settings pick this Sidekick (or one of its widgets), or pick
    /// nothing and so show the last Sidekick opened, which is this one (SidekickWidgetLayout).
    static func isPlaced(sidekickId: String, among placedWidgets: [PlacedSidekickWidget], lastOpenedSidekickId: String?) -> Bool {
        for placedWidget in placedWidgets where shownSidekickId(of: placedWidget, lastOpenedSidekickId: lastOpenedSidekickId) == sidekickId {
            return true
        }
        return false
    }

    /// The Sidekick a placed widget shows. A picked widget's choice id is "<sidekickId>/<widgetId>".
    static func shownSidekickId(of placedWidget: PlacedSidekickWidget, lastOpenedSidekickId: String?) -> String? {
        if let pickedSidekickId = placedWidget.pickedSidekickId {
            return pickedSidekickId
        }
        guard let pickedWidgetChoiceId = placedWidget.pickedWidgetChoiceId else {
            return lastOpenedSidekickId
        }
        guard let slashIndex = pickedWidgetChoiceId.firstIndex(of: "/") else {
            return nil
        }
        return String(pickedWidgetChoiceId[..<slashIndex])
    }
}
