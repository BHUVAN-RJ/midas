import AppIntents
import Foundation
import WidgetKit

// The Sidekick widget's settings and taps (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html). Compiled into the app and the widget
// extension, so MidasTests can run the pick lists against a sample file.
//
// Settings: pick a Sidekick, then one of its widgets (with only one, the second pick can be left
// empty). Each placed copy keeps its own picks, so two Sidekicks can each have a small widget, or
// one Sidekick several.
//
// Taps run in the widget extension (founder, 2026-10-27: "clicking the button doesn't update it
// instantly. It takes a couple of seconds"). A plain AppIntent compiled into the app and the
// extension is performed in the extension's process for a widget button; the LiveActivityIntent of
// builds 14 to 20 was performed in the app's, which iOS first had to launch in the background. The
// tap is queued in the App Group and the widget redraws from the tap preview
// (SidekickWidgetTapPreview); the app writes the queue to the records when it next runs (launch,
// coming to the front, background refresh), with the tap's own time (tappedAt).

/// Where the app plugs in its tap handler at launch. Nil in the widget extension; used only if iOS
/// performs the intent in the app's process.
@MainActor
enum SidekickWidgetIntentBridge {
    static var perform: (@MainActor (_ action: WidgetTapAction) async -> Void)?
}

/// What the intent does in the widget extension: queue the tap, then redraw. Nothing else, so the
/// widget shows the tap as soon as iOS reloads it.
enum SidekickWidgetTapQueue {
    @MainActor
    static func queue(_ action: WidgetTapAction, tappedAt: Date, pendingActionsFileURL: URL?, reloadWidget: () -> Void) {
        let pendingAction = PendingWidgetAction(action: action, tappedAt: tappedAt)
        PendingWidgetActionsFile.append(pendingAction, to: pendingActionsFileURL)
        reloadWidget()
    }

    static func reloadSidekickTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: SidekickWidgetShared.kind)
    }
}

/// Runs one tap of a Sidekick widget: a tick, an increment, a toggle or a set.
struct SidekickWidgetActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Use Sidekick Widget"
    static let isDiscoverable = false

    /// The action as text (WidgetTapAction.encodedText()).
    @Parameter(title: "Action")
    var actionText: String

    init() {}

    init(action: WidgetTapAction) {
        self.actionText = action.encodedText()
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let action = WidgetTapAction.decoded(fromText: actionText) else {
            return .result()
        }
        guard let performHandler = SidekickWidgetIntentBridge.perform else {
            SidekickWidgetTapQueue.queue(action, tappedAt: Date(), pendingActionsFileURL: SidekickWidgetShared.pendingActionsFileURL(),
                                         reloadWidget: SidekickWidgetTapQueue.reloadSidekickTimelines)
            return .result()
        }
        await performHandler(action)
        return .result()
    }
}

// MARK: Settings

/// A Sidekick that has at least one widget.
struct WidgetSidekickEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sidekick")
    static let defaultQuery = WidgetSidekickQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetSidekickQuery: EntityQuery {
    let fileURL: URL?
    let lastOpenedFileURL: URL?

    init() {
        self.fileURL = SidekickWidgetShared.fileURL()
        self.lastOpenedFileURL = SidekickWidgetShared.lastOpenedFileURL()
    }

    init(fileURL: URL?, lastOpenedFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.lastOpenedFileURL = lastOpenedFileURL
    }

    /// A newly added widget starts on the last Sidekick opened that has a widget (founder,
    /// 2026-10-25/26); nil when there is none, and the person picks.
    func defaultResult() async -> WidgetSidekickEntity? {
        return lastOpenedEntity()
    }

    func lastOpenedEntity() -> WidgetSidekickEntity? {
        guard let lastOpenedId = LastOpenedSidekickFile.read(from: lastOpenedFileURL) else {
            return nil
        }
        for entity in allEntities() where entity.id == lastOpenedId {
            return entity
        }
        return nil
    }

    func allEntities() -> [WidgetSidekickEntity] {
        let file = SharedSidekickWidgets.read(from: fileURL)
        var entities: [WidgetSidekickEntity] = []
        for sidekick in file?.sidekicks() ?? [] {
            entities.append(WidgetSidekickEntity(id: sidekick.id, name: sidekick.name))
        }
        return entities
    }

    func entities(for identifiers: [String]) async throws -> [WidgetSidekickEntity] {
        var matchedEntities: [WidgetSidekickEntity] = []
        let entities = allEntities()
        for identifier in identifiers {
            for entity in entities where entity.id == identifier {
                matchedEntities.append(entity)
            }
        }
        return matchedEntities
    }

    func suggestedEntities() async throws -> [WidgetSidekickEntity] {
        return allEntities()
    }
}

/// One widget of one Sidekick; its id is "<sidekickId>/<widgetId>".
struct SidekickWidgetChoiceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget")
    static let defaultQuery = SidekickWidgetChoiceQuery()

    let id: String
    let name: String
    let sidekickId: String

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: "\(name)")
    }

    init(widget: FilledSidekickWidget) {
        self.id = widget.choiceId
        self.name = widget.name
        self.sidekickId = widget.sidekickId
    }
}

struct SidekickWidgetChoiceQuery: EntityQuery {
    /// The Sidekick picked above, so the list shows only its widgets.
    @IntentParameterDependency<SidekickWidgetIntent>(\.$sidekick)
    var widgetIntent

    let fileURL: URL?

    init() {
        self.fileURL = SidekickWidgetShared.fileURL()
    }

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The widgets of one Sidekick, or of every Sidekick when none is picked.
    func choices(sidekickId: String?) -> [SidekickWidgetChoiceEntity] {
        let file = SharedSidekickWidgets.read(from: fileURL)
        var choices: [SidekickWidgetChoiceEntity] = []
        for widget in file?.widgets ?? [] {
            let isOfPickedSidekick = sidekickId == nil || widget.sidekickId == sidekickId
            if isOfPickedSidekick {
                choices.append(SidekickWidgetChoiceEntity(widget: widget))
            }
        }
        return choices
    }

    func entities(for identifiers: [String]) async throws -> [SidekickWidgetChoiceEntity] {
        var matchedChoices: [SidekickWidgetChoiceEntity] = []
        let allChoices = choices(sidekickId: nil)
        for identifier in identifiers {
            for choice in allChoices where choice.id == identifier {
                matchedChoices.append(choice)
            }
        }
        return matchedChoices
    }

    func suggestedEntities() async throws -> [SidekickWidgetChoiceEntity] {
        let pickedSidekickId = widgetIntent?.sidekick.id
        return choices(sidekickId: pickedSidekickId)
    }
}

/// The widget's settings sheet.
struct SidekickWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Sidekick"
    static let description = IntentDescription("A Sidekick on your Home Screen.")

    @Parameter(title: "Sidekick")
    var sidekick: WidgetSidekickEntity?

    @Parameter(title: "Widget")
    var widget: SidekickWidgetChoiceEntity?

    init() {}
}
