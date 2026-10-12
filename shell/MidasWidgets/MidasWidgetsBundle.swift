import SwiftUI
import WidgetKit

// The widget extension's entry point: the Folder (founder plan, 2026-10-11) and Reminders, today's
// reminders (founder, 2026-10-11).

@main
struct MidasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FolderWidget()
        RemindersWidget()
    }
}
