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

/// One notification the engine wants iOS to hold.
struct PlannedBooking: Equatable, Codable, Sendable {
    static let identifierPrefix = "reminder|"

    let identifier: String
    let identity: ReminderIdentity
    let kind: BookingKind
    let trigger: BookingTrigger
    /// When it fires (next, for a repeating trigger). Orders bookings against the budget.
    let fireDate: Date
    /// The occurrence it is for; nil for a repeating trigger.
    let occurrence: Date?
    let title: String
    /// The notification text under the title: the item's notes (founder, 2026-10-20).
    let body: String

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
/// snoozes and later uses.
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

    func plan(records: [ReminderRecord], ledger previousLedger: ReminderLedger, previousBookings: [PlannedBooking], now: Date) -> ReminderPlan {
        var ledger = advance(ledger: previousLedger, deliveredBy: previousBookings, now: now)
        var regularCandidates: [PlannedBooking] = []
        var snoozeCandidates: [PlannedBooking] = []
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
            if let missedBooking = missedBooking(for: record, handledThrough: handledThrough, now: now) {
                regularCandidates.append(missedBooking)
                ledger[ledgerKey] = now
            }
            let futureBookings = upcomingBookings(for: record, handledThrough: handledThrough, now: now)
            regularCandidates.append(contentsOf: futureBookings)
            if let snoozeBooking = snoozeBooking(for: record, now: now) {
                snoozeCandidates.append(snoozeBooking)
            }
        }

        regularCandidates.sort(by: Self.isBookedFirst)
        snoozeCandidates.sort(by: Self.isBookedFirst)
        let keptRegular = regularCandidates.prefix(budget)
        let keptSnoozes = snoozeCandidates.prefix(snoozeBudget)
        let bookings = Array(keptRegular) + Array(keptSnoozes)

        // Forget deleted reminders so the ledger does not grow forever.
        for ledgerKey in ledger.keys where !liveLedgerKeys.contains(ledgerKey) {
            ledger.removeValue(forKey: ledgerKey)
        }
        return ReminderPlan(bookings: bookings, ledger: ledger)
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

    private func missedBooking(for record: ReminderRecord, handledThrough: Date, now: Date) -> PlannedBooking? {
        guard let missedOccurrence = schedule.latestOccurrence(of: record, after: handledThrough, notAfter: now) else {
            return nil
        }
        let suffix = String(Int(missedOccurrence.timeIntervalSince1970))
        let identifier = PlannedBooking.makeIdentifier(identity: record.identity, kind: .missed, suffix: suffix)
        return PlannedBooking(identifier: identifier, identity: record.identity, kind: .missed, trigger: .immediately,
                              fireDate: now, occurrence: missedOccurrence, title: record.title, body: record.notes)
    }

    private func upcomingBookings(for record: ReminderRecord, handledThrough: Date, now: Date) -> [PlannedBooking] {
        if let repeatingBookings = nativeRepeatingBookings(for: record, now: now) {
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
                                         fireDate: occurrence, occurrence: occurrence, title: record.title, body: record.notes)
            bookings.append(booking)
        }
        return bookings
    }

    // A repeat becomes iOS repeating triggers only once its first occurrence is due before the
    // trigger's next fire; until then a repeating trigger would fire too early, so its
    // occurrences are booked one by one and the next run switches it over. A listening reminder
    // kept quiet takes the same path: its first occurrence is the first after the quiet.
    private func nativeRepeatingBookings(for record: ReminderRecord, now: Date) -> [PlannedBooking]? {
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
                                         fireDate: nextFire, occurrence: nil, title: record.title, body: record.notes)
            bookings.append(booking)
        }
        return bookings
    }

    private func snoozeBooking(for record: ReminderRecord, now: Date) -> PlannedBooking? {
        guard let snoozedUntil = record.snoozedUntil, snoozedUntil > now else {
            return nil
        }
        let suffix = String(Int(snoozedUntil.timeIntervalSince1970))
        let identifier = PlannedBooking.makeIdentifier(identity: record.identity, kind: .snooze, suffix: suffix)
        return PlannedBooking(identifier: identifier, identity: record.identity, kind: .snooze, trigger: .date(snoozedUntil),
                              fireDate: snoozedUntil, occurrence: snoozedUntil, title: record.title, body: record.notes)
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
