import Foundation

/// Calendar math for reminders: when each occurrence falls, and whether a repeat can be one iOS
/// repeating trigger. Pure and deterministic given the calendar (the phone's time zone).
struct ReminderSchedule: Sendable {
    let calendar: Calendar
    // Generating occurrences stops after this many steps, so a bad rule cannot hang the shell.
    private static let maximumSteps = 20_000

    /// A Gregorian calendar in the given zone with weeks starting on Sunday, matching the
    /// JavaScript weekday numbering Sidekicks use.
    static func phoneCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 1
        return calendar
    }

    /// The wall-clock fields of the reminder's `at`, read in the reminder's own zone.
    private struct Anchor {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
        let jsWeekday: Int
    }

    private func anchor(of record: ReminderRecord) -> Anchor {
        var anchorCalendar = calendar
        anchorCalendar.timeZone = record.timeZone ?? calendar.timeZone
        let fields = anchorCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: record.at)
        return Anchor(year: fields.year!, month: fields.month!, day: fields.day!, hour: fields.hour!,
                      minute: fields.minute!, second: fields.second!, jsWeekday: fields.weekday! - 1)
    }

    /// Occurrences strictly after `lowerBound`, soonest first, at most `limit` of them. A
    /// one-time reminder has the single occurrence `at`.
    func occurrences(of record: ReminderRecord, after lowerBound: Date, limit: Int) -> [Date] {
        guard limit > 0 else {
            return []
        }
        guard let rule = record.repeatRule else {
            return record.at > lowerBound ? [record.at] : []
        }
        let recordAnchor = anchor(of: record)
        guard let firstOccurrence = wallClockDate(year: recordAnchor.year, month: recordAnchor.month, day: recordAnchor.day, anchor: recordAnchor) else {
            return []
        }
        var collector = OccurrenceCollector(lowerBound: lowerBound, firstOccurrence: firstOccurrence, until: rule.until, limit: limit)
        switch rule.frequency {
        case .day:
            collectDaily(rule: rule, anchor: recordAnchor, collector: &collector)
        case .week:
            collectWeekly(rule: rule, anchor: recordAnchor, collector: &collector)
        case .month:
            collectMonthly(rule: rule, anchor: recordAnchor, collector: &collector)
        case .year:
            collectYearly(rule: rule, anchor: recordAnchor, collector: &collector)
        }
        return collector.collected
    }

    /// The latest occurrence in (after, notAfter], used to find a reminder missed while nothing
    /// was booked for it.
    func latestOccurrence(of record: ReminderRecord, after lowerBound: Date, notAfter upperBound: Date) -> Date? {
        var latestFound: Date?
        var searchFrom = lowerBound
        // Walk forward in pages; repeats missed for a long time still end within maximumSteps.
        for _ in 0..<50 {
            let page = occurrences(of: record, after: searchFrom, limit: 400)
            var pageReachedUpperBound = page.isEmpty
            for occurrence in page {
                if occurrence > upperBound {
                    pageReachedUpperBound = true
                    break
                }
                latestFound = occurrence
            }
            if pageReachedUpperBound || page.count < 400 {
                return latestFound
            }
            searchFrom = page.last!
        }
        return latestFound
    }

    /// The repeating trigger components for a repeat iOS can express itself (interval 1, no end
    /// date): one entry per trigger, each using one of the 64 slots. Nil means the repeat must be
    /// booked occurrence by occurrence. Weekly on several weekdays gives one entry per weekday.
    func nativeRepeatComponents(of record: ReminderRecord) -> [DateComponents]? {
        guard let rule = record.repeatRule, rule.interval == 1, rule.until == nil else {
            return nil
        }
        let recordAnchor = anchor(of: record)
        switch rule.frequency {
        case .day:
            let components = DateComponents(hour: recordAnchor.hour, minute: recordAnchor.minute, second: recordAnchor.second)
            return [components]
        case .week:
            let weekdays = rule.weekdays.isEmpty ? [recordAnchor.jsWeekday] : rule.weekdays
            var weekdayComponents: [DateComponents] = []
            for jsWeekday in weekdays {
                let components = DateComponents(hour: recordAnchor.hour, minute: recordAnchor.minute, second: recordAnchor.second, weekday: jsWeekday + 1)
                weekdayComponents.append(components)
            }
            return weekdayComponents
        case .month:
            let components = DateComponents(day: recordAnchor.day, hour: recordAnchor.hour, minute: recordAnchor.minute, second: recordAnchor.second)
            return [components]
        case .year:
            let components = DateComponents(month: recordAnchor.month, day: recordAnchor.day, hour: recordAnchor.hour, minute: recordAnchor.minute, second: recordAnchor.second)
            return [components]
        }
    }

    /// When an iOS repeating trigger with these components fires next after `date`.
    func nextNativeFire(after date: Date, matching components: DateComponents) -> Date? {
        calendar.nextDate(after: date, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward)
    }

    // MARK: - Per-frequency generation

    private func collectDaily(rule: RepeatRule, anchor: Anchor, collector: inout OccurrenceCollector) {
        let anchorDay = dayStart(year: anchor.year, month: anchor.month, day: anchor.day)
        let daysToLowerBound = calendar.dateComponents([.day], from: anchorDay, to: collector.lowerBound).day ?? 0
        // Jump close to the lower bound instead of walking from the first occurrence.
        var step = max(0, daysToLowerBound / rule.interval - 1)
        for _ in 0..<Self.maximumSteps {
            let candidateDay = calendar.date(byAdding: .day, value: step * rule.interval, to: anchorDay)!
            let candidateFields = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            let candidate = wallClockDate(year: candidateFields.year!, month: candidateFields.month!, day: candidateFields.day!, anchor: anchor)
            if collector.offer(candidate) == .stop {
                return
            }
            step += 1
        }
    }

    private func collectWeekly(rule: RepeatRule, anchor: Anchor, collector: inout OccurrenceCollector) {
        let anchorDay = dayStart(year: anchor.year, month: anchor.month, day: anchor.day)
        // Weeks run Sunday to Saturday; a "every 2 weeks" repeat counts weeks from the anchor's.
        let anchorWeekStart = calendar.date(byAdding: .day, value: -anchor.jsWeekday, to: anchorDay)!
        let weekdays = rule.weekdays.isEmpty ? [anchor.jsWeekday] : rule.weekdays
        let daysToLowerBound = calendar.dateComponents([.day], from: anchorWeekStart, to: collector.lowerBound).day ?? 0
        var step = max(0, daysToLowerBound / 7 / rule.interval - 1)
        for _ in 0..<Self.maximumSteps {
            for jsWeekday in weekdays {
                let dayOffset = step * rule.interval * 7 + jsWeekday
                let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: anchorWeekStart)!
                let candidateFields = calendar.dateComponents([.year, .month, .day], from: candidateDay)
                let candidate = wallClockDate(year: candidateFields.year!, month: candidateFields.month!, day: candidateFields.day!, anchor: anchor)
                if collector.offer(candidate) == .stop {
                    return
                }
            }
            step += 1
        }
    }

    // A monthly repeat on a day some months lack (the 31st) skips those months, as iOS's own
    // repeating trigger does.
    private func collectMonthly(rule: RepeatRule, anchor: Anchor, collector: inout OccurrenceCollector) {
        let lowerFields = calendar.dateComponents([.year, .month], from: collector.lowerBound)
        let monthsToLowerBound = (lowerFields.year! - anchor.year) * 12 + (lowerFields.month! - anchor.month)
        var step = max(0, monthsToLowerBound / rule.interval - 1)
        for _ in 0..<Self.maximumSteps {
            let monthIndex = anchor.month - 1 + step * rule.interval
            let candidateYear = anchor.year + monthIndex / 12
            let candidateMonth = monthIndex % 12 + 1
            if dayExists(year: candidateYear, month: candidateMonth, day: anchor.day) {
                let candidate = wallClockDate(year: candidateYear, month: candidateMonth, day: anchor.day, anchor: anchor)
                if collector.offer(candidate) == .stop {
                    return
                }
            }
            step += 1
        }
    }

    // A yearly repeat on February 29 fires in leap years only, as iOS's own trigger does.
    private func collectYearly(rule: RepeatRule, anchor: Anchor, collector: inout OccurrenceCollector) {
        let lowerYear = calendar.component(.year, from: collector.lowerBound)
        var step = max(0, (lowerYear - anchor.year) / rule.interval - 1)
        for _ in 0..<Self.maximumSteps {
            let candidateYear = anchor.year + step * rule.interval
            if dayExists(year: candidateYear, month: anchor.month, day: anchor.day) {
                let candidate = wallClockDate(year: candidateYear, month: anchor.month, day: anchor.day, anchor: anchor)
                if collector.offer(candidate) == .stop {
                    return
                }
            }
            step += 1
        }
    }

    // MARK: - Helpers

    private func dayStart(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: components)!
    }

    private func dayExists(year: Int, month: Int, day: Int) -> Bool {
        let firstOfMonth = dayStart(year: year, month: month, day: 1)
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 0
        return day <= daysInMonth
    }

    // The anchor's wall-clock time on the given day in the phone's zone. A time skipped by a
    // daylight-saving jump moves forward to the first valid moment, as Calendar does.
    private func wallClockDate(year: Int, month: Int, day: Int, anchor: Anchor) -> Date? {
        let components = DateComponents(year: year, month: month, day: day, hour: anchor.hour, minute: anchor.minute, second: anchor.second)
        return calendar.date(from: components)
    }
}

/// Accepts candidate occurrences in increasing order and keeps those inside the window.
private struct OccurrenceCollector {
    enum Verdict {
        case keepGoing
        case stop
    }

    let lowerBound: Date
    let firstOccurrence: Date
    let until: Date?
    let limit: Int
    private(set) var collected: [Date] = []

    init(lowerBound: Date, firstOccurrence: Date, until: Date?, limit: Int) {
        self.lowerBound = lowerBound
        self.firstOccurrence = firstOccurrence
        self.until = until
        self.limit = limit
    }

    mutating func offer(_ candidate: Date?) -> Verdict {
        guard let candidate else {
            return .keepGoing
        }
        if let until, candidate > until {
            return .stop
        }
        let isInWindow = candidate > lowerBound && candidate >= firstOccurrence
        if isInWindow {
            collected.append(candidate)
        }
        return collected.count >= limit ? .stop : .keepGoing
    }
}
