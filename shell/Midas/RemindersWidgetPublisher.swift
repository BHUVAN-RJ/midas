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
    /// Ticks the widget saved for the app when its intent could not run here.
    private let pendingTicksFileURL: URL?
    private var isApplyingPendingTicks = false

    init(fileURL: URL?, store: LocalRecordStore,
         isAvailable: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date,
         calendar: @escaping @MainActor () -> Calendar,
         reloadWidget: @escaping @MainActor () -> Void,
         pendingTicksFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.pendingTicksFileURL = pendingTicksFileURL
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
                                        reloadWidget: reloadRemindersTimelines,
                                        pendingTicksFileURL: RemindersWidgetShared.pendingTicksFileURL())
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
        applyPendingTicks()
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

    // MARK: Ticks from the widget

    /// Marks a reminder done from the widget. The tick is queued in the App Group first, so it is
    /// never lost: if this run is cut short, the next launch, return to the front, reminder change
    /// or background refresh writes it (the widget keeps hiding the row meanwhile). Then the queue
    /// is written to the records (outbox for sync, the notification engine's observer) and the
    /// widget redrawn without the row.
    func tick(reminderId: String, occurrence: Date) {
        guard pendingTicksFileURL != nil else {
            // No App Group: nothing to queue in, so write straight away.
            _ = writeTick(reminderId: reminderId, occurrence: occurrence)
            publish()
            return
        }
        let queuedTick = PendingReminderTick(reminderId: reminderId, occurrence: occurrence, tickedAt: now())
        PendingReminderTicksFile.append(queuedTick, to: pendingTicksFileURL)
        publish()
    }

    /// True when the record now holds the tick, or there is no such reminder any more; false when
    /// the write failed and the tick must stay queued.
    private func writeTick(reminderId: String, occurrence: Date) -> Bool {
        let sidekickId = RemindersWidgetShared.sidekickId
        let key = ReminderRecord.keyPrefix + reminderId
        guard let currentValue = store.get(sidekickId: sidekickId, key: key) else {
            return true
        }
        let patch = ReminderChange.donePatch(for: currentValue, part: .item, occurrence: occurrence, now: now())
        do {
            try RecordWriter(store: store).update(sidekickId: sidekickId, key: key, patch: patch)
            return true
        } catch {
            return false
        }
    }

    /// Writes every queued tick; ticks whose write failed stay queued for the next try. Each write
    /// makes the store observer publish again, which must not start a second pass over the queue.
    private func applyPendingTicks() {
        guard !isApplyingPendingTicks else {
            return
        }
        isApplyingPendingTicks = true
        defer {
            isApplyingPendingTicks = false
        }
        let queuedTicks = PendingReminderTicksFile.read(from: pendingTicksFileURL)
        guard !queuedTicks.isEmpty else {
            return
        }
        var unwrittenTicks: [PendingReminderTick] = []
        for queuedTick in queuedTicks {
            let isWritten = writeTick(reminderId: queuedTick.reminderId, occurrence: queuedTick.occurrence)
            if !isWritten {
                unwrittenTicks.append(queuedTick)
            }
        }
        // A tick queued by the widget while these were being written stays queued too.
        let ticksNow = PendingReminderTicksFile.read(from: pendingTicksFileURL)
        for tickNow in ticksNow where !queuedTicks.contains(tickNow) {
            unwrittenTicks.append(tickNow)
        }
        PendingReminderTicksFile.write(unwrittenTicks, to: pendingTicksFileURL)
    }

    /// The record after a tick: the Done patch every writer uses (`ReminderChange.donePatch`, the
    /// Sidekick's `markDoneChange`), merged into the record.
    nonisolated static func tickedValue(_ value: JSONValue, occurrence: Date, now: Date) -> JSONValue {
        guard case .object = value else {
            return value
        }
        let patch = ReminderChange.donePatch(for: value, part: .item, occurrence: occurrence, now: now)
        return JSONMergePatch.apply(patch, to: value)
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
