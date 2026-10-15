import AppIntents
import Foundation

// The Sidekick widget's settings and taps (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html). Compiled into the app and the widget
// extension, so MidasTests can run the pick lists against a sample file.
//
// Settings: pick a Sidekick, then one of its widgets (with only one, the second pick can be left
// empty). Each placed copy keeps its own picks, so two Sidekicks can each have a small widget, or
// one Sidekick several.
//
// Taps run in the app's process, as the Reminders widget's tick does (TickReminderIntent): a
// LiveActivityIntent in the app target runs there. If no handler is registered, the tap goes to
// an App Group file the app applies later.

/// Where the app plugs in its tap handler at launch. Nil in the widget extension.
@MainActor
enum SidekickWidgetIntentBridge {
    static var perform: (@MainActor (_ action: WidgetTapAction) async -> Void)?
}

/// Runs one tap of a Sidekick widget: a tick, an increment, a toggle or a set.
struct SidekickWidgetActionIntent: LiveActivityIntent {
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
            let pendingAction = PendingWidgetAction(action: action, tappedAt: Date())
            PendingWidgetActionsFile.append(pendingAction, to: SidekickWidgetShared.pendingActionsFileURL())
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

    init() {
        self.fileURL = SidekickWidgetShared.fileURL()
    }

    init(fileURL: URL?) {
        self.fileURL = fileURL
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
