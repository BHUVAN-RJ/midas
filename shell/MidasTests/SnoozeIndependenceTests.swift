import XCTest
@testable import Midas

// Founder decision 2026-10-15: a snooze on an early alert or an hourly time brings back THAT
// notification's own text, and snoozing one never replaces another's. Before the rework each
// alert and time was a record with its own `snoozedUntil`; now the item carries them in
// `snoozes` (`~rule` / `@HHMM` to date) next to its own `snoozedUntil`. These tests fail if the
// wording or the independence regresses, for the patches, the expansion, the planner and the
// engine.

/// Stands in for iOS: holds the pending bookings.
@MainActor
private final class SnoozeFakeBooking: NotificationBooking {
    var pending: [String: PlannedBooking] = [:]

    func requestAuthorizationIfNeeded() async -> Bool {
        true
    }

    func pendingIdentifiers() async -> [String] {
        Array(pending.keys)
    }

    func book(_ booking: PlannedBooking) async throws {
        pending[booking.identifier] = booking
    }

    func cancel(identifiers: [String]) {
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }

    /// iOS fires and forgets one-time notifications whose time came.
    func deliverDue(now: Date) {
        for (identifier, booking) in pending where booking.kind != .repeating && booking.fireDate <= now {
            pending.removeValue(forKey: identifier)
        }
    }

    func pendingTitles() -> Set<String> {
        var titles: Set<String> = []
        for booking in pending.values {
            titles.insert(booking.title)
        }
        return titles
    }
}

@MainActor
private final class SnoozeTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func currentTime() -> Date {
        now
    }
}

@MainActor
final class SnoozeIndependenceTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private var calendar: Calendar {
        ReminderSchedule.phoneCalendar(timeZone: zone)
    }
    private var expansion: ReminderExpansion {
        ReminderExpansion(schedule: ReminderSchedule(calendar: calendar))
    }

    private func date(_ text: String) -> Date {
        ReminderRecord.parseDate(.string(text))!
    }

    private let threeRules: JSONValue = .array([
        .object(["id": .string("a1"), "kind": .string("daysBefore"), "days": .number(1), "time": .string("18:00")]),
        .object(["id": .string("a2"), "kind": .string("morningOf"), "time": .string("08:00")]),
        .object(["id": .string("a3"), "kind": .string("before"), "minutes": .number(60)]),
    ])

    /// Dentist on 2026-10-18 13:00 PT with three early alerts.
    private func dentistValue(snoozes: [String: JSONValue] = [:], snoozedUntil: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "title": .string("Dentist"), "at": .string("2026-10-18T13:00:00-07:00"), "timeZone": .string(zone.identifier), "alerts": threeRules,
        ]
        if !snoozes.isEmpty {
            fields["snoozes"] = .object(snoozes)
        }
        if let snoozedUntil {
            fields["snoozedUntil"] = .string(snoozedUntil)
        }
        return .object(fields)
    }

    private func parse(_ key: String, _ value: JSONValue) -> ReminderRecord {
        ReminderRecord.parse(sidekickId: "care-reminders", key: key, value: value)!
    }

    private var dayBeforeWording: String {
        "Dentist tomorrow at \(ReminderExpansion.formatTime(date("2026-10-18T13:00:00-07:00"), zone: zone))"
    }

    // MARK: Patches

    func testASnoozeOnAnAlertOrATimeIsItsOwnEntryAndASnoozeOnTheItemIsSnoozedUntil() {
        let when = date("2026-10-17T18:10:00-07:00")
        let whenText = ReminderRecord.formatDate(when)
        XCTAssertEqual(ReminderChange.snoozePatch(until: when, part: .alert(ruleId: "a1")), .object(["snoozes": .object(["~a1": .string(whenText)])]))
        XCTAssertEqual(ReminderChange.snoozePatch(until: when, part: .slot(time: "11:00")), .object(["snoozes": .object(["@1100": .string(whenText)])]))
        XCTAssertEqual(ReminderChange.snoozePatch(until: when, part: .item), .object(["snoozedUntil": .string(whenText)]))
    }

    func testSnoozingOneAlertNeverReplacesAnothersOrTheItems() {
        let now = date("2026-10-17T18:05:00-07:00")
        var value = dentistValue(snoozedUntil: "2026-10-18T13:20:00-07:00")
        value = ReminderAction.snoozeTenMinutes.apply(to: value, part: .alert(ruleId: "a1"), occurrence: nil, now: now, calendar: calendar)
        value = ReminderAction.snoozeOneHour.apply(to: value, part: .alert(ruleId: "a2"), occurrence: nil, now: now, calendar: calendar)
        value = ReminderAction.snoozeUntilTomorrow.apply(to: value, part: .slot(time: "11:00"), occurrence: nil, now: now, calendar: calendar)
        XCTAssertEqual(value["snoozes"]?["~a1"], .string(ReminderRecord.formatDate(now.addingTimeInterval(600))))
        XCTAssertEqual(value["snoozes"]?["~a2"], .string(ReminderRecord.formatDate(now.addingTimeInterval(3600))))
        XCTAssertEqual(value["snoozes"]?["@1100"], .string(ReminderRecord.formatDate(date("2026-10-18T09:00:00-07:00"))))
        XCTAssertEqual(value["snoozedUntil"], .string("2026-10-18T13:20:00-07:00"), "a snooze on an alert must not touch the item's own snooze")
        XCTAssertNil(ReminderRecord.validationError(value))
        let record = parse("reminder:d1", value)
        XCTAssertEqual(record.snoozes.count, 3)
    }

    func testDoneOnTheEventRemovesTheAlertsSnoozesAndKeepsTheTimesAndDoneOnATimeRemovesOnlyItsOwn() {
        let now = date("2026-10-18T13:05:00-07:00")
        let occurrence = date("2026-10-18T13:00:00-07:00")
        let snoozes: [String: JSONValue] = ["~a1": .string("2026-10-17T18:10:00.000Z"), "~a2": .string("2026-10-18T08:10:00.000Z"), "@1100": .string("2026-10-18T11:10:00.000Z")]
        let value = dentistValue(snoozes: snoozes, snoozedUntil: "2026-10-18T13:20:00.000Z")

        let doneOnAlert = ReminderChange.donePatch(for: value, part: .alert(ruleId: "a1"), occurrence: occurrence, now: now)
        XCTAssertEqual(doneOnAlert["snoozes"], .object(["~a1": .null, "~a2": .null]))
        XCTAssertEqual(doneOnAlert["snoozedUntil"], .null)
        let afterAlertDone = JSONMergePatch.apply(doneOnAlert, to: value)
        XCTAssertEqual(afterAlertDone["snoozes"], .object(["@1100": .string("2026-10-18T11:10:00.000Z")]), "the time's own snooze must stay")
        XCTAssertEqual(ReminderChange.donePatch(for: value, part: .item, occurrence: occurrence, now: now), doneOnAlert, "Done on the item and on an alert is one change")

        let doneOnTime = ReminderChange.donePatch(for: value, part: .slot(time: "11:00"), occurrence: occurrence, now: now)
        XCTAssertEqual(doneOnTime["snoozes"], .object(["@1100": .null]))
        XCTAssertNil(doneOnTime["snoozedUntil"], "Done on a time must not clear the item's snooze")
        let afterTimeDone = JSONMergePatch.apply(doneOnTime, to: value)
        XCTAssertEqual(afterTimeDone["snoozes"]?["~a1"], .string("2026-10-17T18:10:00.000Z"))
        XCTAssertEqual(afterTimeDone["snoozedUntil"], .string("2026-10-18T13:20:00.000Z"))
    }

    func testDoneRemovesTheWholeFieldWhenNoSnoozeStaysAndNamesNothingWhenThereAreNone() {
        let now = date("2026-10-18T13:05:00-07:00")
        let onlyAlerts = dentistValue(snoozes: ["~a1": .string("2026-10-17T18:10:00.000Z")])
        let patch = ReminderChange.donePatch(for: onlyAlerts, part: .item, occurrence: nil, now: now)
        XCTAssertEqual(patch["snoozes"], .null, "an empty object must not be left behind")
        XCTAssertNil(JSONMergePatch.apply(patch, to: onlyAlerts)["snoozes"])
        let none = ReminderChange.donePatch(for: dentistValue(), part: .item, occurrence: nil, now: now)
        XCTAssertNil(none["snoozes"], "a record without snoozes is not touched there")
        XCTAssertEqual(ReminderChange.donePatch(for: dentistValue(), part: .slot(time: "11:00"), occurrence: nil, now: now),
                       .object(["slotsDone": .object(["11:00": .string(ReminderRecord.formatDate(now))])]))
    }

    func testTheRecordCheckRefusesASnoozeThatIsNotADate() {
        let bad = dentistValue(snoozes: ["~a1": .string("someday")])
        XCTAssertEqual(ReminderRecord.validationError(bad), "reminder.snoozes.~a1 must be a date")
        XCTAssertEqual(ReminderRecord.validationError(.object(["title": .string("x"), "snoozes": .string("no")])), "reminder.snoozes must be an object")
    }

    // MARK: Expansion and planner

    func testAnAlertCarriesItsOwnSnoozeIntoTheExpansionAndTheOthersCarryNone() {
        let now = date("2026-10-15T12:00:00-07:00")
        let value = dentistValue(snoozes: ["~a1": .string("2026-10-17T18:10:00-07:00")], snoozedUntil: "2026-10-18T13:20:00-07:00")
        let expanded = expansion.expand(parse("reminder:d1", value), now: now)
        XCTAssertEqual(expanded.map(\.identity.reminderId), ["d1", "d1~a1", "d1~a2", "d1~a3"])
        XCTAssertEqual(expanded[0].snoozedUntil, date("2026-10-18T13:20:00-07:00"))
        XCTAssertEqual(expanded[1].snoozedUntil, date("2026-10-17T18:10:00-07:00"))
        XCTAssertEqual(expanded[1].at, date("2026-10-17T18:00:00-07:00"), "an alert still ahead keeps its own moment")
        XCTAssertEqual(expanded[1].title, dayBeforeWording)
        XCTAssertNil(expanded[2].snoozedUntil)
        XCTAssertNil(expanded[3].snoozedUntil)
    }

    func testTheSnoozedNotificationOfAnAlertCarriesTheAlertsWordingNotTheItemsTitle() {
        let now = date("2026-10-15T12:00:00-07:00")
        let value = dentistValue(snoozes: ["~a1": .string("2026-10-17T18:10:00-07:00")])
        let records = expansion.expand(parse("reminder:d1", value), now: now)
        let planner = ReminderPlanner(schedule: ReminderSchedule(calendar: calendar))
        let plan = planner.plan(records: records, ledger: [:], previousBookings: [], now: now)
        var snoozeBookings: [PlannedBooking] = []
        for booking in plan.bookings where booking.kind == .snooze {
            snoozeBookings.append(booking)
        }
        XCTAssertEqual(snoozeBookings.count, 1)
        XCTAssertEqual(snoozeBookings.first?.title, dayBeforeWording)
        XCTAssertEqual(snoozeBookings.first?.identity.reminderId, "d1~a1")
        XCTAssertEqual(snoozeBookings.first?.fireDate, date("2026-10-17T18:10:00-07:00"))
    }

    func testAnAlertThatFiredAndWasSnoozedComesBackOnceAtTheSnoozeTimeWithItsOwnText() {
        let now = date("2026-10-17T18:05:00-07:00")
        let snoozed = dentistValue(snoozes: ["~a1": .string("2026-10-17T18:15:00-07:00")])
        let expanded = expansion.expand(parse("reminder:d1", snoozed), now: now)
        XCTAssertEqual(expanded.map(\.identity.reminderId), ["d1", "d1~a1", "d1~a2", "d1~a3"])
        XCTAssertEqual(expanded[1].at, date("2026-10-17T18:15:00-07:00"), "a fired alert comes back at the snooze time as its own moment")
        XCTAssertNil(expanded[1].snoozedUntil)
        XCTAssertEqual(expanded[1].title, dayBeforeWording)

        let planner = ReminderPlanner(schedule: ReminderSchedule(calendar: calendar))
        let plan = planner.plan(records: expanded, ledger: [:], previousBookings: [], now: now)
        var alertBookings: [PlannedBooking] = []
        for booking in plan.bookings where booking.identity.reminderId == "d1~a1" {
            alertBookings.append(booking)
        }
        XCTAssertEqual(alertBookings.count, 1, "exactly one notification for the snoozed alert, no missed one")
        XCTAssertEqual(alertBookings.first?.fireDate, date("2026-10-17T18:15:00-07:00"))

        // Without a pending snooze a fired alert is gone, as before.
        let plain = expansion.expand(parse("reminder:d1", dentistValue()), now: now)
        XCTAssertEqual(plain.map(\.identity.reminderId), ["d1", "d1~a2", "d1~a3"])
        let passed = dentistValue(snoozes: ["~a1": .string("2026-10-17T18:04:00-07:00")])
        XCTAssertEqual(expansion.expand(parse("reminder:d1", passed), now: now).map(\.identity.reminderId), ["d1", "d1~a2", "d1~a3"], "a snooze already past brings nothing back")
    }

    func testAnHourlyTimeCarriesItsOwnSnoozeInTheExpansionAndInTheWidgetsRecords() {
        let value: JSONValue = .object([
            "title": .string("Pills"), "at": .string("2026-10-12T08:00:00-07:00"), "timeZone": .string(zone.identifier),
            "repeat": .object(["every": .string("day")]), "everyHours": .number(3),
            "snoozes": .object(["@1100": .string("2026-10-15T11:10:00-07:00")]), "snoozedUntil": .string("2026-10-15T08:10:00-07:00"),
        ])
        let record = parse("reminder:p1", value)
        let slots = expansion.hourlySlots(of: record)
        XCTAssertEqual(slots.first?.identity.reminderId, "p1@1100")
        XCTAssertEqual(slots.first?.snoozedUntil, date("2026-10-15T11:10:00-07:00"))
        XCTAssertEqual(slots.first?.title, "Pills", "an hourly time's own wording is the item's title")
        XCTAssertNil(slots[1].snoozedUntil, "the 14:00 time was not snoozed")

        let stored = LocalRecord(sidekickId: "care-reminders", key: "reminder:p1", value: value)
        let widgetRecords = expansion.slotRecords(of: stored)
        let eleven = widgetRecords.first { $0.key == "reminder:p1@1100" }
        XCTAssertEqual(eleven?.value["snoozedUntil"], .string(ReminderRecord.formatDate(date("2026-10-15T11:10:00-07:00"))))
        XCTAssertNil(eleven?.value["snoozes"])
        let fourteen = widgetRecords.first { $0.key == "reminder:p1@1400" }
        XCTAssertNil(fourteen?.value["snoozedUntil"], "the item's own snooze must not leak onto its times")
    }

    // MARK: Engine, end to end

    func testTwoSnoozesArePendingAtOnceEachWithItsOwnText() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appending(path: "snooze-engine-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let store = LocalRecordStore(fileURL: temporaryDirectory.appending(path: "records.json"))
        let fakeBooking = SnoozeFakeBooking()
        let clock = SnoozeTestClock(now: date("2026-10-17T17:00:00-07:00"))
        let phoneCalendar = calendar
        func fixedCalendar() -> Calendar {
            phoneCalendar
        }
        let engine = NotificationEngine(store: store, booking: fakeBooking, stateFileURL: temporaryDirectory.appending(path: "engine.json"),
                                        calendarProvider: fixedCalendar, clock: clock.currentTime)
        try store.set(sidekickId: "care-reminders", key: "reminder:d1", value: dentistValue())
        await engine.refresh()
        XCTAssertTrue(fakeBooking.pendingTitles().contains(dayBeforeWording), "the day-before alert is booked: \(fakeBooking.pendingTitles())")

        // The day-before alert fires at 18:00; the user snoozes it at 18:05.
        clock.now = date("2026-10-17T18:05:00-07:00")
        fakeBooking.deliverDue(now: clock.now)
        await engine.handle(action: .snoozeTenMinutes, for: ReminderIdentity(sidekickId: "care-reminders", reminderId: "d1~a1"))
        let afterAlertSnooze = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: "reminder:d1"))
        XCTAssertEqual(afterAlertSnooze["snoozes"]?["~a1"], .string(ReminderRecord.formatDate(date("2026-10-17T18:15:00-07:00"))))
        XCTAssertNil(afterAlertSnooze["snoozedUntil"], "the alert's snooze must not become the item's")
        XCTAssertTrue(fakeBooking.pendingTitles().contains(dayBeforeWording), "the snoozed alert comes back with its own text: \(fakeBooking.pendingTitles())")

        // The user also snoozes the item itself (from the Sidekick, say): both are pending.
        await engine.handle(action: .snoozeOneHour, for: ReminderIdentity(sidekickId: "care-reminders", reminderId: "d1"))
        let afterItemSnooze = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: "reminder:d1"))
        XCTAssertEqual(afterItemSnooze["snoozes"]?["~a1"], afterAlertSnooze["snoozes"]?["~a1"], "the item's snooze must not replace the alert's")
        XCTAssertNotNil(afterItemSnooze["snoozedUntil"])
        var pendingByReminder: [String: [PlannedBooking]] = [:]
        for booking in fakeBooking.pending.values {
            pendingByReminder[booking.identity.reminderId, default: []].append(booking)
        }
        let alertComeback = pendingByReminder["d1~a1"]?.first { $0.fireDate == date("2026-10-17T18:15:00-07:00") }
        XCTAssertEqual(alertComeback?.title, dayBeforeWording)
        let itemComeback = pendingByReminder["d1"]?.first { $0.kind == .snooze }
        XCTAssertEqual(itemComeback?.title, "Dentist")
        XCTAssertEqual(itemComeback?.fireDate, date("2026-10-17T19:05:00-07:00"))

        // Done on the alert completes the event and clears every snooze for it.
        await engine.handle(action: .done, for: ReminderIdentity(sidekickId: "care-reminders", reminderId: "d1~a1"))
        let afterDone = try XCTUnwrap(store.get(sidekickId: "care-reminders", key: "reminder:d1"))
        XCTAssertEqual(afterDone["done"], .bool(true))
        XCTAssertNil(afterDone["snoozes"])
        XCTAssertNil(afterDone["snoozedUntil"])
        XCTAssertTrue(fakeBooking.pending.isEmpty, "nothing is left to fire: \(fakeBooking.pendingTitles())")
    }
}
