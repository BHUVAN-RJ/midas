import Foundation

/// The App Group files the separate Reminders widget kept (Today's list, ticks waiting for the
/// app, the page each size showed). That widget was retired on 2026-10-26 (founder: the Reminders
/// Sidekick makes its own widget through the widget builder), so the app removes them at launch.
/// A tick still waiting in the old file is dropped with it; the person ticks it again.
enum RetiredRemindersWidgetFiles {
    static let fileNames = ["widget-reminders-today.json", "widget-reminders-ticks.json", "widget-reminders-pages.json"]

    /// Removes the files from the App Group container (or `container`, for tests); nothing
    /// happens when the container is not available or a file is already gone.
    static func remove(container: URL? = nil, fileManager: FileManager = .default) {
        let appGroupContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupIdentifier)
        guard let folder = container ?? appGroupContainer else {
            return
        }
        for fileName in fileNames {
            let fileURL = folder.appending(path: fileName)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
