import Foundation

/// The one way the shell changes a Sidekick's record (unified data plan, section 5, "Native
/// writers"): read the record, merge the patch (RFC 7396), run the store's write gate (`$type`,
/// the record's schema), check the size limit, write. The notification buttons, both widgets and
/// the Apple Reminders import all go through here with the same patches the pages produce
/// (`ReminderChange`), so a change gives the same record whoever made it. A patch touches only
/// the fields it names: unknown fields are kept.
@MainActor
final class RecordWriter {
    /// The server keeps values up to this size (backend/src/sync.ts MAX_VALUE_BYTES).
    static let maxValueBytes = SidekickStoreChannel.maxValueBytes

    private let store: LocalRecordStore

    init(store: LocalRecordStore) {
        self.store = store
    }

    /// The record as stored after the patch. A record that does not exist yet is built from the
    /// patch alone. Throws `RecordRefusal` with the reason when the result does not fit its type
    /// or is over the size limit; nothing is written then.
    @discardableResult
    func update(sidekickId: String, key: String, patch: JSONValue) throws -> JSONValue {
        let currentValue = store.get(sidekickId: sidekickId, key: key)
        let mergedValue = JSONMergePatch.apply(patch, to: currentValue)
        if RecordSync.valueByteCount(mergedValue) > Self.maxValueBytes {
            throw RecordRefusal(reason: "value is over \(Self.maxValueBytes) bytes")
        }
        try store.set(sidekickId: sidekickId, key: key, value: mergedValue)
        return store.get(sidekickId: sidekickId, key: key) ?? mergedValue
    }

    /// Applies what a Sidekick tool returned (jess router, founder 2026-10-21): whole records to
    /// store and keys to remove. Every stored value passes the write gate and the size limit
    /// before anything is written, so a tool that fails a check changes nothing; then the ops are
    /// written in order. Throws `RecordRefusal` naming the key that failed.
    func apply(sidekickId: String, ops: [SidekickToolOp]) throws {
        var checkedOps: [SidekickToolOp] = []
        for op in ops {
            switch op {
            case .set(let key, let value):
                let checkedValue: JSONValue
                do {
                    checkedValue = try store.checkedValue(sidekickId: sidekickId, key: key, value: value)
                } catch let refusal as RecordRefusal {
                    throw RecordRefusal(reason: "\(key): \(refusal.reason)")
                }
                if RecordSync.valueByteCount(checkedValue) > Self.maxValueBytes {
                    throw RecordRefusal(reason: "\(key): value is over \(Self.maxValueBytes) bytes")
                }
                checkedOps.append(.set(key: key, value: checkedValue))
            case .delete:
                checkedOps.append(op)
            }
        }
        for op in checkedOps {
            switch op {
            case .set(let key, let value):
                try store.set(sidekickId: sidekickId, key: key, value: value)
            case .delete(let key):
                try store.delete(sidekickId: sidekickId, key: key)
            }
        }
    }
}

/// What Done and Snooze change on a reminder record, as patches. The same fields the same way
/// everywhere (founder, 2026-10-15): the Reminders page's `markDoneChange`, the care-reminders
/// page's Done, the notification buttons and both widgets all produce these.
///
///   Done, one-time:          { done: true, completedAt: now, snoozedUntil: removed, the alerts'
///                              snoozes removed }
///   Done, repeat:            { lastDoneAt: now, doneThrough: the occurrence (never earlier than
///                              before), snoozedUntil: removed, the alerts' snoozes removed }
///   Done on an hourly time:  { slotsDone: { "HH:MM": now }, that time's snooze removed }
///   Snooze on the item:      { snoozedUntil: when }
///   Snooze on an alert/time: { snoozes: { "~rule" | "@HHMM": when } }
///
/// Done on an early alert completes the event it is for (founder, 2026-10-12): the same patch
/// as Done on the item, for the occurrence the alert served. Each early alert and hourly time
/// has its own snooze, independent of the item's and of each other's (founder, 2026-10-15); the
/// snooze entries a Done removes are the ones the record holds, so a record without any is not
/// touched.
enum ReminderChange {
    static func donePatch(for value: JSONValue, part: ReminderExpansion.Part, occurrence: Date?, now: Date) -> JSONValue {
        var patch: [String: JSONValue] = [:]
        switch part {
        case .item, .alert:
            patch["snoozedUntil"] = .null
            let isRepeat = value["repeat"] != nil && value["repeat"] != .null
            if isRepeat {
                patch["lastDoneAt"] = .string(ReminderRecord.formatDate(now))
                if let occurrence {
                    patch["doneThrough"] = .string(ReminderRecord.formatDate(laterDoneThrough(current: value["doneThrough"], occurrence: occurrence)))
                }
            } else {
                patch["done"] = .bool(true)
                patch["completedAt"] = .string(ReminderRecord.formatDate(now))
            }
            // The event is done: every early alert's snooze for it goes; the hourly times keep theirs.
            if let snoozesPatch = snoozesRemovalPatch(for: value, removing: alertSnoozeSuffixes(in: value)) {
                patch["snoozes"] = snoozesPatch
            }
        case .slot(let time):
            patch["slotsDone"] = .object([time: .string(ReminderRecord.formatDate(now))])
            if let snoozesPatch = snoozesRemovalPatch(for: value, removing: [ReminderExpansion.suffix(of: part)]) {
                patch["snoozes"] = snoozesPatch
            }
        }
        return .object(patch)
    }

    /// The keys of the record's `snoozes` that belong to early alerts (`~rule`).
    static func alertSnoozeSuffixes(in value: JSONValue) -> [String] {
        guard case .object(let snoozeFields)? = value["snoozes"] else {
            return []
        }
        var suffixes: [String] = []
        for suffix in snoozeFields.keys where suffix.hasPrefix(ReminderExpansion.alertSeparator) {
            suffixes.append(suffix)
        }
        return suffixes
    }

    /// The `snoozes` part of a patch that removes the given entries: null for the whole field
    /// when nothing would stay, nil when the record holds none of them.
    static func snoozesRemovalPatch(for value: JSONValue, removing suffixes: [String]) -> JSONValue? {
        guard case .object(let snoozeFields)? = value["snoozes"] else {
            return nil
        }
        var removals: [String: JSONValue] = [:]
        for suffix in suffixes where snoozeFields[suffix] != nil {
            removals[suffix] = .null
        }
        if removals.isEmpty {
            return nil
        }
        if removals.count == snoozeFields.count {
            return .null
        }
        return .object(removals)
    }

    /// Snooze on the item's own notification.
    static func snoozePatch(until snoozedUntil: Date) -> JSONValue {
        snoozePatch(until: snoozedUntil, part: .item)
    }

    /// Snooze on one of the item's notifications: the item's own sets `snoozedUntil`; an early
    /// alert or an hourly time sets its own entry in `snoozes`, leaving the others as they are.
    static func snoozePatch(until snoozedUntil: Date, part: ReminderExpansion.Part) -> JSONValue {
        let when = JSONValue.string(ReminderRecord.formatDate(snoozedUntil))
        switch part {
        case .item:
            return .object(["snoozedUntil": when])
        case .alert, .slot:
            return .object(["snoozes": .object([ReminderExpansion.suffix(of: part): when])])
        }
    }

    /// doneThrough only ever moves forward.
    static func laterDoneThrough(current: JSONValue?, occurrence: Date) -> Date {
        guard let currentDate = ReminderRecord.parseDate(current) else {
            return occurrence
        }
        return max(currentDate, occurrence)
    }
}
