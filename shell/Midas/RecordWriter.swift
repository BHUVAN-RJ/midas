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
}

/// What Done and Snooze change on a reminder record, as patches. The same fields the same way
/// everywhere (founder, 2026-10-15): the Reminders page's `markDoneChange`, the care-reminders
/// page's Done, the notification buttons and both widgets all produce these.
///
///   Done, one-time:          { done: true, completedAt: now, snoozedUntil: removed }
///   Done, repeat:            { lastDoneAt: now, doneThrough: the occurrence (never earlier than
///                              before), snoozedUntil: removed }
///   Done on an hourly time:  { slotsDone: { "HH:MM": now }, snoozedUntil: removed }
///   Snooze:                  { snoozedUntil: when }
///
/// Done on an early alert completes the event it is for (founder, 2026-10-12): the same patch
/// as Done on the item, for the occurrence the alert served.
enum ReminderChange {
    static func donePatch(for value: JSONValue, part: ReminderExpansion.Part, occurrence: Date?, now: Date) -> JSONValue {
        var patch: [String: JSONValue] = ["snoozedUntil": .null]
        switch part {
        case .item, .alert:
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
        case .slot(let time):
            patch["slotsDone"] = .object([time: .string(ReminderRecord.formatDate(now))])
        }
        return .object(patch)
    }

    static func snoozePatch(until snoozedUntil: Date) -> JSONValue {
        .object(["snoozedUntil": .string(ReminderRecord.formatDate(snoozedUntil))])
    }

    /// doneThrough only ever moves forward.
    static func laterDoneThrough(current: JSONValue?, occurrence: Date) -> Date {
        guard let currentDate = ReminderRecord.parseDate(current) else {
            return occurrence
        }
        return max(currentDate, occurrence)
    }
}
