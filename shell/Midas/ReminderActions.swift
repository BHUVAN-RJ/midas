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

    /// The record after this action. Done on a one-time reminder completes it; Done on a repeat
    /// completes only this occurrence (recorded as `lastDoneAt`), the repeat carries on. A
    /// snooze sets `snoozedUntil`, which the planner books from the reserved slots.
    func apply(to value: JSONValue, now: Date, calendar: Calendar) -> JSONValue {
        guard case .object(var fields) = value else {
            return value
        }
        let isRepeat = fields["repeat"] != nil && fields["repeat"] != .null
        switch self {
        case .done:
            fields["snoozedUntil"] = .null
            if isRepeat {
                fields["lastDoneAt"] = .string(ReminderRecord.formatDate(now))
            } else {
                fields["done"] = .bool(true)
            }
        case .snoozeTenMinutes:
            let snoozedUntil = now.addingTimeInterval(10 * 60)
            fields["snoozedUntil"] = .string(ReminderRecord.formatDate(snoozedUntil))
        case .snoozeOneHour:
            let snoozedUntil = now.addingTimeInterval(60 * 60)
            fields["snoozedUntil"] = .string(ReminderRecord.formatDate(snoozedUntil))
        case .snoozeUntilTomorrow:
            let snoozedUntil = Self.tomorrowMorning(after: now, calendar: calendar)
            fields["snoozedUntil"] = .string(ReminderRecord.formatDate(snoozedUntil))
        }
        return .object(fields)
    }

    private static func tomorrowMorning(after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        return calendar.date(bySettingHour: tomorrowMorningHour, minute: 0, second: 0, of: tomorrow)!
    }
}
