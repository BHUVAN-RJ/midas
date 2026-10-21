import AppIntents

/// Midas's App Shortcuts: listed in the Shortcuts app under Midas, so the Action button can run
/// "Ask jess" (Settings → Action Button → Shortcut) on iOS 17 and later. Siri phrases must
/// contain the app's name (PRODUCT.md, mission check); they stay as they were when the title became
/// "Ask jess" (founder, 2026-10-21).
struct MidasShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceReminderIntent(),
            phrases: [
                "New reminder in \(.applicationName)",
                "Add a reminder in \(.applicationName)",
                "\(.applicationName) new reminder",
            ],
            shortTitle: "Ask jess",
            systemImageName: "mic"
        )
    }
}
