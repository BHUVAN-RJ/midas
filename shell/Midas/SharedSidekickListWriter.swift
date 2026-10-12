import Foundation
import WidgetKit

/// Writes the home grid's Sidekick list where the widget reads it (the App Group file named in
/// shell/Shared/WidgetShared.swift), then asks WidgetKit to redraw. The app is the only writer.
struct SharedSidekickListWriter: Sendable {
    /// Nil when the App Group is not available (an unsigned build, the entitlement missing):
    /// then nothing is written and the app carries on.
    let fileURL: URL?
    let now: @Sendable () -> Date
    let reloadWidgets: @Sendable () -> Void

    init(fileURL: URL?, now: @escaping @Sendable () -> Date, reloadWidgets: @escaping @Sendable () -> Void) {
        self.fileURL = fileURL
        self.now = now
        self.reloadWidgets = reloadWidgets
    }

    /// The writer the app uses: the real App Group container and the real widget reload.
    static func live(fileManager: FileManager = .default) -> SharedSidekickListWriter {
        let fileURL = WidgetShared.sidekickListFileURL(fileManager: fileManager)
        return SharedSidekickListWriter(fileURL: fileURL, now: Date.init, reloadWidgets: reloadAllWidgetTimelines)
    }

    /// Writes `entries` in the order given (home grid order). A write that cannot happen is
    /// skipped quietly: the widget keeps the last list it had.
    func write(entries: [SidekickEntry]) {
        guard let fileURL else {
            return
        }
        let list = SharedSidekickList(sidekicks: entries, savedAt: now())
        guard let encodedList = try? list.encoded() else {
            return
        }
        // Atomic, so the widget never reads a half-written file.
        let didWrite = (try? encodedList.write(to: fileURL, options: [.atomic])) != nil
        guard didWrite else {
            return
        }
        reloadWidgets()
    }

    @Sendable
    private static func reloadAllWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
