import Foundation

/// One reminder in Today: what the Sidekick widget's `when: 'today'` source makes an item of.
struct SharedReminder: Codable, Equatable, Sendable {
    /// The record key without the `reminder:` prefix.
    let id: String
    let title: String
    /// Today's moment for this reminder: its time, today's occurrence of a repeat, or the snooze.
    let at: Date
    /// An all-day reminder shows no time and never turns late during its day.
    let allDay: Bool
    /// "#RRGGBB": the list's colour, or blue with no list.
    let colorHex: String

    /// Whether the reminder's time has passed at `now` (the item is `late`).
    func hasPassed(at now: Date) -> Bool {
        guard !allDay else {
            return false
        }
        return at <= now
    }
}

/// Which reminders of the Reminders Sidekick are in Today, as the Sidekick's own Today list
/// decides (sidekicks/reminders/index.html `placeItem`; midas-intel reminders BRIEF.md): dated
/// today and not done; past due today stays until midnight; undated never. A repeat counts with
/// today's occurrence: the missed one if it fell today and was not dealt with, else the next one
/// if it falls later today. Feeds the Sidekick widget's `when: 'today'` source
/// (SidekickWidgetFiller).
struct TodayReminderPlanner: Sendable {
    /// The circle colour of a reminder with no list: systemBlue, as the Sidekick draws it.
    static let noListColorHex = "#007AFF"

    let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// The reminders in Today at `now`, in widget order.
    func reminders(reminderRecords: [LocalRecord], listRecords: [LocalRecord], now: Date) -> [SharedReminder] {
        let colorsByListId = Self.listColors(listRecords: listRecords)
        var todayReminders: [SharedReminder] = []
        for storedRecord in reminderRecords {
            guard let reminder = todayReminder(storedRecord: storedRecord, colorsByListId: colorsByListId, now: now) else {
                continue
            }
            todayReminders.append(reminder)
        }
        return Self.sorted(todayReminders)
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

    private func todayReminder(storedRecord: LocalRecord, colorsByListId: [String: String], now: Date) -> SharedReminder? {
        guard let record = ReminderRecord.parse(sidekickId: storedRecord.sidekickId, key: storedRecord.key, value: storedRecord.value) else {
            return nil
        }
        guard !record.done else {
            return nil
        }
        let value = storedRecord.value
        guard let moment = todayMoment(of: record, value: value, now: now) else {
            return nil
        }
        let listId = value["list"]?.stringValue
        let colorHex = Self.circleColorHex(listId: listId, colorsByListId: colorsByListId)
        let allDay = value["allDay"]?.boolValue ?? false
        return SharedReminder(id: record.identity.reminderId, title: record.title, at: moment, allDay: allDay, colorHex: colorHex)
    }

    /// The reminder's moment today, or nil when it is not in Today at `now`.
    private func todayMoment(of record: ReminderRecord, value: JSONValue, now: Date) -> Date? {
        guard record.repeatRule != nil else {
            let moment = Self.later(record.at, record.snoozedUntil)
            return calendar.isDate(moment, inSameDayAs: now) ? moment : nil
        }
        let schedule = ReminderSchedule(calendar: calendar)
        let handledThrough = Self.handledThrough(record: record, value: value)
        // The latest occurrence up to now that was not dealt with: past due, or snoozed past it.
        if let missed = schedule.latestOccurrence(of: record, after: handledThrough, notAfter: now) {
            let effectiveMoment = Self.later(missed, record.snoozedUntil)
            if calendar.isDate(effectiveMoment, inSameDayAs: now) {
                return effectiveMoment
            }
        }
        let searchFrom = max(now, handledThrough)
        let nextOccurrences = schedule.occurrences(of: record, after: searchFrom, limit: 1)
        guard let next = nextOccurrences.first, calendar.isDate(next, inSameDayAs: now) else {
            return nil
        }
        return next
    }

    /// Occurrences up to this moment are dealt with: done from a notification or the Sidekick
    /// (`lastDoneAt`, `doneThrough`), or before the reminder existed (`createdAt`). With none of
    /// these, everything from the first occurrence on counts.
    static func handledThrough(record: ReminderRecord, value: JSONValue) -> Date {
        var candidates: [Date] = [record.at.addingTimeInterval(-1)]
        if let lastDoneAt = ReminderRecord.parseDate(value["lastDoneAt"]) {
            candidates.append(lastDoneAt)
        }
        if let doneThrough = ReminderRecord.parseDate(value["doneThrough"]) {
            candidates.append(doneThrough)
        }
        // The Sidekick treats createdAt minus one millisecond as handled.
        if let createdAt = ReminderRecord.parseDate(value["createdAt"]) {
            candidates.append(createdAt.addingTimeInterval(-0.001))
        }
        return candidates.max()!
    }

    static func later(_ moment: Date, _ snoozedUntil: Date?) -> Date {
        guard let snoozedUntil, snoozedUntil > moment else {
            return moment
        }
        return snoozedUntil
    }

    // MARK: Colours

    /// The Sidekick's twelve list colours by name (LIST_COLOURS); a list stores a name or a hex.
    static let listColorHexByName: [String: String] = [
        "red": "#FF3B30", "orange": "#FF9500", "yellow": "#FFCC00", "green": "#34C759",
        "cyan": "#32ADE6", "blue": "#007AFF", "indigo": "#5856D6", "pink": "#FF2D55",
        "purple": "#AF52DE", "brown": "#A2845E", "gray": "#8E8E93", "mint": "#00C7BE",
    ]

    /// What the Sidekick draws for a list colour it cannot read.
    static let unknownListColorHex = "#8E8E93"

    /// The circle colour: the list's colour; with no list, or a list no longer there, blue.
    static func circleColorHex(listId: String?, colorsByListId: [String: String]) -> String {
        guard let listId, let listColorHex = colorsByListId[listId] else {
            return noListColorHex
        }
        return listColorHex
    }

    /// `list:<id>` records to their colour as "#RRGGBB".
    static func listColors(listRecords: [LocalRecord]) -> [String: String] {
        var colorsByListId: [String: String] = [:]
        for listRecord in listRecords {
            guard listRecord.key.hasPrefix("list:") else {
                continue
            }
            let listId = String(listRecord.key.dropFirst("list:".count))
            let storedColor = listRecord.value["color"]?.stringValue
            colorsByListId[listId] = normalizedColorHex(storedColor)
        }
        return colorsByListId
    }

    /// A colour name or "#RGB", "#RRGGBB", "#RRGGBBAA" as "#RRGGBB"; grey for anything else.
    static func normalizedColorHex(_ storedColor: String?) -> String {
        guard let storedColor else {
            return unknownListColorHex
        }
        if let namedHex = listColorHexByName[storedColor.lowercased()] {
            return namedHex
        }
        guard storedColor.hasPrefix("#") else {
            return unknownListColorHex
        }
        let digits = storedColor.dropFirst().uppercased()
        let isHex = !digits.isEmpty && digits.allSatisfy(\.isHexDigit)
        guard isHex else {
            return unknownListColorHex
        }
        switch digits.count {
        case 3:
            // "#ABC" means "#AABBCC".
            var expanded = "#"
            for digit in digits {
                expanded.append(digit)
                expanded.append(digit)
            }
            return expanded
        case 6:
            return "#" + digits
        case 8:
            return "#" + digits.prefix(6)
        default:
            return unknownListColorHex
        }
    }
}
