import Foundation

// Compiled into the app and the widget extension: the Sidekick widget shows a reminder tick at once
// with the same patch the app writes (SidekickWidgetTapPreview).

/// What Done and Snooze change on a reminder record, as patches. The same fields the same way
/// everywhere (founder, 2026-10-15): the Reminders page's `markDoneChange`, the care-reminders
/// page's Done, the notification buttons and the Sidekick widget all produce these.
///
///   Done, one-time:          { done: true, completedAt: now, snoozedUntil: removed, the alerts'
///                              snoozes removed }
///   Done, repeat:            { lastDoneAt: now, doneThrough: the occurrence (never earlier than
///                              before), snoozedUntil: removed, the alerts' snoozes removed }
///   Done on an hourly time:  { slotsDone: { "HH:MM": now, or the occurrence when ticked early },
///                              that time's snooze removed }
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
            // A time ticked before it comes (the widget's next dose at 2:50 for 3:00) counts for
            // that time (founder, 2026-10-31, build 22): its Done is kept at the occurrence, so
            // Today, the widget and the Sidekick read that occurrence as dealt with.
            patch["slotsDone"] = .object([time: .string(ReminderRecord.formatDate(slotDoneMoment(occurrence: occurrence, now: now)))])
            if let snoozesPatch = snoozesRemovalPatch(for: value, removing: [ReminderExpansion.suffix(of: part)]) {
                patch["snoozes"] = snoozesPatch
            }
        }
        return .object(patch)
    }

    /// When an hourly time's Done is recorded: now, or the occurrence it was tapped for when that
    /// is still ahead (an early tick).
    static func slotDoneMoment(occurrence: Date?, now: Date) -> Date {
        guard let occurrence, occurrence > now else {
            return now
        }
        return occurrence
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
    /// Stop on an alarm or its countdown card (founder, 2026-10-24): the pending snooze of the
    /// notification it was for goes, so it does not ring again; nil when there is none.
    static func snoozeRemovalPatch(for value: JSONValue, part: ReminderExpansion.Part) -> JSONValue? {
        switch part {
        case .item:
            guard value["snoozedUntil"] != nil else {
                return nil
            }
            return .object(["snoozedUntil": .null])
        case .alert, .slot:
            guard let snoozesPatch = snoozesRemovalPatch(for: value, removing: [ReminderExpansion.suffix(of: part)]) else {
                return nil
            }
            return .object(["snoozes": snoozesPatch])
        }
    }

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
