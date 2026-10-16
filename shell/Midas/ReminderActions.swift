import Foundation

/// The buttons on a Midas reminder notification, and how each one changes the reminder record.
/// The shell writes the change into the Sidekick's record, so the Sidekick sees it next time it
/// reads, then the engine re-plans.
enum ReminderAction: String, CaseIterable, Sendable {
    case done = "midas.reminder.done"
    case snoozeTenMinutes = "midas.reminder.snooze.10m"
    case snoozeOneHour = "midas.reminder.snooze.1h"
    case snoozeUntilTomorrow = "midas.reminder.snooze.tomorrow"

    static let categoryIdentifier = "midas.reminder"
    // "Tomorrow" means 9:00 the next morning, phone time.
    static let tomorrowMorningHour = 9

    var buttonTitle: String {
        switch self {
        case .done:
            return "Done"
        case .snoozeTenMinutes:
            return "Snooze 10 Minutes"
        case .snoozeOneHour:
            return "Snooze 1 Hour"
        case .snoozeUntilTomorrow:
            return "Snooze Until Tomorrow"
        }
    }

    /// The record after this action on the reminder's own notification. Done on a one-time
    /// reminder completes it; Done on a repeat completes only this occurrence (recorded as
    /// `lastDoneAt`), the repeat carries on. A snooze sets `snoozedUntil`, which the planner
    /// books from the reserved slots.
    func apply(to value: JSONValue, now: Date, calendar: Calendar) -> JSONValue {
        apply(to: value, part: .item, occurrence: nil, now: now, calendar: calendar)
    }

    /// The item record after this action on one of its notifications: its own, an early alert
    /// or an hourly time (ReminderExpansion). The change is the `ReminderChange` patch, the same
    /// one the pages and the widgets make, merged into the record.
    func apply(to value: JSONValue, part: ReminderExpansion.Part, occurrence: Date?, now: Date, calendar: Calendar) -> JSONValue {
        guard case .object = value else {
            return value
        }
        let changePatch = patch(for: value, part: part, occurrence: occurrence, now: now, calendar: calendar)
        return JSONMergePatch.apply(changePatch, to: value)
    }

    /// What this action changes on the item record, as a patch for `RecordWriter.update`. Done on
    /// an early alert completes the whole event (founder, 2026-10-12): the one-time item, or the
    /// repeat's occurrence the alert served. Done on an hourly time marks that time done today
    /// (`slotsDone`). A snooze on any of them snoozes the item.
    func patch(for value: JSONValue, part: ReminderExpansion.Part, occurrence: Date?, now: Date, calendar: Calendar) -> JSONValue {
        switch self {
        case .done:
            return ReminderChange.donePatch(for: value, part: part, occurrence: occurrence, now: now)
        case .snoozeTenMinutes:
            return ReminderChange.snoozePatch(until: now.addingTimeInterval(10 * 60))
        case .snoozeOneHour:
            return ReminderChange.snoozePatch(until: now.addingTimeInterval(60 * 60))
        case .snoozeUntilTomorrow:
            return ReminderChange.snoozePatch(until: Self.tomorrowMorning(after: now, calendar: calendar))
        }
    }

    private static func tomorrowMorning(after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        return calendar.date(bySettingHour: tomorrowMorningHour, minute: 0, second: 0, of: tomorrow)!
    }
}
