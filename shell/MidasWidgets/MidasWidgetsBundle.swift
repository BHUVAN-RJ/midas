import SwiftUI
import WidgetKit

// The widget extension's entry point: the Folder (founder plan, 2026-10-11) and Reminders, today's
// reminders (founder, 2026-10-11), Sidekick, the widget any Sidekick fills (founder, 2026-10-13), and
// on iOS 18 the Ask jess control (voice reminders, founder 2026-10-15), and on iOS 26 the countdown
// card after Snooze on an alarm reminder (founder, 2026-10-24).
// The gallery lists widgets in this order; Sidekick is first so adding one needs no swipe
// (founder, 2026-10-25; tests/guard/test_widget_gallery_order.py).

@main
struct MidasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SidekickWidget()
        FolderWidget()
        RemindersWidget()
        if #available(iOS 18.0, *) {
            VoiceReminderControl()
        }
        if #available(iOS 26.0, *) {
            AlarmCountdownActivity()
        }
    }
}
