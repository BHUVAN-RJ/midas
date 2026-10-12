import Foundation

// The Reminders widget's contract and logic (brief docs/briefs/widget-reminders.md, founder
// 2026-10-11: "a standalone widget which will show the three today's reminders"). The app works out
// which reminders are in Today and writes them into the App Group container; the widget only reads
// them. Free of WidgetKit so MidasTests can test it through the app module; the views live in
// shell/MidasWidgets/RemindersWidget.swift.

/// The words the Reminders widget shows. Only these; docs/WRITING.md rules.
enum RemindersWidgetCopy {
    static let displayName = "Reminders"
    static let description = "Today's reminders."
    static let header = "Today"
    static let allDone = "All done"
    static let empty = "Open Midas"
}

enum RemindersWidgetShared {
    /// WidgetKit `kind` of the Reminders widget.
    static let kind = "com.bhuvanrj.midas.reminders"

    /// The Sidekick whose reminders the widget shows, and which a tap opens.
    static let sidekickId = "reminders"

    /// The circle colour of a reminder with no list: systemBlue, as the Sidekick draws it.
    static let noListColorHex = "#007AFF"

    /// How many rows the widget draws, in both sizes.
    static let shownLimit = 3

    /// Where the shared Today list lives; nil when the App Group is not available.
    static func fileURL(fileManager: FileManager = .default) -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupIdentifier) else {
            return nil
        }
        return container.appending(path: "widget-reminders-today.json")
    }
}

/// One reminder in Today, as the widget draws it.
struct SharedReminder: Codable, Equatable, Sendable {
    /// The record key without the `reminder:` prefix.
    let id: String
    let title: String
    /// Today's moment for this reminder: its time, today's occurrence of a repeat, or the snooze.
    let at: Date
    /// An all-day reminder shows no time and never turns red during its day.
    let allDay: Bool
    /// "#RRGGBB": the list's colour, or blue with no list.
    let colorHex: String

    /// Whether the reminder's time has passed at `now` (the widget draws the time in red).
    func hasPassed(at now: Date) -> Bool {
        guard !allDay else {
            return false
        }
        return at <= now
    }
}

/// The reminders in Today on one day, in widget order.
struct SharedRemindersDay: Codable, Equatable, Sendable {
    /// Midnight starting the day, in the phone's time zone.
    let dayStart: Date
    let reminders: [SharedReminder]
}

/// The file the app writes: today's Today and tomorrow's, so the widget rolls over at midnight
/// without the app running.
struct SharedTodayReminders: Codable, Equatable, Sendable {
    /// Bumped when the file's shape changes; a reader ignores a version it does not know.
    static let currentFormatVersion = 1

    let formatVersion: Int
    let savedAt: Date
    let days: [SharedRemindersDay]

    init(days: [SharedRemindersDay], savedAt: Date) {
        self.formatVersion = Self.currentFormatVersion
        self.savedAt = savedAt
        self.days = days
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Nil for unreadable data or an unknown format version.
    static func decoded(from data: Data) -> SharedTodayReminders? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(SharedTodayReminders.self, from: data) else {
            return nil
        }
        guard file.formatVersion == currentFormatVersion else {
            return nil
        }
        return file
    }

    /// Today's reminders on the day holding `date`; nil when the file does not cover that day
    /// (the app has not run since).
    func reminders(on date: Date, calendar: Calendar) -> [SharedReminder]? {
        for day in days where calendar.isDate(day.dayStart, inSameDayAs: date) {
            return day.reminders
        }
        return nil
    }
}

/// One drawn row: the reminder and whether its time has passed at the entry's date.
struct RemindersWidgetRow: Equatable, Sendable {
    let reminder: SharedReminder
    let hasPassed: Bool
}

/// What the widget draws at one moment.
enum RemindersWidgetContent: Equatable, Sendable {
    /// No file (signed out, no Reminders Sidekick) or a file older than today: "Open Midas".
    case empty
    /// Nothing left in Today: "All done", count 0.
    case allDone
    /// The count of everything in Today and the first rows by time.
    case reminders(count: Int, rows: [RemindersWidgetRow])
}

enum RemindersWidgetLayout {
    /// The content at `now`.
    static func content(file: SharedTodayReminders?, now: Date, calendar: Calendar) -> RemindersWidgetContent {
        guard let file, let todayReminders = file.reminders(on: now, calendar: calendar) else {
            return .empty
        }
        guard !todayReminders.isEmpty else {
            return .allDone
        }
        let sortedReminders = sorted(todayReminders)
        let shownReminders = sortedReminders.prefix(RemindersWidgetShared.shownLimit)
        var rows: [RemindersWidgetRow] = []
        for reminder in shownReminders {
            let row = RemindersWidgetRow(reminder: reminder, hasPassed: reminder.hasPassed(at: now))
            rows.append(row)
        }
        return .reminders(count: todayReminders.count, rows: rows)
    }

    /// Widget order, as the Sidekick's Today: all-day first, then by time, then by id.
    static func sorted(_ reminders: [SharedReminder]) -> [SharedReminder] {
        return reminders.sorted(by: isShownBefore)
    }

    static func isShownBefore(_ first: SharedReminder, _ second: SharedReminder) -> Bool {
        if first.allDay != second.allDay {
            return first.allDay
        }
        if first.at != second.at {
            return first.at < second.at
        }
        return first.id < second.id
    }

    /// When the widget redraws: now, each timed reminder's moment later today (its row turns red),
    /// and the next midnight (Today rolls over). Nothing else.
    static func timelineDates(file: SharedTodayReminders?, now: Date, calendar: Calendar) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        var reminderDates: Set<Date> = []
        let todayReminders = file?.reminders(on: now, calendar: calendar) ?? []
        for reminder in todayReminders where !reminder.allDay {
            let isLaterToday = reminder.at > now && reminder.at < nextMidnight
            if isLaterToday {
                reminderDates.insert(reminder.at)
            }
        }
        var dates = [now]
        dates.append(contentsOf: reminderDates.sorted())
        dates.append(nextMidnight)
        return dates
    }

    /// 12-hour time, "6:00 PM", in the calendar's time zone; empty for an all-day reminder.
    static func timeText(for reminder: SharedReminder, calendar: Calendar) -> String {
        guard !reminder.allDay else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: reminder.at)
    }
}

/// Reads the shared Today list the app writes into the App Group container.
enum SharedTodayRemindersReader {
    /// Nil when there is no file, it cannot be read, or its format is unknown.
    static func read(from fileURL: URL?) -> SharedTodayReminders? {
        guard let fileURL else {
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return SharedTodayReminders.decoded(from: data)
    }
}
