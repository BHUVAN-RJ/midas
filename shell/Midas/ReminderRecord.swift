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

/// A `reminder:<id>` record as a Sidekick writes it:
///
///     { at, title, body?, repeat?: { every, interval?, weekdays?, until? }, timeZone?, done?,
///       snoozedUntil?, lastDoneAt? }
///
/// `at` is an ISO 8601 string (as `Date.toISOString()` gives) or epoch milliseconds. A one-time
/// reminder fires at that exact moment. A repeat keeps the wall-clock time `at` has in
/// `timeZone` (an IANA name; the phone's zone if absent) wherever the phone is. `snoozedUntil`
/// and `lastDoneAt` are written by the shell when the user acts on a notification.
struct ReminderRecord: Equatable, Sendable {
    static let keyPrefix = "reminder:"

    let identity: ReminderIdentity
    let at: Date
    let title: String
    let body: String
    let repeatRule: RepeatRule?
    let timeZone: TimeZone?
    let done: Bool
    let snoozedUntil: Date?

    /// Parses a stored record. Returns nil for anything `validationError` would reject.
    static func parse(sidekickId: String, key: String, value: JSONValue) -> ReminderRecord? {
        guard key.hasPrefix(keyPrefix), validationError(value) == nil else {
            return nil
        }
        let reminderId = String(key.dropFirst(keyPrefix.count))
        let identity = ReminderIdentity(sidekickId: sidekickId, reminderId: reminderId)
        // validationError already proved these fields are present and well formed.
        let at = parseDate(value["at"])!
        let title = value["title"]!.stringValue!
        let body = value["body"]?.stringValue ?? ""
        let repeatRule = value["repeat"].flatMap(parseRepeatRule)
        let timeZone = value["timeZone"]?.stringValue.flatMap(TimeZone.init(identifier:))
        let done = value["done"]?.boolValue ?? false
        let snoozedUntil = parseDate(value["snoozedUntil"])
        return ReminderRecord(identity: identity, at: at, title: title, body: body, repeatRule: repeatRule,
                              timeZone: timeZone, done: done, snoozedUntil: snoozedUntil)
    }

    /// Why a value cannot be stored under `reminder:`, or nil if it can. The store channel
    /// rejects bad writes with this message so the Sidekick learns at write time.
    @Sendable
    static func validationError(_ value: JSONValue) -> String? {
        guard case .object = value else {
            return "reminder must be an object"
        }
        guard parseDate(value["at"]) != nil else {
            return "reminder.at must be an ISO 8601 date or epoch milliseconds"
        }
        guard let title = value["title"]?.stringValue, !title.isEmpty else {
            return "reminder.title must be a non-empty string"
        }
        if let body = value["body"], body.stringValue == nil, body != .null {
            return "reminder.body must be a string"
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
        if let repeatValue = value["repeat"], repeatValue != .null {
            return repeatValidationError(repeatValue)
        }
        return nil
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

    static func parseDate(_ value: JSONValue?) -> Date? {
        guard let value else {
            return nil
        }
        if let epochMilliseconds = value.numberValue {
            return Date(timeIntervalSince1970: epochMilliseconds / 1000)
        }
        guard let text = value.stringValue else {
            return nil
        }
        let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let fractionalDate = try? fractionalStyle.parse(text) {
            return fractionalDate
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    /// The form the shell writes dates in, matching JavaScript's `Date.toISOString()`.
    static func formatDate(_ date: Date) -> String {
        let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return fractionalStyle.format(date)
    }
}
