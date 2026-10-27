import Foundation
import WidgetKit

/// Fills every Sidekick's `widget:` records and writes them where the Sidekick widget reads them
/// (the App Group file named in shell/Shared/SidekickWidgetShared.swift), then asks WidgetKit to
/// redraw. Runs at launch, whenever a record of a Sidekick with widgets changes, and when Midas
/// comes to the front. Also runs the widget's taps: each changes one record of the Sidekick that
/// owns the widget. The app is the only writer.
@MainActor
final class SidekickWidgetPublisher {
    /// Nil when the App Group is not available: nothing is written and the app carries on.
    private let fileURL: URL?
    private let store: LocalRecordStore
    /// The user's Sidekicks (id, name); empty when signed out, which removes the file.
    private let sidekicks: @MainActor () -> [(id: String, name: String)]
    private let now: @MainActor () -> Date
    private let calendar: @MainActor () -> Calendar
    private let reloadWidget: @MainActor () -> Void
    /// Taps the widget saved for the app when their intent could not run here.
    private let pendingActionsFileURL: URL?
    /// The records the widget refills from to show a waiting tap at once (SidekickWidgetTapPreview).
    private let recordsFileURL: URL?
    /// Where the last Sidekick opened that has a widget is kept (LastOpenedSidekickFile).
    private let lastOpenedFileURL: URL?
    private var isApplyingPendingActions = false

    init(fileURL: URL?, store: LocalRecordStore,
         sidekicks: @escaping @MainActor () -> [(id: String, name: String)],
         now: @escaping @MainActor () -> Date,
         calendar: @escaping @MainActor () -> Calendar,
         reloadWidget: @escaping @MainActor () -> Void,
         pendingActionsFileURL: URL? = nil,
         recordsFileURL: URL? = nil,
         lastOpenedFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.store = store
        self.sidekicks = sidekicks
        self.now = now
        self.calendar = calendar
        self.reloadWidget = reloadWidget
        self.pendingActionsFileURL = pendingActionsFileURL
        self.recordsFileURL = recordsFileURL
        self.lastOpenedFileURL = lastOpenedFileURL
    }

    /// The publisher the app uses: the real App Group container, the phone's calendar, the real
    /// widget reload, the Sidekicks the directory lists while signed in.
    static func live(store: LocalRecordStore, directory: SidekickDirectory) -> SidekickWidgetPublisher {
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = {
            guard ShellServices.currentSessionToken() != nil else {
                return []
            }
            var signedInSidekicks: [(id: String, name: String)] = []
            for entry in directory.entries {
                signedInSidekicks.append((id: entry.id, name: entry.name))
            }
            return signedInSidekicks
        }
        return SidekickWidgetPublisher(fileURL: SidekickWidgetShared.fileURL(), store: store, sidekicks: listSidekicks,
                                       now: Date.init, calendar: currentPhoneCalendar, reloadWidget: reloadSidekickTimelines,
                                       pendingActionsFileURL: SidekickWidgetShared.pendingActionsFileURL(),
                                       recordsFileURL: SidekickWidgetShared.recordsFileURL(),
                                       lastOpenedFileURL: SidekickWidgetShared.lastOpenedFileURL())
    }

    /// A Sidekick was opened: when it has a widget it becomes the one a new Sidekick widget shows
    /// (founder, 2026-10-25/26). A Sidekick without a widget leaves the last one in place.
    func noteOpened(sidekickId: String) {
        let widgetRecords = store.query(sidekickId: sidekickId, keyPrefix: SidekickWidgetShared.recordPrefix)
        guard !widgetRecords.isEmpty else {
            return
        }
        guard LastOpenedSidekickFile.read(from: lastOpenedFileURL) != sidekickId else {
            return
        }
        LastOpenedSidekickFile.write(sidekickId, to: lastOpenedFileURL)
        reloadWidget()
    }

    /// Republishes whenever a record a widget may show changes.
    func startWatchingStore() {
        store.addChangeObserver(handleStoreChange)
    }

    private func handleStoreChange(_ change: LocalRecordChange) {
        guard affectsWidgets(change) else {
            return
        }
        publish()
    }

    /// A `widget:` record, or any record of a Sidekick that has a widget.
    func affectsWidgets(_ change: LocalRecordChange) -> Bool {
        if change.key.hasPrefix(SidekickWidgetShared.recordPrefix) {
            return true
        }
        let widgetRecords = store.query(sidekickId: change.sidekickId, keyPrefix: SidekickWidgetShared.recordPrefix)
        return !widgetRecords.isEmpty
    }

    /// The filled widgets of every Sidekick the user has, in Sidekick order then key order.
    func filledWidgets() -> [FilledSidekickWidget] {
        let filler = SidekickWidgetFiller(calendar: calendar())
        let moment = now()
        var widgets: [FilledSidekickWidget] = []
        for sidekick in sidekicks() {
            let widgetRecords = store.query(sidekickId: sidekick.id, keyPrefix: SidekickWidgetShared.recordPrefix)
            guard !widgetRecords.isEmpty else {
                continue
            }
            let sidekickRecords = store.query(sidekickId: sidekick.id, keyPrefix: "")
            for widgetRecord in widgetRecords {
                let filledWidget = filler.fill(sidekickId: sidekick.id, sidekickName: sidekick.name, record: widgetRecord,
                                               sidekickRecords: sidekickRecords, now: moment)
                widgets.append(filledWidget)
            }
        }
        return widgets
    }

    /// The records of every Sidekick the user has that has a widget, for the widget's tap preview.
    func recordsSnapshot() -> SidekickWidgetRecordsSnapshot {
        var snapshotSidekicks: [SidekickWidgetRecordsSnapshot.Sidekick] = []
        for sidekick in sidekicks() {
            let widgetRecords = store.query(sidekickId: sidekick.id, keyPrefix: SidekickWidgetShared.recordPrefix)
            guard !widgetRecords.isEmpty else {
                continue
            }
            var snapshotRecords: [SidekickWidgetRecordsSnapshot.Record] = []
            for record in store.query(sidekickId: sidekick.id, keyPrefix: "") {
                snapshotRecords.append(SidekickWidgetRecordsSnapshot.Record(key: record.key, value: record.value))
            }
            snapshotSidekicks.append(SidekickWidgetRecordsSnapshot.Sidekick(id: sidekick.id, name: sidekick.name, records: snapshotRecords))
        }
        return SidekickWidgetRecordsSnapshot(sidekicks: snapshotSidekicks)
    }

    /// Writes the filled widgets (or removes the file when there are none) and reloads the widget.
    /// A write that cannot happen is skipped quietly: the widget keeps what it had.
    func publish() {
        guard let fileURL else {
            return
        }
        applyPendingActions()
        let widgets = filledWidgets()
        guard !widgets.isEmpty else {
            removeRecordsFile()
            removeFile(at: fileURL)
            return
        }
        // The records first: the queue was just emptied into them, so the widget never counts a
        // tap twice (records with it plus the queue still holding it).
        writeRecordsFile()
        let file = SharedSidekickWidgets(widgets: widgets, savedAt: now())
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

    // MARK: Taps from the widget

    /// Runs a tap. Queued in the App Group first, so it is never lost if this run is cut short;
    /// then the queue is written to the records (outbox for sync, the other observers) and the
    /// widget redrawn.
    func perform(_ action: WidgetTapAction) {
        guard pendingActionsFileURL != nil else {
            // No App Group: nothing to queue in, so write straight away.
            _ = write(action, tappedAt: now())
            publish()
            return
        }
        let pendingAction = PendingWidgetAction(action: action, tappedAt: now())
        PendingWidgetActionsFile.append(pendingAction, to: pendingActionsFileURL)
        publish()
    }

    /// True when the record now holds the change, or the change can never apply (no such
    /// Sidekick, a protected key, no record to tick); false when the write failed and the tap must
    /// stay queued. A tap is written for now.
    func write(_ action: WidgetTapAction) -> Bool {
        return write(action, tappedAt: now())
    }

    /// The same, for a tap made at `tappedAt`: a `{today}` in its key is the day it was tapped on,
    /// not the day the app gets to write it.
    func write(_ action: WidgetTapAction, tappedAt: Date) -> Bool {
        guard action.kind != .open, let key = action.key else {
            return true
        }
        let isKnownSidekick = sidekicks().contains { sidekick in sidekick.id == action.sidekickId }
        guard isKnownSidekick else {
            return true
        }
        let isReminderTick = action.kind == .tick && key.hasPrefix(ReminderRecord.keyPrefix)
        guard isReminderTick || !SidekickWidgetDescription.isProtectedKey(key) else {
            return true
        }
        // A tick on an hourly time (`reminder:<id>@HHMM`, expanded for the widget) lands on the item.
        let targetKey = SidekickWidgetDayKey.resolve(Self.targetKey(for: action), at: tappedAt, calendar: calendar())
        let currentValue = store.get(sidekickId: action.sidekickId, key: targetKey)
        guard let patch = Self.patch(for: currentValue, by: action, now: now()) else {
            return true
        }
        do {
            try RecordWriter(store: store).update(sidekickId: action.sidekickId, key: targetKey, patch: patch)
            return true
        } catch {
            return false
        }
    }

    /// The record a tap writes: the item behind an expanded hourly time or early alert, else the
    /// tapped key itself.
    nonisolated static func targetKey(for action: WidgetTapAction) -> String {
        guard let key = action.key, key.hasPrefix(ReminderRecord.keyPrefix) else {
            return action.key ?? ""
        }
        let reminderId = String(key.dropFirst(ReminderRecord.keyPrefix.count))
        let (itemId, _) = ReminderExpansion.split(reminderId: reminderId)
        return ReminderRecord.keyPrefix + itemId
    }

    /// The record after a tap; nil when there is nothing to change (a tick on a missing record).
    nonisolated static func changedValue(_ currentValue: JSONValue?, by action: WidgetTapAction, now: Date) -> JSONValue? {
        guard let patch = patch(for: currentValue, by: action, now: now) else {
            return nil
        }
        return JSONMergePatch.apply(patch, to: currentValue)
    }

    /// What a tap changes, as a patch for `RecordWriter.update`; nil when there is nothing to
    /// change. A tick on a reminder is the Done every writer makes (`ReminderChange`); a tick on
    /// any other record sets `done` and `completedAt`.
    nonisolated static func patch(for currentValue: JSONValue?, by action: WidgetTapAction, now: Date) -> JSONValue? {
        switch action.kind {
        case .open:
            return nil
        case .tick:
            guard let currentValue else {
                return nil
            }
            if let key = action.key, key.hasPrefix(ReminderRecord.keyPrefix) {
                let reminderId = String(key.dropFirst(ReminderRecord.keyPrefix.count))
                let (_, part) = ReminderExpansion.split(reminderId: reminderId)
                return ReminderChange.donePatch(for: currentValue, part: part, occurrence: action.occurrence ?? now, now: now)
            }
            return SidekickWidgetTapPatch.plainPatch(for: currentValue, by: action, now: now)
        case .increment, .toggle, .set:
            return SidekickWidgetTapPatch.plainPatch(for: currentValue, by: action, now: now)
        }
    }

    /// Writes every queued tap; taps whose write failed stay queued for the next try. Each write
    /// makes the store observer publish again, which must not start a second pass over the queue.
    private func applyPendingActions() {
        guard !isApplyingPendingActions else {
            return
        }
        isApplyingPendingActions = true
        defer {
            isApplyingPendingActions = false
        }
        let queuedActions = PendingWidgetActionsFile.read(from: pendingActionsFileURL)
        guard !queuedActions.isEmpty else {
            return
        }
        var unwrittenActions: [PendingWidgetAction] = []
        for queuedAction in queuedActions where !write(queuedAction.action, tappedAt: queuedAction.tappedAt) {
            unwrittenActions.append(queuedAction)
        }
        // A tap queued by the widget while these were being written stays queued too.
        let actionsNow = PendingWidgetActionsFile.read(from: pendingActionsFileURL)
        for actionNow in actionsNow where !queuedActions.contains(actionNow) {
            unwrittenActions.append(actionNow)
        }
        PendingWidgetActionsFile.write(unwrittenActions, to: pendingActionsFileURL)
    }

    private func writeRecordsFile() {
        guard let recordsFileURL, let encodedSnapshot = try? recordsSnapshot().encoded() else {
            return
        }
        try? encodedSnapshot.write(to: recordsFileURL, options: [.atomic])
    }

    private func removeRecordsFile() {
        guard let recordsFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: recordsFileURL)
    }

    private func removeFile(at fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
        reloadWidget()
    }

    private static func currentPhoneCalendar() -> Calendar {
        SidekickWidgetDayKey.calendar(timeZone: .current)
    }

    private static func reloadSidekickTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: SidekickWidgetShared.kind)
    }
}
