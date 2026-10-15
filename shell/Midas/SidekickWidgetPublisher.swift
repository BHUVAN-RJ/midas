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
    private var isApplyingPendingActions = false

    init(fileURL: URL?, store: LocalRecordStore,
         sidekicks: @escaping @MainActor () -> [(id: String, name: String)],
         now: @escaping @MainActor () -> Date,
         calendar: @escaping @MainActor () -> Calendar,
         reloadWidget: @escaping @MainActor () -> Void,
         pendingActionsFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.store = store
        self.sidekicks = sidekicks
        self.now = now
        self.calendar = calendar
        self.reloadWidget = reloadWidget
        self.pendingActionsFileURL = pendingActionsFileURL
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
                                       pendingActionsFileURL: SidekickWidgetShared.pendingActionsFileURL())
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

    /// Writes the filled widgets (or removes the file when there are none) and reloads the widget.
    /// A write that cannot happen is skipped quietly: the widget keeps what it had.
    func publish() {
        guard let fileURL else {
            return
        }
        applyPendingActions()
        let widgets = filledWidgets()
        guard !widgets.isEmpty else {
            removeFile(at: fileURL)
            return
        }
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
            _ = write(action)
            publish()
            return
        }
        let pendingAction = PendingWidgetAction(action: action, tappedAt: now())
        PendingWidgetActionsFile.append(pendingAction, to: pendingActionsFileURL)
        publish()
    }

    /// True when the record now holds the change, or the change can never apply (no such
    /// Sidekick, a protected key, no record to tick); false when the write failed and the tap must
    /// stay queued.
    func write(_ action: WidgetTapAction) -> Bool {
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
        let currentValue = store.get(sidekickId: action.sidekickId, key: key)
        guard let changedValue = Self.changedValue(currentValue, by: action, now: now()) else {
            return true
        }
        do {
            try store.set(sidekickId: action.sidekickId, key: key, value: changedValue)
            return true
        } catch {
            return false
        }
    }

    /// The record after a tap; nil when there is nothing to change (a tick on a missing record).
    nonisolated static func changedValue(_ currentValue: JSONValue?, by action: WidgetTapAction, now: Date) -> JSONValue? {
        var fields: [String: JSONValue] = [:]
        if case .object(let currentFields)? = currentValue {
            fields = currentFields
        }
        switch action.kind {
        case .open:
            return nil
        case .tick:
            guard let currentValue else {
                return nil
            }
            if action.key?.hasPrefix(ReminderRecord.keyPrefix) == true {
                return RemindersWidgetPublisher.tickedValue(currentValue, occurrence: action.occurrence ?? now, now: now)
            }
            fields["done"] = .bool(true)
            fields["completedAt"] = .string(ReminderRecord.formatDate(now))
            return .object(fields)
        case .increment:
            guard let field = action.field else {
                return nil
            }
            let currentNumber = fields[field]?.numberValue ?? 0
            fields[field] = .number(currentNumber + (action.amount ?? 1))
            return .object(fields)
        case .toggle:
            guard let field = action.field else {
                return nil
            }
            let currentFlag = fields[field]?.boolValue ?? false
            fields[field] = .bool(!currentFlag)
            return .object(fields)
        case .set:
            guard let field = action.field, let valueJSON = action.valueJSON,
                  let newValue = try? JSONDecoder().decode(JSONValue.self, from: Data(valueJSON.utf8)) else {
                return nil
            }
            fields[field] = newValue
            return .object(fields)
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
        for queuedAction in queuedActions where !write(queuedAction.action) {
            unwrittenActions.append(queuedAction)
        }
        // A tap queued by the widget while these were being written stays queued too.
        let actionsNow = PendingWidgetActionsFile.read(from: pendingActionsFileURL)
        for actionNow in actionsNow where !queuedActions.contains(actionNow) {
            unwrittenActions.append(actionNow)
        }
        PendingWidgetActionsFile.write(unwrittenActions, to: pendingActionsFileURL)
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

    private static func reloadSidekickTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: SidekickWidgetShared.kind)
    }
}
