import AppIntents
import Foundation

// "New Reminder" (voice reminders, brief item 2, founder 2026-10-15: Action button, speak, leave).
// One intent behind every way in: the Shortcuts app and the Action button's Shortcut (through
// MidasShortcuts, an AppShortcutsProvider in the app), and on iOS 18 the control in MidasWidgets
// (Action button → Controls, Control Center). Compiled into the app and the widget extension.
//
// openAppWhenRun: iOS brings Midas to the front and runs perform() in the app's process, where the
// app has registered its handler; the handler shows the Listening screen.

/// Where the app plugs in what "New Reminder" does at launch. Nil in the widget extension.
@MainActor
enum VoiceReminderIntentBridge {
    static var open: (@MainActor () -> Void)?
}

struct StartVoiceReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "New Reminder"
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceReminderIntentBridge.open?()
        return .result()
    }
}
