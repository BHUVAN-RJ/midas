import Foundation

// A widget tap shows on the widget at once (founder, 2026-10-26: "+0.25 L saves but the widget
// does not change until Midas opens"). When the tap's intent cannot run in the app's process it
// waits in the App Group (PendingWidgetActionsFile) until Midas next runs, and the filled file the
// widget draws from still holds the old numbers. So the app also publishes the records of every
// Sidekick with a widget, and the widget extension refills the placed widget from those records
// with the waiting taps applied, the way the Reminders widget hides a ticked row before the app
// has written it. Compiled into the app and the widget extension.

/// The records of every Sidekick that has a widget, as of the app's last publish.
struct SidekickWidgetRecordsSnapshot: Codable, Equatable, Sendable {
    struct Record: Codable, Equatable, Sendable {
        let key: String
        let value: JSONValue
    }

    struct Sidekick: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let records: [Record]
    }

    /// Bumped when the file's shape changes; a reader ignores a version it does not know.
    static let currentFormatVersion = 1

    let formatVersion: Int
    let sidekicks: [Sidekick]

    init(sidekicks: [Sidekick]) {
        self.formatVersion = Self.currentFormatVersion
        self.sidekicks = sidekicks
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Nil for a missing or unreadable file, or an unknown format version.
    static func read(from fileURL: URL?) -> SidekickWidgetRecordsSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SidekickWidgetRecordsSnapshot.self, from: data) else {
            return nil
        }
        guard snapshot.formatVersion == currentFormatVersion else {
            return nil
        }
        return snapshot
    }

    func sidekick(id: String) -> Sidekick? {
        for sidekick in sidekicks where sidekick.id == id {
            return sidekick
        }
        return nil
    }
}

/// What a tap changes on a record that is not a reminder, as a JSON merge patch. The app's writer
/// (SidekickWidgetPublisher.patch) and the widget's preview both use it, so they agree.
enum SidekickWidgetTapPatch {
    /// Nil when there is nothing to change: an open, a tick on a missing record, a field missing.
    static func plainPatch(for currentValue: JSONValue?, by action: WidgetTapAction, now: Date) -> JSONValue? {
        switch action.kind {
        case .open:
            return nil
        case .tick:
            guard currentValue != nil else {
                return nil
            }
            return .object(["done": .bool(true), "completedAt": .string(ReminderRecord.formatDate(now))])
        case .increment:
            guard let field = action.field else {
                return nil
            }
            let currentNumber = currentValue?[field]?.numberValue ?? 0
            return .object([field: .number(currentNumber + (action.amount ?? 1))])
        case .toggle:
            guard let field = action.field else {
                return nil
            }
            let currentFlag = currentValue?[field]?.boolValue ?? false
            return .object([field: .bool(!currentFlag)])
        case .set:
            guard let field = action.field, let valueJSON = action.valueJSON,
                  let newValue = try? JSONDecoder().decode(JSONValue.self, from: Data(valueJSON.utf8)) else {
                return nil
            }
            return .object([field: newValue])
        }
    }
}

enum SidekickWidgetTapPreview {
    /// The widget refilled with the taps still waiting for the app; nil when no waiting tap changes
    /// a record of its Sidekick (draw the published widget as it is). Reminder ticks are left to
    /// the app: a ticked reminder's row comes off when the app writes it.
    static func widget(_ widget: FilledSidekickWidget?, snapshot: SidekickWidgetRecordsSnapshot?,
                       pendingActions: [PendingWidgetAction], now: Date, calendar: Calendar) -> FilledSidekickWidget? {
        guard let widget, widget.isUsable, let sidekick = snapshot?.sidekick(id: widget.sidekickId) else {
            return nil
        }
        var valuesByKey: [String: JSONValue] = [:]
        var keyOrder: [String] = []
        for record in sidekick.records {
            valuesByKey[record.key] = record.value
            keyOrder.append(record.key)
        }
        var changedAny = false
        for pendingAction in pendingActions where pendingAction.action.sidekickId == widget.sidekickId {
            guard let resolvedKey = previewKey(for: pendingAction, calendar: calendar) else {
                continue
            }
            let currentValue = valuesByKey[resolvedKey]
            guard let patch = SidekickWidgetTapPatch.plainPatch(for: currentValue, by: pendingAction.action, now: pendingAction.tappedAt) else {
                continue
            }
            if currentValue == nil {
                keyOrder.append(resolvedKey)
            }
            valuesByKey[resolvedKey] = JSONMergePatch.apply(patch, to: currentValue)
            changedAny = true
        }
        guard changedAny else {
            return nil
        }
        let widgetKey = SidekickWidgetShared.recordPrefix + widget.widgetId
        guard let widgetDescription = valuesByKey[widgetKey] else {
            return nil
        }
        var records: [LocalRecord] = []
        for key in keyOrder {
            guard let value = valuesByKey[key] else {
                continue
            }
            records.append(LocalRecord(sidekickId: widget.sidekickId, key: key, value: value))
        }
        let widgetRecord = LocalRecord(sidekickId: widget.sidekickId, key: widgetKey, value: widgetDescription)
        let filler = SidekickWidgetFiller(calendar: calendar)
        return filler.fill(sidekickId: widget.sidekickId, sidekickName: sidekick.name, record: widgetRecord,
                           sidekickRecords: records, now: now)
    }

    /// The record a waiting tap changes, with `{today}` resolved to the day it was tapped; nil for
    /// taps the preview leaves alone (opens, reminders, shell records).
    private static func previewKey(for pendingAction: PendingWidgetAction, calendar: Calendar) -> String? {
        let action = pendingAction.action
        guard action.kind != .open, let key = action.key else {
            return nil
        }
        guard !key.hasPrefix(ReminderRecord.keyPrefix), !SidekickWidgetDescription.isProtectedKey(key) else {
            return nil
        }
        return SidekickWidgetDayKey.resolve(key, at: pendingAction.tappedAt, calendar: calendar)
    }

    /// The published file with one widget swapped for its refilled copy.
    static func file(_ file: SharedSidekickWidgets, replacing refilledWidget: FilledSidekickWidget) -> SharedSidekickWidgets {
        var widgets: [FilledSidekickWidget] = []
        for publishedWidget in file.widgets {
            let isRefilled = publishedWidget.choiceId == refilledWidget.choiceId
            widgets.append(isRefilled ? refilledWidget : publishedWidget)
        }
        return SharedSidekickWidgets(widgets: widgets, savedAt: file.savedAt)
    }
}
