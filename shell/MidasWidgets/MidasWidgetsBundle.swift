import SwiftUI
import WidgetKit

// The widget extension's entry point: Sidekick, the widget any Sidekick fills (founder, 2026-10-13;
// the Reminders Sidekick's own widget is one of these since 2026-10-26, so the separate Reminders
// widget is gone), the Folder (founder plan, 2026-10-11), and on iOS 18 the Ask jess control (voice
// reminders, founder 2026-10-15), and on iOS 26 the countdown card after Snooze on an alarm reminder
// (founder, 2026-10-24).
// The gallery lists widgets in this order; Sidekicks (the folder) is first (founder, 2026-10-27:
// "in the list it should be the first"; tests/guard/test_widget_gallery_order.py), so adding a
// Sidekick widget swipes past its one page.

@main
struct MidasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FolderWidget()
        SidekickWidget()
        if #available(iOS 18.0, *) {
            VoiceReminderControl()
        }
        if #available(iOS 26.0, *) {
            AlarmCountdownActivity()
        }
    }
}
