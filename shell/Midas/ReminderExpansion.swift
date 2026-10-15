import Foundation

/// An early alert rule carried on a `reminder:` record (`alerts`, care.item in the care-reminders
/// manifest): a notification before the reminder itself. Kinds: `daysBefore` (N days before at a
/// clock time), `morningOf` (the day itself at a clock time), `before` (N minutes before).
struct EarlyAlertRule: Equatable, Sendable {
    let id: String
    let kind: String
    let days: Int
    let minutes: Int
    /// "HH:MM" for the day kinds.
    let time: String
    /// The person's own wording, with {title}, {time} and {day}; nil for the default.
    let text: String?

    static func parse(_ value: JSONValue) -> EarlyAlertRule? {
        guard let id = value["id"]?.stringValue, let kind = value["kind"]?.stringValue else {
            return nil
        }
        let days = Int(value["days"]?.numberValue ?? 1)
        let minutes = Int(value["minutes"]?.numberValue ?? 60)
        let time = value["time"]?.stringValue ?? (kind == "morningOf" ? "08:00" : "18:00")
        let text = value["text"]?.stringValue
        return EarlyAlertRule(id: id, kind: kind, days: days, minutes: minutes, time: time, text: text)
    }
}

/// Turns one stored reminder into every notification it stands for (unified data plan, phases 3
/// and 4: "early alerts and hourly times become fields on the item; the engine expands them").
/// Before 2026-10-15 the care-reminders page wrote one record per early alert
/// (`reminder:<id>~<rule>`) and per hourly time (`reminder:<id>@HHMM`); now the item carries
/// `alerts` and `everyHours`, and the engine builds the same reminders in memory, under the same
/// ids, so engine state (ledger, bookings) carries over unchanged.
struct ReminderExpansion: Sendable {
    static let alertSeparator = "~"
    static let slotSeparator = "@"
    static let hourlyIntervals: Set<Int> = [2, 3, 4]

    let schedule: ReminderSchedule

    /// The record itself first, then its hourly times, then its early alerts.
    func expand(_ record: ReminderRecord, now: Date) -> [ReminderRecord] {
        var expanded = [record]
        expanded.append(contentsOf: hourlySlots(of: record))
        expanded.append(contentsOf: earlyAlerts(of: record, now: now))
        return expanded
    }

    /// Which stored record a notification's reminder id belongs to, and what part of it:
    /// `<id>` itself, `<id>~<rule>` an early alert, `<id>@HHMM` an hourly time.
    enum Part: Equatable, Sendable {
        case item
        case alert(ruleId: String)
        case slot(time: String)
    }

    static func split(reminderId: String) -> (itemId: String, part: Part) {
        if let separatorIndex = reminderId.firstIndex(of: Character(slotSeparator)) {
            let itemId = String(reminderId[..<separatorIndex])
            let digits = String(reminderId[reminderId.index(after: separatorIndex)...])
            return (itemId, .slot(time: wallTime(fromDigits: digits)))
        }
        if let separatorIndex = reminderId.firstIndex(of: Character(alertSeparator)) {
            let itemId = String(reminderId[..<separatorIndex])
            let ruleId = String(reminderId[reminderId.index(after: separatorIndex)...])
            return (itemId, .alert(ruleId: ruleId))
        }
        return (reminderId, .item)
    }

    // MARK: Hourly times

    /// The wall-clock times an hourly item fires each day, its own time first: every 3 hours
    /// from 08:00 is 08:00, 11:00, ... 23:00, 02:00, 05:00.
    func timesOfDay(_ record: ReminderRecord) -> [String] {
        guard let everyHours = record.everyHours, Self.hourlyIntervals.contains(everyHours) else {
            return [Self.wallTime(of: record.at, in: record.timeZone ?? schedule.calendar.timeZone)]
        }
        let zone = record.timeZone ?? schedule.calendar.timeZone
        let startMinutes = Self.minutesOfDay(of: record.at, in: zone)
        var times: [String] = []
        var offset = 0
        while offset < 24 * 60 {
            times.append(Self.wallTime(fromMinutes: (startMinutes + offset) % (24 * 60)))
            offset += everyHours * 60
        }
        return times
    }

    /// One daily reminder per extra time, starting the first time it falls on or after the
    /// item's own first time; a time earlier in the day than the item's own first comes the
    /// next day.
    func hourlySlots(of record: ReminderRecord) -> [ReminderRecord] {
        guard let everyHours = record.everyHours, Self.hourlyIntervals.contains(everyHours) else {
            return []
        }
        let zone = record.timeZone ?? schedule.calendar.timeZone
        var zoneCalendar = schedule.calendar
        zoneCalendar.timeZone = zone
        var slots: [ReminderRecord] = []
        for time in timesOfDay(record).dropFirst() {
            guard let firstFire = Self.firstInstant(withWallTime: time, onOrAfter: record.at, calendar: zoneCalendar) else {
                continue
            }
            let slotId = "\(record.identity.reminderId)\(Self.slotSeparator)\(time.replacingOccurrences(of: ":", with: ""))"
            let identity = ReminderIdentity(sidekickId: record.identity.sidekickId, reminderId: slotId)
            let dailyRule = RepeatRule(frequency: .day, interval: 1, weekdays: [], until: nil)
            let slot = ReminderRecord(identity: identity, at: firstFire, title: record.title, body: record.body, repeatRule: dailyRule,
                                      timeZone: record.timeZone, done: record.done, snoozedUntil: nil, lastDoneAt: record.slotsDone[time],
                                      doneThrough: nil, alerts: [], everyHours: nil, slotsDone: [:])
            slots.append(slot)
        }
        return slots
    }

    // MARK: Early alerts

    /// The occurrence whose early alerts are booked: the item's own time for a one-time item,
    /// the next occurrence after now and after what is done for a repeat. Nil when done.
    func targetOccurrence(of record: ReminderRecord, now: Date) -> Date? {
        guard !record.done else {
            return nil
        }
        guard record.repeatRule != nil else {
            return record.at
        }
        let after = max(now, record.doneThrough ?? .distantPast)
        return schedule.occurrences(of: record, after: after, limit: 1).first
    }

    /// One one-time reminder per rule whose moment is still ahead and before the occurrence.
    /// An hourly item fires only at its own times (no early alerts).
    func earlyAlerts(of record: ReminderRecord, now: Date) -> [ReminderRecord] {
        guard !record.alerts.isEmpty, record.everyHours == nil else {
            return []
        }
        guard let occurrence = targetOccurrence(of: record, now: now) else {
            return []
        }
        let zone = record.timeZone ?? schedule.calendar.timeZone
        var alerts: [ReminderRecord] = []
        for rule in record.alerts {
            guard let alertAt = alertMoment(rule: rule, occurrence: occurrence, zone: zone) else {
                continue
            }
            guard alertAt > now, alertAt < occurrence else {
                continue
            }
            let alertId = "\(record.identity.reminderId)\(Self.alertSeparator)\(rule.id)"
            let identity = ReminderIdentity(sidekickId: record.identity.sidekickId, reminderId: alertId)
            let title = Self.wording(rule: rule, title: record.title, occurrence: occurrence, alertAt: alertAt, zone: zone)
            let alert = ReminderRecord(identity: identity, at: alertAt, title: title, body: "", repeatRule: nil, timeZone: record.timeZone,
                                       done: false, snoozedUntil: nil, lastDoneAt: nil, doneThrough: nil, alerts: [], everyHours: nil, slotsDone: [:])
            alerts.append(alert)
        }
        return alerts
    }

    /// When a rule fires for one occurrence.
    func alertMoment(rule: EarlyAlertRule, occurrence: Date, zone: TimeZone) -> Date? {
        if rule.kind == "before" {
            return occurrence.addingTimeInterval(-Double(rule.minutes) * 60)
        }
        var zoneCalendar = schedule.calendar
        zoneCalendar.timeZone = zone
        let daysBefore = rule.kind == "morningOf" ? 0 : rule.days
        guard let alertDay = zoneCalendar.date(byAdding: .day, value: -daysBefore, to: zoneCalendar.startOfDay(for: occurrence)) else {
            return nil
        }
        let (hour, minute) = Self.hourAndMinute(of: rule.time)
        return zoneCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: alertDay)
    }

    // MARK: Wording (the care-reminders page's templates, docs/WRITING.md: say it, stop)

    static func wording(rule: EarlyAlertRule, title: String, occurrence: Date, alertAt: Date, zone: TimeZone) -> String {
        let template = rule.text?.trimmingCharacters(in: .whitespaces).isEmpty == false ? rule.text! : defaultTemplate(rule)
        var text = template.replacingOccurrences(of: "{title}", with: title)
        text = text.replacingOccurrences(of: "{time}", with: formatTime(occurrence, zone: zone))
        text = text.replacingOccurrences(of: "{day}", with: dayWord(rule: rule, occurrence: occurrence, alertAt: alertAt, zone: zone))
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func defaultTemplate(_ rule: EarlyAlertRule) -> String {
        if rule.kind == "before" {
            return "{title} in \(leadText(minutes: rule.minutes))"
        }
        if rule.kind == "daysBefore" && rule.days > 1 {
            return "{title} on {day} at {time}"
        }
        return "{title} {day} at {time}"
    }

    static func leadText(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 {
            return "\(rest) min"
        }
        if rest == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(hours) h \(rest) min"
    }

    /// "today", "tomorrow", or the weekday two or more days out.
    static func dayWord(rule: EarlyAlertRule, occurrence: Date, alertAt: Date, zone: TimeZone) -> String {
        var zoneCalendar = ReminderSchedule.phoneCalendar(timeZone: zone)
        zoneCalendar.timeZone = zone
        var days = 0
        if rule.kind == "daysBefore" {
            days = rule.days
        } else if rule.kind == "before" {
            let alertDay = zoneCalendar.startOfDay(for: alertAt)
            let occurrenceDay = zoneCalendar.startOfDay(for: occurrence)
            days = zoneCalendar.dateComponents([.day], from: alertDay, to: occurrenceDay).day ?? 0
        }
        if days == 0 {
            return "today"
        }
        if days == 1 {
            return "tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: occurrence)
    }

    /// The clock time as the phone shows it ("1:00 PM" or "13:00" by locale), like the page's
    /// `Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' })`.
    static func formatTime(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: Wall-clock helpers

    static func hourAndMinute(of wallTime: String) -> (Int, Int) {
        let parts = wallTime.split(separator: ":")
        let hour = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (hour, minute)
    }

    static func wallTime(fromMinutes minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "0800" (as in a slot id) to "08:00".
    static func wallTime(fromDigits digits: String) -> String {
        guard digits.count == 4 else {
            return digits
        }
        return "\(digits.prefix(2)):\(digits.suffix(2))"
    }

    static func wallTime(of date: Date, in zone: TimeZone) -> String {
        wallTime(fromMinutes: minutesOfDay(of: date, in: zone))
    }

    static func minutesOfDay(of date: Date, in zone: TimeZone) -> Int {
        var zoneCalendar = ReminderSchedule.phoneCalendar(timeZone: zone)
        zoneCalendar.timeZone = zone
        let fields = zoneCalendar.dateComponents([.hour, .minute], from: date)
        return (fields.hour ?? 0) * 60 + (fields.minute ?? 0)
    }

    static func firstInstant(withWallTime wallTime: String, onOrAfter start: Date, calendar: Calendar) -> Date? {
        let (hour, minute) = hourAndMinute(of: wallTime)
        let startDay = calendar.startOfDay(for: start)
        guard let sameDay = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startDay) else {
            return nil
        }
        if sameDay >= start {
            return sameDay
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startDay) else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: nextDay)
    }
}
