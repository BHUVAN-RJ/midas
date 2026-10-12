import Foundation
import WidgetKit

/// Writes the Reminders Sidekick's Today where the Reminders widget reads it (the App Group file
/// named in shell/Shared/RemindersWidgetShared.swift), then asks WidgetKit to redraw that widget.
/// Runs at launch, whenever a `reminder:` or `list:` record of that Sidekick changes, and when
/// Midas comes to the front. The app is the only writer.
@MainActor
final class RemindersWidgetPublisher {
    /// Nil when the App Group is not available (an unsigned build, the entitlement missing):
    /// then nothing is written and the app carries on.
    private let fileURL: URL?
    private let store: LocalRecordStore
    /// False when signed out or the user has no Reminders Sidekick: the file is removed and the
    /// widget shows "Open Midas".
    private let isAvailable: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private let calendar: @MainActor () -> Calendar
    private let reloadWidget: @MainActor () -> Void

    init(fileURL: URL?, store: LocalRecordStore,
         isAvailable: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date,
         calendar: @escaping @MainActor () -> Calendar,
         reloadWidget: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.store = store
        self.isAvailable = isAvailable
        self.now = now
        self.calendar = calendar
        self.reloadWidget = reloadWidget
    }

    /// The publisher the app uses: the real App Group container, the phone's calendar, the real
    /// widget reload. Available when signed in and the directory lists the Reminders Sidekick.
    static func live(store: LocalRecordStore, directory: SidekickDirectory) -> RemindersWidgetPublisher {
        let fileURL = RemindersWidgetShared.fileURL()
        let isAvailable: @MainActor () -> Bool = {
            let isSignedIn = ShellServices.currentSessionToken() != nil
            let hasRemindersSidekick = directory.entry(withId: RemindersWidgetShared.sidekickId) != nil
            return isSignedIn && hasRemindersSidekick
        }
        return RemindersWidgetPublisher(fileURL: fileURL, store: store, isAvailable: isAvailable,
                                        now: Date.init, calendar: currentPhoneCalendar,
                                        reloadWidget: reloadRemindersTimelines)
    }

    /// Republishes whenever a record the widget depends on changes.
    func startWatchingStore() {
        store.addChangeObserver(handleStoreChange)
    }

    private func handleStoreChange(_ change: LocalRecordChange) {
        guard Self.affectsWidget(change) else {
            return
        }
        publish()
    }

    /// A `reminder:` or `list:` record of the Reminders Sidekick.
    static func affectsWidget(_ change: LocalRecordChange) -> Bool {
        guard change.sidekickId == RemindersWidgetShared.sidekickId else {
            return false
        }
        return change.key.hasPrefix(ReminderRecord.keyPrefix) || change.key.hasPrefix("list:")
    }

    /// Writes the current Today (or removes the file when unavailable) and reloads the widget.
    /// A write that cannot happen is skipped quietly: the widget keeps what it had.
    func publish() {
        guard let fileURL else {
            return
        }
        guard isAvailable() else {
            removeFile(at: fileURL)
            return
        }
        let sidekickId = RemindersWidgetShared.sidekickId
        let reminderRecords = store.query(sidekickId: sidekickId, keyPrefix: ReminderRecord.keyPrefix)
        let listRecords = store.query(sidekickId: sidekickId, keyPrefix: "list:")
        let planner = TodayReminderPlanner(calendar: calendar())
        let days = planner.days(reminderRecords: reminderRecords, listRecords: listRecords, now: now())
        let file = SharedTodayReminders(days: days, savedAt: now())
        guard let encodedFile = try? file.encoded() else {
            return
        }
        // Atomic, so the widget never reads a half-written file.
        let didWrite = (try? encodedFile.write(to: fileURL, options: [.atomic])) != nil
        guard didWrite else {
            return
        }
        reloadWidget()
    }

    private func removeFile(at fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
        reloadWidget()
    }

    private static func currentPhoneCalendar() -> Calendar {
        ReminderSchedule.phoneCalendar(timeZone: .current)
    }

    private static func reloadRemindersTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: RemindersWidgetShared.kind)
    }
}
