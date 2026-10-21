import SwiftUI
import WidgetKit

// The widget extension's entry point: the Folder (founder plan, 2026-10-11) and Reminders, today's
// reminders (founder, 2026-10-11), Sidekick, the widget any Sidekick fills (founder, 2026-10-13), and
// on iOS 18 the Ask jess control (voice reminders, founder 2026-10-15).

@main
struct MidasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FolderWidget()
        RemindersWidget()
        SidekickWidget()
        if #available(iOS 18.0, *) {
            VoiceReminderControl()
        }
    }
}
