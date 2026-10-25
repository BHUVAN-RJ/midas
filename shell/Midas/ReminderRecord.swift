import Foundation

/// Which Sidekick owns a reminder, and its id (the record key without the `reminder:` prefix).
struct ReminderIdentity: Hashable, Codable, Sendable, Comparable {
    let sidekickId: String
    let reminderId: String

    var ledgerKey: String {
        "\(sidekickId)/\(reminderId)"
    }

    static func < (first: ReminderIdentity, second: ReminderIdentity) -> Bool {
        if first.sidekickId != second.sidekickId {
            return first.sidekickId < second.sidekickId
        }
        return first.reminderId < second.reminderId
    }
}

enum RepeatFrequency: String, Codable, Sendable {
    case day
    case week
    case month
    case year
}

/// How a reminder repeats. Weekdays use the JavaScript numbering a Sidekick has from
/// `Date.getDay()`: 0 is Sunday, 6 is Saturday. They apply to weekly repeats only.
struct RepeatRule: Equatable, Sendable {
    let frequency: RepeatFrequency
    let interval: Int
    let weekdays: [Int]
    let until: Date?
}

/// A `reminder:<id>` record (`reminders.item`, `care.item`; docs/NOTIFICATIONS.md 4.2), the
/// fields the engine reads:
///
///     { $type, title, notes?, at?, repeat?: { every, interval?, weekdays?, until? }, timeZone?,
///       done?, snoozedUntil?, snoozes?, lastDoneAt?, doneThrough?, alerts?, everyHours?,
///       slotsDone? }
///
/// `notes` is the notification text, under the title, on every notification the item makes
/// (founder, 2026-10-20). `at` is an ISO 8601 string with an offset (as `Date.toISOString()`
/// gives). A one-time reminder fires at that exact moment. A repeat keeps the wall-clock time
/// `at` has in `timeZone` (an IANA name; the phone's zone if absent) wherever the phone is.
/// `snoozedUntil`,
/// `snoozes`, `lastDoneAt`, `doneThrough` and `slotsDone` are written by the Done and Snooze
/// writers (`ReminderChange`).
struct ReminderRecord: Equatable, Sendable {
    static let keyPrefix = "reminder:"

    let identity: ReminderIdentity
    let at: Date
    let title: String
    /// The item's notes: the notification text ("" for none).
    let notes: String
    let repeatRule: RepeatRule?
    let timeZone: TimeZone?
    let done: Bool
    let snoozedUntil: Date?
    // Fields the Done writers and the care-reminders expansion read (unified data, 2026-10-15).
    /// When Done was last tapped on a repeat.
    var lastDoneAt: Date? = nil
    /// The occurrence through which a repeat is done.
    var doneThrough: Date? = nil
    /// Early alerts, expanded by the engine into reminders of their own (`ReminderExpansion`).
    var alerts: [EarlyAlertRule] = []
    /// Every 2, 3 or 4 hours around the clock from `at`; the extra times are expanded too.
    var everyHours: Int? = nil
    /// "HH:MM": with `everyHours`, the last time of the day (hydration plan N1); nil for around
    /// the clock.
    var endTime: String? = nil
    /// Done tapped on an hourly time's notification: "HH:MM" to when.
    var slotsDone: [String: Date] = [:]
    /// Snooze tapped on an early alert's or an hourly time's notification: the notification's
    /// own suffix (`~rule` or `@HHMM`) to when it comes back. Each one is independent of the
    /// others and of the item's own `snoozedUntil` (founder, 2026-10-15).
    var snoozes: [String: Date] = [:]

    /// Parses a stored record into a reminder the engine can book. Returns nil for anything
    /// `validationError` would reject, and for an item without `at` (an undated reminder, kept
    /// under `reminder:` since 2026-10-15; it notifies nobody).
    static func parse(sidekickId: String, key: String, value: JSONValue) -> ReminderRecord? {
        guard key.hasPrefix(keyPrefix), validationError(value) == nil, let at = parseDate(value["at"]) else {
            return nil
        }
        let reminderId = String(key.dropFirst(keyPrefix.count))
        let identity = ReminderIdentity(sidekickId: sidekickId, reminderId: reminderId)
        // validationError already proved these fields are present and well formed.
        let title = value["title"]!.stringValue!
        let notes = parseNotes(value)
        let repeatRule = value["repeat"].flatMap(parseRepeatRule)
        let timeZone = value["timeZone"]?.stringValue.flatMap(TimeZone.init(identifier:))
        let done = value["done"]?.boolValue ?? false
        let snoozedUntil = parseDate(value["snoozedUntil"])
        var record = ReminderRecord(identity: identity, at: at, title: title, notes: notes, repeatRule: repeatRule,
                                    timeZone: timeZone, done: done, snoozedUntil: snoozedUntil)
        record.lastDoneAt = parseDate(value["lastDoneAt"])
        record.doneThrough = parseDate(value["doneThrough"])
        record.alerts = parseAlerts(value["alerts"])
        record.everyHours = parseEveryHours(value["everyHours"])
        record.endTime = value["endTime"]?.stringValue
        record.slotsDone = parseSlotsDone(value["slotsDone"])
        record.snoozes = parseDateMap(value["snoozes"])
        return record
    }

    /// The item's notes, "" for none.
    private static func parseNotes(_ value: JSONValue) -> String {
        value["notes"]?.stringValue ?? ""
    }

    private static func parseAlerts(_ value: JSONValue?) -> [EarlyAlertRule] {
        guard let rules = value?.arrayValue else {
            return []
        }
        var parsedRules: [EarlyAlertRule] = []
        for ruleValue in rules {
            if let rule = EarlyAlertRule.parse(ruleValue) {
                parsedRules.append(rule)
            }
        }
        return parsedRules
    }

    private static func parseEveryHours(_ value: JSONValue?) -> Int? {
        guard let hours = value?.numberValue, hours == hours.rounded() else {
            return nil
        }
        return Int(hours)
    }

    private static func parseSlotsDone(_ value: JSONValue?) -> [String: Date] {
        parseDateMap(value)
    }

    /// An object whose values are dates (`slotsDone`, `snoozes`); entries that are not dates are left out.
    private static func parseDateMap(_ value: JSONValue?) -> [String: Date] {
        guard case .object(let fields)? = value else {
            return [:]
        }
        var dates: [String: Date] = [:]
        for (name, dateValue) in fields {
            if let date = parseDate(dateValue) {
                dates[name] = date
            }
        }
        return dates
    }

    /// Why a value cannot be stored under `reminder:`, or nil if it can. The store channel
    /// rejects bad writes with this message so the Sidekick learns at write time. `at` may be
    /// absent (an undated item, unified data 2026-10-15); when present it must be a date.
    @Sendable
    static func validationError(_ value: JSONValue) -> String? {
        guard case .object = value else {
            return "reminder must be an object"
        }
        if let at = value["at"], parseDate(at) == nil {
            return "reminder.at must be an ISO 8601 date"
        }
        guard let title = value["title"]?.stringValue, !title.isEmpty else {
            return "reminder.title must be a non-empty string"
        }
        if let notes = value["notes"], notes.stringValue == nil, notes != .null {
            return "reminder.notes must be a string"
        }
        if let done = value["done"], done.boolValue == nil, done != .null {
            return "reminder.done must be true or false"
        }
        if let timeZoneName = value["timeZone"]?.stringValue, TimeZone(identifier: timeZoneName) == nil {
            return "reminder.timeZone is not a known time zone"
        }
        if let snoozedUntil = value["snoozedUntil"], snoozedUntil != .null, parseDate(snoozedUntil) == nil {
            return "reminder.snoozedUntil must be a date"
        }
        if let snoozes = value["snoozes"], snoozes != .null {
            guard case .object(let snoozeFields) = snoozes else {
                return "reminder.snoozes must be an object"
            }
            for (name, snoozeValue) in snoozeFields where parseDate(snoozeValue) == nil {
                return "reminder.snoozes.\(name) must be a date"
            }
        }
        if let endTime = value["endTime"], endTime != .null, !isWallTime(endTime) {
            return "reminder.endTime must be a time like 21:00"
        }
        if let repeatValue = value["repeat"], repeatValue != .null {
            return repeatValidationError(repeatValue)
        }
        return nil
    }

    /// "HH:MM", 00:00 to 23:59.
    static func isWallTime(_ value: JSONValue) -> Bool {
        guard let text = value.stringValue, text.count == 5 else {
            return false
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    private static func repeatValidationError(_ repeatValue: JSONValue) -> String? {
        guard let frequencyName = repeatValue["every"]?.stringValue, let frequency = RepeatFrequency(rawValue: frequencyName) else {
            return "reminder.repeat.every must be day, week, month or year"
        }
        if let intervalValue = repeatValue["interval"] {
            guard let interval = intervalValue.numberValue, interval == interval.rounded(), interval >= 1, interval <= 999 else {
                return "reminder.repeat.interval must be a whole number from 1 to 999"
            }
        }
        if let weekdaysValue = repeatValue["weekdays"] {
            guard frequency == .week else {
                return "reminder.repeat.weekdays applies to weekly repeats only"
            }
            guard let weekdays = weekdaysValue.arrayValue, !weekdays.isEmpty else {
                return "reminder.repeat.weekdays must be a non-empty list"
            }
            for weekday in weekdays {
                guard let number = weekday.numberValue, number == number.rounded(), number >= 0, number <= 6 else {
                    return "reminder.repeat.weekdays holds numbers 0 (Sunday) to 6 (Saturday)"
                }
            }
        }
        if let untilValue = repeatValue["until"], untilValue != .null, parseDate(untilValue) == nil {
            return "reminder.repeat.until must be a date"
        }
        return nil
    }

    private static func parseRepeatRule(_ repeatValue: JSONValue) -> RepeatRule? {
        guard let frequencyName = repeatValue["every"]?.stringValue, let frequency = RepeatFrequency(rawValue: frequencyName) else {
            return nil
        }
        let interval = Int(repeatValue["interval"]?.numberValue ?? 1)
        var weekdays: [Int] = []
        for weekday in repeatValue["weekdays"]?.arrayValue ?? [] {
            if let number = weekday.numberValue {
                weekdays.append(Int(number))
            }
        }
        let uniqueSortedWeekdays = Array(Set(weekdays)).sorted()
        let until = parseDate(repeatValue["until"])
        return RepeatRule(frequency: frequency, interval: interval, weekdays: uniqueSortedWeekdays, until: until)
    }

    /// An ISO 8601 date with an offset; anything else (including a number) is not a date.
    static func parseDate(_ value: JSONValue?) -> Date? {
        guard let text = value?.stringValue else {
            return nil
        }
        let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let fractionalDate = try? fractionalStyle.parse(text) {
            return fractionalDate
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    /// The form the shell writes dates in, matching JavaScript's `Date.toISOString()`. The
    /// milliseconds are rounded and written by hand: Foundation's fractional formatting floors, so
    /// a parsed ".520" (not exactly 0.52 in binary) came back as ".519".
    static func formatDate(_ date: Date) -> String {
        let totalMilliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let wholeSeconds = (totalMilliseconds / 1000).rounded(.down)
        let milliseconds = Int(totalMilliseconds - wholeSeconds * 1000)
        let secondsText = Date.ISO8601FormatStyle().format(Date(timeIntervalSince1970: wholeSeconds))
        let withoutZone = secondsText.hasSuffix("Z") ? String(secondsText.dropLast()) : secondsText
        return withoutZone + String(format: ".%03dZ", milliseconds)
    }
}
