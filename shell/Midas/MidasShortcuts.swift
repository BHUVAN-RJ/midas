import AppIntents

/// Midas's App Shortcuts: listed in the Shortcuts app under Midas, so the Action button can run
/// "New Reminder" (Settings → Action Button → Shortcut) on iOS 17 and later. Siri phrases must
/// contain the app's name (PRODUCT.md, mission check).
struct MidasShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceReminderIntent(),
            phrases: [
                "New reminder in \(.applicationName)",
                "Add a reminder in \(.applicationName)",
                "\(.applicationName) new reminder",
            ],
            shortTitle: "New Reminder",
            systemImageName: "mic"
        )
    }
}
