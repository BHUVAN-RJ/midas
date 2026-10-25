import Foundation

enum BookingKind: String, Codable, Sendable {
    /// One occurrence of a reminder, booked as a one-time trigger.
    case occurrence
    /// An iOS repeating trigger: one slot, fires every period until removed.
    case repeating
    /// A snoozed reminder firing again; comes out of the reserved slots.
    case snooze
    /// An occurrence whose time passed while nothing was booked for it; fires right away.
    case missed
}

enum BookingTrigger: Equatable, Codable, Sendable {
    case date(Date)
    case repeating(DateComponents)
    case immediately
}

/// How a booking reaches its person (founder, 2026-10-24): L2 Active, L3 Time Sensitive (both
/// notifications), or L5 an AlarmKit alarm.
enum BookingLevel: String, Codable, Sendable {
    case active
    case timeSensitive
    case alarm
}

/// One notification (or alarm) the engine wants iOS to hold.
struct PlannedBooking: Equatable, Codable, Sendable {
    static let identifierPrefix = "reminder|"
    /// Between the time and the notes in the body (layout A, mockup notification-levels-2026-10-24).
    static let bodySeparator = " · "

    let identifier: String
    let identity: ReminderIdentity
    let kind: BookingKind
    let trigger: BookingTrigger
    /// When it fires (next, for a repeating trigger). Orders bookings against the budget.
    let fireDate: Date
    /// The occurrence it is for; nil for a repeating trigger.
    let occurrence: Date?
    let title: String
    /// The item's notes (founder, 2026-10-20); the body shows them after the time.
    let body: String
    /// The Sidekick's name as the person sees it (layout A, founder 2026-10-24); "" for none.
    var subtitle: String = ""
    /// The reminder's time as the phone shows it ("11:00 PM"), first in the body; "" for none.
    var timeText: String = ""
    var level: BookingLevel = .timeSensitive

    /// Layout A's body: the time, then the notes.
    var notificationBody: String {
        var parts: [String] = []
        if !timeText.isEmpty {
            parts.append(timeText)
        }
        if !body.isEmpty {
            parts.append(body)
        }
        return parts.joined(separator: Self.bodySeparator)
    }

    init(identifier: String, identity: ReminderIdentity, kind: BookingKind, trigger: BookingTrigger, fireDate: Date, occurrence: Date?,
         title: String, body: String, subtitle: String = "", timeText: String = "", level: BookingLevel = .timeSensitive) {
        self.identifier = identifier
        self.identity = identity
        self.kind = kind
        self.trigger = trigger
        self.fireDate = fireDate
        self.occurrence = occurrence
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.timeText = timeText
        self.level = level
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, identity, kind, trigger, fireDate, occurrence, title, body, subtitle, timeText, level
    }

    // State saved before 2026-10-24 has no subtitle, time or level; it still loads, so the
    // ledger survives the update (a lost ledger would fire past one-time reminders again).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        identity = try container.decode(ReminderIdentity.self, forKey: .identity)
        kind = try container.decode(BookingKind.self, forKey: .kind)
        trigger = try container.decode(BookingTrigger.self, forKey: .trigger)
        fireDate = try container.decode(Date.self, forKey: .fireDate)
        occurrence = try container.decodeIfPresent(Date.self, forKey: .occurrence)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        timeText = try container.decodeIfPresent(String.self, forKey: .timeText) ?? ""
        level = try container.decodeIfPresent(BookingLevel.self, forKey: .level) ?? .timeSensitive
    }

    static func makeIdentifier(identity: ReminderIdentity, kind: BookingKind, suffix: String) -> String {
        "\(identifierPrefix)\(identity.sidekickId)|\(identity.reminderId)|\(kind.rawValue)|\(suffix)"
    }
}

/// For each reminder, every occurrence at or before `handledThrough` was delivered, shown as
/// missed, or predates the reminder. Anything later that passes unbooked is missed.
typealias ReminderLedger = [String: Date]

struct ReminderPlan: Equatable, Sendable {
    let bookings: [PlannedBooking]
    let ledger: ReminderLedger
}

/// Decides which notifications iOS should hold. Pure: same input, same plan. The engine runs it
/// whenever the app gets to run and applies the difference to iOS.
///
/// iOS holds at most 64 scheduled notifications per app, shared by every Sidekick. The planner
/// books at most `budget` (48) reminders, soonest first, and keeps `snoozeBudget` (16) for
/// snoozes and later uses. Alarms (AlarmKit) are not notifications and count against neither.
struct ReminderPlanner: Sendable {
    static let defaultBudget = 48
    static let defaultSnoozeBudget = 16

    let schedule: ReminderSchedule
    let budget: Int
    let snoozeBudget: Int

    init(schedule: ReminderSchedule, budget: Int = defaultBudget, snoozeBudget: Int = defaultSnoozeBudget) {
        self.schedule = schedule
        self.budget = budget
        self.snoozeBudget = snoozeBudget
    }

    /// `sidekickNames` gives each booking its subtitle (the name on the home tile).
    /// `alarmsAllowed` is false when AlarmKit was declined or the phone is older than iOS 26: an
    /// Alarm reminder is then booked as a Time Sensitive notification (founder, 2026-10-24).
    func plan(records: [ReminderRecord], ledger previousLedger: ReminderLedger, previousBookings: [PlannedBooking], now: Date,
              sidekickNames: [String: String] = [:], alarmsAllowed: Bool = false) -> ReminderPlan {
        var ledger = advance(ledger: previousLedger, deliveredBy: previousBookings, now: now)
        var regularCandidates: [PlannedBooking] = []
        var snoozeCandidates: [PlannedBooking] = []
        var alarmBookings: [PlannedBooking] = []
        var liveLedgerKeys: Set<String> = []

        for record in records {
            let ledgerKey = record.identity.ledgerKey
            liveLedgerKeys.insert(ledgerKey)
            // A new one-time reminder already in the past still fires once; a new repeat starts
            // counting from now, so its past occurrences are not reported as missed.
            var handledThrough = ledger[ledgerKey] ?? (record.repeatRule == nil ? .distantPast : now)
            // Times a listening reminder kept quiet were dealt with, not missed (hydration plan
            // N2): the ledger moves past them, even into the future (the rest of a met day).
            if let quietUntil = record.quietUntil, quietUntil > handledThrough {
                handledThrough = quietUntil
            }
            ledger[ledgerKey] = handledThrough
            guard !record.done else {
                continue
            }
            let style = BookingStyle(record: record, sidekickNames: sidekickNames, alarmsAllowed: alarmsAllowed)
            if let missedBooking = missedBooking(for: record, style: style, handledThrough: handledThrough, now: now) {
                regularCandidates.append(missedBooking)
                ledger[ledgerKey] = now
            }
            if style.level == .alarm {
                alarmBookings.append(contentsOf: upcomingAlarms(for: record, style: style, handledThrough: handledThrough, now: now))
                if let snoozeAlarm = snoozeBooking(for: record, style: style, now: now) {
                    alarmBookings.append(snoozeAlarm)
                }
                continue
            }
            let futureBookings = upcomingBookings(for: record, style: style, handledThrough: handledThrough, now: now)
            regularCandidates.append(contentsOf: futureBookings)
            if let snoozeBooking = snoozeBooking(for: record, style: style, now: now) {
                snoozeCandidates.append(snoozeBooking)
            }
        }

        regularCandidates.sort(by: Self.isBookedFirst)
        snoozeCandidates.sort(by: Self.isBookedFirst)
        alarmBookings.sort(by: Self.isBookedFirst)
        let keptRegular = regularCandidates.prefix(budget)
        let keptSnoozes = snoozeCandidates.prefix(snoozeBudget)
        let bookings = Array(keptRegular) + Array(keptSnoozes) + alarmBookings

        // Forget deleted reminders so the ledger does not grow forever.
        for ledgerKey in ledger.keys where !liveLedgerKeys.contains(ledgerKey) {
            ledger.removeValue(forKey: ledgerKey)
        }
        return ReminderPlan(bookings: bookings, ledger: ledger)
    }

    /// What every booking of one record shares: its level, its subtitle, and the zone its time
    /// is shown in.
    private struct BookingStyle {
        let level: BookingLevel
        let subtitle: String

        init(record: ReminderRecord, sidekickNames: [String: String], alarmsAllowed: Bool) {
            switch record.reminderType {
            case .normal:
                level = .active
            case .timeSensitive:
                level = .timeSensitive
            case .alarm:
                level = alarmsAllowed ? .alarm : .timeSensitive
            }
            subtitle = sidekickNames[record.identity.sidekickId] ?? ""
        }

        /// A notification in place of an alarm (an Alarm reminder's missed notice) is Time
        /// Sensitive (founder, 2026-10-24).
        var notificationLevel: BookingLevel {
            level == .alarm ? .timeSensitive : level
        }
    }

    /// The reminder's time on the phone's clock, as the body shows it.
    private func timeText(of moment: Date) -> String {
        ReminderExpansion.formatTime(moment, zone: schedule.calendar.timeZone)
    }

    /// Bookings that iOS held until their time came were delivered by iOS, so the ledger moves
    /// past them. A repeating trigger delivered every occurrence up to now.
    func advance(ledger previousLedger: ReminderLedger, deliveredBy previousBookings: [PlannedBooking], now: Date) -> ReminderLedger {
        var ledger = previousLedger
        for booking in previousBookings {
            let ledgerKey = booking.identity.ledgerKey
            let currentMark = ledger[ledgerKey] ?? .distantPast
            switch booking.kind {
            case .repeating:
                ledger[ledgerKey] = max(currentMark, now)
            case .occurrence, .missed:
                if booking.fireDate <= now {
                    let deliveredOccurrence = booking.occurrence ?? booking.fireDate
                    ledger[ledgerKey] = max(currentMark, deliveredOccurrence)
                }
            case .snooze:
                continue
            }
        }
        return ledger
    }

    private func missedBooking(for record: ReminderRecord, style: BookingStyle, handledThrough: Date, now: Date) -> PlannedBooking? {
        guard let missedOccurrence = schedule.latestOccurrence(of: record, after: handledThrough, notAfter: now) else {
            return nil
        }
        let suffix = String(Int(missedOccurrence.timeIntervalSince1970))
        let identifier = PlannedBooking.makeIdentifier(identity: record.identity, kind: .missed, suffix: suffix)
        return PlannedBooking(identifier: identifier, identity: record.identity, kind: .missed, trigger: .immediately,
                              fireDate: now, occurrence: missedOccurrence, title: record.title, body: record.notes,
                              subtitle: style.subtitle, timeText: timeText(of: missedOccurrence), level: style.notificationLevel)
    }

    private func upcomingBookings(for record: ReminderRecord, style: BookingStyle, handledThrough: Date, now: Date) -> [PlannedBooking] {
        if let repeatingBookings = nativeRepeatingBookings(for: record, style: style, now: now) {
            return repeatingBookings
        }
        var lowerBound = max(now, handledThrough)
        // A listening reminder's ledger can run ahead of now (a met day); what is quiet now is
        // `quietUntil` alone, so a day that is no longer met (an undo) gets its times back.
        if record.listen != nil {
            lowerBound = max(now, record.quietUntil ?? now)
        }
        let upcomingOccurrences = schedule.occurrences(of: record, after: lowerBound, limit: budget)
        var bookings: [PlannedBooking] = []
        for occurrence in upcomingOccurrences {
            let suffix = String(Int(occurrence.timeIntervalSince1970))
            let identifier = PlannedBooking.makeIdentifier(identity: record.identity, kind: .occurrence, suffix: suffix)
            let booking = PlannedBooking(identifier: identifier, identity: record.identity, kind: .occurrence, trigger: .date(occurrence),
                                         fireDate: occurrence, occurrence: occurrence, title: record.title, body: record.notes,
                                         subtitle: style.subtitle, timeText: timeText(of: occurrence), level: style.level)
            bookings.append(booking)
        }
        return bookings
    }

    /// An Alarm reminder's alarms (founder, 2026-10-24). AlarmKit repeats only never or weekly:
    /// a daily or weekly repeat with interval 1 and no end rings from AlarmKit's own schedule;
    /// every other repeat is booked as one alarm for its next occurrence and re-booked on each
    /// run (if Midas does not run before the one after, that one fires as a missed notification).
    private func upcomingAlarms(for record: ReminderRecord, style: BookingStyle, handledThrough: Date, now: Date) -> [PlannedBooking] {
        let frequency = record.repeatRule?.frequency
        let alarmKitCanRepeat = frequency == .day || frequency == .week
        if alarmKitCanRepeat, let repeatingAlarms = nativeRepeatingBookings(for: record, style: style, now: now) {
            return repeatingAlarms
        }
        var lowerBound = max(now, handledThrough)
        // As for notifications: a listening reminder is quiet until `quietUntil` only.
        if record.listen != nil {
            lowerBound = max(now, record.quietUntil ?? now)
        }
        guard let nextOccurrence = schedule.occurrences(of: record, after: lowerBound, limit: 1).first else {
            return []
        }
        let suffix = String(Int(nextOccurrence.timeIntervalSince1970))
        let identifier = PlannedBooking.makeIdentifier(identity: record.identity, kind: .occurrence, suffix: suffix)
        let alarm = PlannedBooking(identifier: identifier, identity: record.identity, kind: .occurrence, trigger: .date(nextOccurrence),
                                   fireDate: nextOccurrence, occurrence: nextOccurrence, title: record.title, body: record.notes,
                                   subtitle: style.subtitle, timeText: timeText(of: nextOccurrence), level: .alarm)
        return [alarm]
    }

    // A repeat becomes iOS repeating triggers only once its first occurrence is due before the
    // trigger's next fire; until then a repeating trigger would fire too early, so its
    // occurrences are booked one by one and the next run switches it over. A listening reminder
    // kept quiet takes the same path: its first occurrence is the first after the quiet.
    private func nativeRepeatingBookings(for record: ReminderRecord, style: BookingStyle, now: Date) -> [PlannedBooking]? {
        guard let componentList = schedule.nativeRepeatComponents(of: record) else {
            return nil
        }
        let firstAllowed = record.quietUntil ?? .distantPast
        guard let firstOccurrence = schedule.occurrences(of: record, after: firstAllowed, limit: 1).first else {
            return nil
        }
        var bookings: [PlannedBooking] = []
        for (triggerIndex, components) in componentList.enumerated() {
            guard let nextFire = schedule.nextNativeFire(after: now, matching: components), nextFire >= firstOccurrence else {
                return nil
            }
            let identifier = PlannedBooking.makeIdentifier(identity: record.identity, kind: .repeating, suffix: String(triggerIndex))
            let booking = PlannedBooking(identifier: identifier, identity: record.identity, kind: .repeating, trigger: .repeating(components),
                                         fireDate: nextFire, occurrence: nil, title: record.title, body: record.notes,
                                         subtitle: style.subtitle, timeText: timeText(of: nextFire), level: style.level)
            bookings.append(booking)
        }
        return bookings
    }

    private func snoozeBooking(for record: ReminderRecord, style: BookingStyle, now: Date) -> PlannedBooking? {
        guard let snoozedUntil = record.snoozedUntil, snoozedUntil > now else {
            return nil
        }
        let suffix = String(Int(snoozedUntil.timeIntervalSince1970))
        let identifier = PlannedBooking.makeIdentifier(identity: record.identity, kind: .snooze, suffix: suffix)
        // The body keeps the time the reminder was for, not the snooze's.
        let snoozedOccurrence = schedule.latestOccurrence(of: record, after: .distantPast, notAfter: snoozedUntil) ?? record.at
        return PlannedBooking(identifier: identifier, identity: record.identity, kind: .snooze, trigger: .date(snoozedUntil),
                              fireDate: snoozedUntil, occurrence: snoozedUntil, title: record.title, body: record.notes,
                              subtitle: style.subtitle, timeText: timeText(of: snoozedOccurrence), level: style.level)
    }

    // Soonest first; ties broken by owner, reminder and identifier so the plan never flickers.
    private static func isBookedFirst(_ first: PlannedBooking, _ second: PlannedBooking) -> Bool {
        if first.fireDate != second.fireDate {
            return first.fireDate < second.fireDate
        }
        if first.identity != second.identity {
            return first.identity < second.identity
        }
        return first.identifier < second.identifier
    }
}
