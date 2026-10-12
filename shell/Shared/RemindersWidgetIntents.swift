import AppIntents
import Foundation

// The Reminders widget's buttons (brief docs/briefs/widget-reminders.md steps 4 and 5, founder
// 2026-10-11). Compiled into the app and the widget extension.
//
// Ticking runs in the app's process: Apple's "Adding interactivity to widgets and Live Activities"
// says the system runs a widget button's intent in the widget extension by default, but "if the
// intent conforms to ... LiveActivityIntent ... the system performs the app intent in the app's
// process" (the intent type must be in the app target, which shell/Shared/ is). So the tick writes
// the record through the app's own store: outbox (sync) and notification engine included. If no
// handler is registered (the intent ended up in the extension after all), the tick goes to an App
// Group file the app applies later, and the widget hides that row meanwhile.

/// Where the app plugs in its tick handler at launch. Nil in the widget extension.
@MainActor
enum RemindersWidgetIntentBridge {
    static var tick: (@MainActor (_ reminderId: String, _ occurrence: Date) async -> Void)?
}

/// Ticks one reminder done from the widget, as the Sidekick's own tick does.
struct TickReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Reminder Done"
    static let isDiscoverable = false

    @Parameter(title: "Reminder")
    var reminderId: String

    /// The occurrence the row showed (for a repeat, which day's is done).
    @Parameter(title: "Occurrence")
    var occurrence: Date

    init() {}

    init(reminderId: String, occurrence: Date) {
        self.reminderId = reminderId
        self.occurrence = occurrence
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let tickHandler = RemindersWidgetIntentBridge.tick else {
            let pendingTick = PendingReminderTick(reminderId: reminderId, occurrence: occurrence, tickedAt: Date())
            PendingReminderTicksFile.append(pendingTick, to: RemindersWidgetShared.pendingTicksFileURL())
            return .result()
        }
        await tickHandler(reminderId, occurrence)
        return .result()
    }
}

/// The up and down arrows: moves one size's page when today has more than fits.
struct PageRemindersIntent: AppIntent {
    static let title: LocalizedStringResource = "Page Reminders"
    static let isDiscoverable = false

    @Parameter(title: "Size")
    var familyName: String

    /// -1 for up, 1 for down.
    @Parameter(title: "Step")
    var step: Int

    @Parameter(title: "Pages")
    var pageCount: Int

    init() {}

    init(family: RemindersWidgetFamily, step: Int, pageCount: Int) {
        self.familyName = family.rawValue
        self.step = step
        self.pageCount = pageCount
    }

    func perform() async throws -> some IntentResult {
        guard let family = RemindersWidgetFamily(rawValue: familyName) else {
            return .result()
        }
        RemindersWidgetPagesFile.movePage(for: family, by: step, pageCount: pageCount, in: RemindersWidgetShared.pagesFileURL())
        return .result()
    }
}
