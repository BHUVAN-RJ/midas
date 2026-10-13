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
        return appGroupFileURL(named: "widget-reminders-today.json", fileManager: fileManager)
    }

    /// Ticks made in the widget that the app has not yet written to the records (only used when
    /// the tick could not run in the app's process).
    static func pendingTicksFileURL(fileManager: FileManager = .default) -> URL? {
        return appGroupFileURL(named: "widget-reminders-ticks.json", fileManager: fileManager)
    }

    /// The page each widget size shows when today has more than fits.
    static func pagesFileURL(fileManager: FileManager = .default) -> URL? {
        return appGroupFileURL(named: "widget-reminders-pages.json", fileManager: fileManager)
    }

    private static func appGroupFileURL(named fileName: String, fileManager: FileManager) -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupIdentifier) else {
            return nil
        }
        return container.appending(path: fileName)
    }
}

/// The three sizes, each with how many rows one page shows (brief step 5: large up to 8).
enum RemindersWidgetFamily: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    var rowLimit: Int {
        switch self {
        case .small, .medium:
            return RemindersWidgetShared.shownLimit
        case .large:
            return 8
        }
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

    /// Whether a tick made in the widget is for this reminder's occurrence today.
    func isCoveredBy(_ tick: PendingReminderTick) -> Bool {
        return tick.reminderId == id && tick.occurrence >= at
    }

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

/// What one widget size draws at one moment: the content and where the page is.
struct RemindersWidgetScreen: Equatable, Sendable {
    let content: RemindersWidgetContent
    /// The page shown, from 0, clamped to the pages there are.
    let pageIndex: Int
    let pageCount: Int

    /// Arrows show only when today has more than one page.
    var showsPageArrows: Bool {
        return pageCount > 1
    }

    var canPageUp: Bool {
        return pageIndex > 0
    }

    var canPageDown: Bool {
        return pageIndex < pageCount - 1
    }
}

enum RemindersWidgetLayout {
    /// The content at `now`: the first three, as the small and medium sizes draw on page 1.
    static func content(file: SharedTodayReminders?, now: Date, calendar: Calendar) -> RemindersWidgetContent {
        let firstPage = screen(file: file, now: now, calendar: calendar, family: .small, requestedPage: 0, pendingTicks: [])
        return firstPage.content
    }

    /// What a size draws at `now` on the requested page. Reminders ticked in the widget but not yet
    /// in the file are left out, so a ticked row leaves at once.
    static func screen(file: SharedTodayReminders?, now: Date, calendar: Calendar, family: RemindersWidgetFamily,
                       requestedPage: Int, pendingTicks: [PendingReminderTick]) -> RemindersWidgetScreen {
        guard let file, let todayReminders = file.reminders(on: now, calendar: calendar) else {
            return RemindersWidgetScreen(content: .empty, pageIndex: 0, pageCount: 1)
        }
        let openReminders = withoutTicked(todayReminders, pendingTicks: pendingTicks)
        guard !openReminders.isEmpty else {
            return RemindersWidgetScreen(content: .allDone, pageIndex: 0, pageCount: 1)
        }
        let sortedReminders = sorted(openReminders)
        let rowLimit = family.rowLimit
        let pageCount = (sortedReminders.count + rowLimit - 1) / rowLimit
        let pageIndex = min(max(requestedPage, 0), pageCount - 1)
        let pageStart = pageIndex * rowLimit
        let pageEnd = min(pageStart + rowLimit, sortedReminders.count)
        var rows: [RemindersWidgetRow] = []
        for reminder in sortedReminders[pageStart..<pageEnd] {
            let row = RemindersWidgetRow(reminder: reminder, hasPassed: reminder.hasPassed(at: now))
            rows.append(row)
        }
        let content = RemindersWidgetContent.reminders(count: sortedReminders.count, rows: rows)
        return RemindersWidgetScreen(content: content, pageIndex: pageIndex, pageCount: pageCount)
    }

    /// Drops reminders with a pending tick for this occurrence (or a later one).
    static func withoutTicked(_ reminders: [SharedReminder], pendingTicks: [PendingReminderTick]) -> [SharedReminder] {
        var openReminders: [SharedReminder] = []
        for reminder in reminders {
            let isTicked = pendingTicks.contains(where: reminder.isCoveredBy)
            if !isTicked {
                openReminders.append(reminder)
            }
        }
        return openReminders
    }

    /// Widget order: reminders with a time first, earliest first, then untimed ones, then by id
    /// (founder, 2026-10-11; docs/PRODUCT.md, the Reminders widget).
    static func sorted(_ reminders: [SharedReminder]) -> [SharedReminder] {
        return reminders.sorted(by: isShownBefore)
    }

    static func isShownBefore(_ first: SharedReminder, _ second: SharedReminder) -> Bool {
        if first.allDay != second.allDay {
            return !first.allDay
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

// MARK: Ticks and pages, written by the widget's intents

/// A reminder ticked done in the widget: which one, and the occurrence the row showed.
struct PendingReminderTick: Codable, Equatable, Sendable {
    let reminderId: String
    let occurrence: Date
    let tickedAt: Date
}

/// Ticks waiting for the app, in an App Group file. Used only when the tick intent could not run
/// in the app's process; the app applies them at its next launch or return to the front.
enum PendingReminderTicksFile {
    private struct Contents: Codable {
        let formatVersion: Int
        let ticks: [PendingReminderTick]
    }

    private static let formatVersion = 1

    static func read(from fileURL: URL?) -> [PendingReminderTick] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(Contents.self, from: data), contents.formatVersion == formatVersion else {
            return []
        }
        return contents.ticks
    }

    static func append(_ tick: PendingReminderTick, to fileURL: URL?) {
        guard let fileURL else {
            return
        }
        var ticks = read(from: fileURL)
        ticks.append(tick)
        write(ticks, to: fileURL)
    }

    static func write(_ ticks: [PendingReminderTick], to fileURL: URL?) {
        guard let fileURL else {
            return
        }
        guard !ticks.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let contents = Contents(formatVersion: formatVersion, ticks: ticks)
        guard let data = try? encoder.encode(contents) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

/// The page each widget size shows, in an App Group file the arrow intents change. One page per
/// size: two widgets of the same size page together.
enum RemindersWidgetPagesFile {
    static func page(for family: RemindersWidgetFamily, in fileURL: URL?) -> Int {
        let pages = read(from: fileURL)
        return pages[family.rawValue] ?? 0
    }

    /// Moves a size's page by `step`, never below 0 (the layout clamps the top end).
    static func movePage(for family: RemindersWidgetFamily, by step: Int, pageCount: Int, in fileURL: URL?) {
        guard let fileURL else {
            return
        }
        var pages = read(from: fileURL)
        let currentPage = pages[family.rawValue] ?? 0
        let lastPage = max(pageCount - 1, 0)
        let clampedCurrent = min(currentPage, lastPage)
        pages[family.rawValue] = min(max(clampedCurrent + step, 0), lastPage)
        guard let data = try? JSONEncoder().encode(pages) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static func read(from fileURL: URL?) -> [String: Int] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }
}
