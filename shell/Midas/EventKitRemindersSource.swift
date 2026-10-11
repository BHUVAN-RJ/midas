import EventKit
import Foundation
import UIKit

/// Reads Apple Reminders on the phone with EventKit. Every EventKit object is turned into plain
/// values (PhoneReminder) as soon as it is read, so nothing from EventKit leaves this file.
@MainActor
final class EventKitRemindersSource: PhoneRemindersSource {
    private let eventStore = EKEventStore()

    func requestAccess() async -> Bool {
        let granted = try? await eventStore.requestFullAccessToReminders()
        return granted ?? false
    }

    func readAll() async throws -> (lists: [PhoneReminderList], reminders: [PhoneReminder]) {
        var lists: [PhoneReminderList] = []
        for calendar in eventStore.calendars(for: .reminder) {
            lists.append(EventKitReminderConversion.list(from: calendar))
        }
        // nil calendars = every reminders list; completed reminders included
        let predicate = eventStore.predicateForReminders(in: nil)
        let reminders = try await Self.fetchReminders(eventStore: eventStore, predicate: predicate)
        return (lists, reminders)
    }

    private static func fetchReminders(eventStore: EKEventStore, predicate: NSPredicate) async throws -> [PhoneReminder] {
        return try await withCheckedThrowingContinuation { continuation in
            let completion = makeFetchCompletion(continuation: continuation)
            eventStore.fetchReminders(matching: predicate, completion: completion)
        }
    }

    // Built outside the main actor: EventKit calls it on its own queue
    nonisolated private static func makeFetchCompletion(continuation: CheckedContinuation<[PhoneReminder], Error>) -> @Sendable ([EKReminder]?) -> Void {
        return { fetchedReminders in
            guard let fetchedReminders else {
                continuation.resume(throwing: PhoneRemindersError.readFailed)
                return
            }
            // Converted here, on EventKit's queue: EKReminder is not Sendable
            var converted: [PhoneReminder] = []
            for reminder in fetchedReminders {
                converted.append(EventKitReminderConversion.reminder(from: reminder))
            }
            continuation.resume(returning: converted)
        }
    }
}

/// EventKit objects to plain values, matching the Mac export field by field.
enum EventKitReminderConversion {
    private static let frequencyNames: [EKRecurrenceFrequency: String] = [
        .daily: "daily", .weekly: "weekly", .monthly: "monthly", .yearly: "yearly",
    ]

    static func list(from calendar: EKCalendar) -> PhoneReminderList {
        return PhoneReminderList(id: calendar.calendarIdentifier, title: calendar.title, colorHex: hexString(from: calendar.cgColor))
    }

    static func reminder(from reminder: EKReminder) -> PhoneReminder {
        let formatter = ISO8601DateFormatter.deviceZone
        var alarms: [PhoneReminderAlarm] = []
        for alarm in reminder.alarms ?? [] {
            if let convertedAlarm = self.alarm(from: alarm, formatter: formatter) {
                alarms.append(convertedAlarm)
            }
        }
        var rules: [PhoneRecurrenceRule] = []
        for rule in reminder.recurrenceRules ?? [] {
            rules.append(recurrenceRule(from: rule, formatter: formatter))
        }
        let identifier = reminder.calendarItemIdentifier
        let externalIdentifier = reminder.calendarItemExternalIdentifier ?? identifier
        return PhoneReminder(
            id: identifier,
            externalId: externalIdentifier,
            listId: reminder.calendar?.calendarIdentifier ?? "",
            title: reminder.title ?? "",
            notes: reminder.notes,
            url: reminder.url?.absoluteString,
            completed: reminder.isCompleted,
            completionDate: isoText(reminder.completionDate, formatter: formatter),
            creationDate: isoText(reminder.creationDate, formatter: formatter),
            lastModifiedDate: isoText(reminder.lastModifiedDate, formatter: formatter),
            priority: reminder.priority,
            due: dueFromOptional(reminder.dueDateComponents),
            alarms: alarms,
            recurrence: rules
        )
    }

    /// Due date components to the export's `due`: a date without an hour is all day.
    static func due(from components: DateComponents) -> PhoneReminderDue? {
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        let dateText = String(format: "%04d-%02d-%02d", year, month, day)
        guard let hour = components.hour else {
            return PhoneReminderDue(allDay: true, date: dateText, time: nil, timeZone: nil, instant: nil)
        }
        let minute = components.minute ?? 0
        let timeText = String(format: "%02d:%02d", hour, minute)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? .current
        var wallClock = DateComponents()
        wallClock.year = year
        wallClock.month = month
        wallClock.day = day
        wallClock.hour = hour
        wallClock.minute = minute
        let instantText = isoText(calendar.date(from: wallClock), formatter: ISO8601DateFormatter.deviceZone)
        return PhoneReminderDue(allDay: false, date: dateText, time: timeText, timeZone: components.timeZone?.identifier, instant: instantText)
    }

    /// Location alarms have no time and are left out.
    static func alarm(from alarm: EKAlarm, formatter: ISO8601DateFormatter) -> PhoneReminderAlarm? {
        if let absoluteDate = alarm.absoluteDate {
            return PhoneReminderAlarm(absoluteDate: formatter.string(from: absoluteDate), relativeOffsetSeconds: nil)
        }
        if alarm.structuredLocation != nil {
            return nil
        }
        return PhoneReminderAlarm(absoluteDate: nil, relativeOffsetSeconds: alarm.relativeOffset)
    }

    static func recurrenceRule(from rule: EKRecurrenceRule, formatter: ISO8601DateFormatter) -> PhoneRecurrenceRule {
        var days: [PhoneRecurrenceDay]?
        if let daysOfTheWeek = rule.daysOfTheWeek {
            var convertedDays: [PhoneRecurrenceDay] = []
            for dayOfWeek in daysOfTheWeek {
                convertedDays.append(PhoneRecurrenceDay(weekday: dayOfWeek.dayOfTheWeek.rawValue, weekNumber: dayOfWeek.weekNumber))
            }
            days = convertedDays
        }
        let end = rule.recurrenceEnd
        var endOccurrenceCount: Int?
        if let end, end.occurrenceCount > 0 {
            endOccurrenceCount = end.occurrenceCount
        }
        return PhoneRecurrenceRule(
            frequency: frequencyNames[rule.frequency] ?? "unknown",
            interval: rule.interval,
            daysOfWeek: days,
            daysOfMonth: integers(rule.daysOfTheMonth),
            monthsOfYear: integers(rule.monthsOfTheYear),
            weeksOfYear: integers(rule.weeksOfTheYear),
            daysOfYear: integers(rule.daysOfTheYear),
            setPositions: integers(rule.setPositions),
            endDate: isoText(end?.endDate, formatter: formatter),
            endOccurrenceCount: endOccurrenceCount
        )
    }

    static func hexString(from color: CGColor?) -> String? {
        guard let color else {
            return nil
        }
        let uiColor = UIColor(cgColor: color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        let redByte = Int((min(max(red, 0), 1) * 255).rounded())
        let greenByte = Int((min(max(green, 0), 1) * 255).rounded())
        let blueByte = Int((min(max(blue, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
    }

    static func isoText(_ date: Date?, formatter: ISO8601DateFormatter) -> String? {
        guard let date else {
            return nil
        }
        return formatter.string(from: date)
    }

    private static func dueFromOptional(_ components: DateComponents?) -> PhoneReminderDue? {
        guard let components else {
            return nil
        }
        return due(from: components)
    }

    private static func integers(_ numbers: [NSNumber]?) -> [Int]? {
        guard let numbers else {
            return nil
        }
        var values: [Int] = []
        for number in numbers {
            values.append(number.intValue)
        }
        return values
    }
}
