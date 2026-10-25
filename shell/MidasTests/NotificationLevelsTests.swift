import UserNotifications
import XCTest
@testable import Midas

// Founder decisions 2026-10-24 (docs/briefs/notification-levels.md, after repair 3365bd8a "Even
// though they are time they don't come under time sensitive"): layout A (title the reminder,
// subtitle the Sidekick's name, body the time then the notes), `reminderType` normal /
// timeSensitive / alarm with absent = Time Sensitive, alarms through AlarmKit outside the 48
// bookings, the countdown card after Snooze with Done and Stop. These tests fail if any of that
// stops holding.

/// Stands in for iOS's notification center.
@MainActor
private final class LevelsFakeNotificationBooking: NotificationBooking {
    var authorizationRequests = 0
    var pending: [String: PlannedBooking] = [:]

    func requestAuthorizationIfNeeded() async -> Bool {
        authorizationRequests += 1
        return true
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

    func pendingBookings() -> [PlannedBooking] {
        Array(pending.values)
    }
}

/// Stands in for AlarmKit: holds alarms by id, each in a state.
@MainActor
private final class FakeAlarmBooking: AlarmBooking {
    var authorizationAnswer = true
    var authorizationRequests = 0
    var held: [UUID: HeldAlarmState] = [:]
    var bookingsById: [UUID: PlannedBooking] = [:]
    var bookedIdentifiers: [String] = []
    var cancelledIds: [UUID] = []
    var stoppedIds: [UUID] = []
    var countdownIds: [UUID] = []

    func requestAuthorizationIfNeeded() async -> Bool {
        authorizationRequests += 1
        return authorizationAnswer
    }

    func heldAlarms() async -> [UUID: HeldAlarmState] {
        held
    }

    func book(_ booking: PlannedBooking) async throws {
        let alarmId = AlarmIdentifier.uuid(for: booking.identifier)
        bookedIdentifiers.append(booking.identifier)
        bookingsById[alarmId] = booking
        held[alarmId] = .scheduled
    }

    func cancel(alarmIds: [UUID]) {
        cancelledIds.append(contentsOf: alarmIds)
        for alarmId in alarmIds {
            held.removeValue(forKey: alarmId)
            bookingsById.removeValue(forKey: alarmId)
        }
    }

    /// A one-time alarm is gone once stopped; a weekly one waits for its next time.
    func stop(alarmIds: [UUID]) {
        stoppedIds.append(contentsOf: alarmIds)
        for alarmId in alarmIds {
            if bookingsById[alarmId]?.kind == .repeating {
                held[alarmId] = .scheduled
            } else {
                held.removeValue(forKey: alarmId)
                bookingsById.removeValue(forKey: alarmId)
            }
        }
    }

    func startCountdown(alarmIds: [UUID]) {
        countdownIds.append(contentsOf: alarmIds)
        for alarmId in alarmIds {
            held[alarmId] = .countingDown
        }
    }

    func heldBookings() -> [PlannedBooking] {
        var bookings: [PlannedBooking] = []
        for (alarmId, booking) in bookingsById where held[alarmId] != nil {
            bookings.append(booking)
        }
        return bookings
    }
}

@MainActor
private final class LevelsClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func currentTime() -> Date {
        now
    }
}

// MARK: - The record field

final class ReminderTypeFieldTests: XCTestCase {
    private func parsed(_ fields: [String: JSONValue]) -> ReminderRecord? {
        var allFields = fields
        allFields["title"] = .string("Gratitude")
        allFields["at"] = .string("2026-10-24T23:00:00-07:00")
        return ReminderRecord.parse(sidekickId: "reminders", key: "reminder:g1", value: .object(allFields))
    }

    func testAbsentReminderTypeIsTimeSensitive() {
        XCTAssertEqual(parsed([:])?.reminderType, .timeSensitive, "records saved before 2026-10-24 are Time Sensitive")
    }

    func testEachReminderTypeIsRead() {
        XCTAssertEqual(parsed(["reminderType": .string("normal")])?.reminderType, .normal)
        XCTAssertEqual(parsed(["reminderType": .string("timeSensitive")])?.reminderType, .timeSensitive)
        XCTAssertEqual(parsed(["reminderType": .string("alarm")])?.reminderType, .alarm)
    }

    func testABadReminderTypeIsRefusedWithItsReason() {
        let reason = "reminder.reminderType must be normal, timeSensitive or alarm"
        let loud: JSONValue = .object(["title": .string("x"), "reminderType": .string("loud")])
        let number: JSONValue = .object(["title": .string("x"), "reminderType": .number(2)])
        let capitalised: JSONValue = .object(["title": .string("x"), "reminderType": .string("Alarm")])
        XCTAssertEqual(ReminderRecord.validationError(loud), reason)
        XCTAssertEqual(ReminderRecord.validationError(number), reason)
        XCTAssertEqual(ReminderRecord.validationError(capitalised), reason)
        XCTAssertNil(ReminderRecord.validationError(.object(["title": .string("x"), "reminderType": .string("alarm")])))
        XCTAssertNil(parsed(["reminderType": .string("loud")]), "a bad value is not booked")
    }

    @MainActor
    func testTheStoreRefusesABadReminderTypeAtWriteTime() throws {
        let validator = try XCTUnwrap(ShellServices.reservedRecordValidators[ReminderRecord.keyPrefix])
        let refused: JSONValue = .object(["title": .string("x"), "reminderType": .string("critical")])
        XCTAssertEqual(validator(refused), "reminder.reminderType must be normal, timeSensitive or alarm")
    }
}

// MARK: - The planner: levels, subtitle, body

final class NotificationLevelsPlannerTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private var calendar: Calendar {
        ReminderSchedule.phoneCalendar(timeZone: zone)
    }
    private var schedule: ReminderSchedule {
        ReminderSchedule(calendar: calendar)
    }
    private var expansion: ReminderExpansion {
        ReminderExpansion(schedule: schedule)
    }
    private var planner: ReminderPlanner {
        ReminderPlanner(schedule: schedule)
    }
    private let now = ReminderRecord.parseDate(.string("2026-10-24T12:00:00-07:00"))!
    private let names = ["reminders": "Reminders", "care-reminders": "Care"]

    private func record(_ id: String, sidekickId: String = "reminders", _ fields: [String: JSONValue]) -> ReminderRecord {
        var allFields = fields
        allFields["timeZone"] = .string(zone.identifier)
        if allFields["title"] == nil {
            allFields["title"] = .string(id)
        }
        return ReminderRecord.parse(sidekickId: sidekickId, key: "reminder:\(id)", value: .object(allFields))!
    }

    private func plan(_ records: [ReminderRecord], alarmsAllowed: Bool = false) -> ReminderPlan {
        var expanded: [ReminderRecord] = []
        for stored in records {
            expanded.append(contentsOf: expansion.expand(stored, now: now))
        }
        return planner.plan(records: expanded, ledger: [:], previousBookings: [], now: now, sidekickNames: names, alarmsAllowed: alarmsAllowed)
    }

    private func bookings(of plan: ReminderPlan, reminderId: String) -> [PlannedBooking] {
        var found: [PlannedBooking] = []
        for booking in plan.bookings where booking.identity.reminderId == reminderId {
            found.append(booking)
        }
        return found
    }

    private let twoAlerts: JSONValue = .array([
        .object(["id": .string("a1"), "kind": .string("daysBefore"), "days": .number(1), "time": .string("18:00")]),
        .object(["id": .string("a2"), "kind": .string("before"), "minutes": .number(30)]),
    ])

    func testLevelsFollowTheReminderType() {
        let normal = record("n1", ["at": .string("2026-10-25T09:00:00-07:00"), "reminderType": .string("normal")])
        let sensitive = record("t1", ["at": .string("2026-10-25T09:00:00-07:00"), "reminderType": .string("timeSensitive")])
        let unset = record("u1", ["at": .string("2026-10-25T09:00:00-07:00")])
        let result = plan([normal, sensitive, unset])
        XCTAssertEqual(bookings(of: result, reminderId: "n1").first?.level, .active)
        XCTAssertEqual(bookings(of: result, reminderId: "t1").first?.level, .timeSensitive)
        XCTAssertEqual(bookings(of: result, reminderId: "u1").first?.level, .timeSensitive, "absent is Time Sensitive")
    }

    func testEveryNotificationAnItemMakesHasTheSidekickNameAsSubtitle() {
        let dentist = record("d1", sidekickId: "care-reminders", [
            "at": .string("2026-10-27T13:00:00-07:00"), "alerts": twoAlerts, "snoozedUntil": .string("2026-10-24T12:30:00-07:00"),
        ])
        let pills = record("p1", sidekickId: "care-reminders", [
            "at": .string("2026-10-25T08:00:00-07:00"), "repeat": .object(["every": .string("day")]), "everyHours": .number(4),
        ])
        let missed = record("m1", ["at": .string("2026-10-24T10:00:00-07:00")])
        let result = plan([dentist, pills, missed])
        var kinds: Set<BookingKind> = []
        var reminderIds: Set<String> = []
        for booking in result.bookings {
            let expected = booking.identity.sidekickId == "care-reminders" ? "Care" : "Reminders"
            XCTAssertEqual(booking.subtitle, expected, "\(booking.identifier) has no Sidekick name")
            kinds.insert(booking.kind)
            reminderIds.insert(booking.identity.reminderId)
        }
        XCTAssertEqual(kinds, [.occurrence, .snooze, .repeating, .missed], "own, snooze, hourly times and missed are all checked")
        XCTAssertTrue(reminderIds.contains("d1~a1") && reminderIds.contains("d1~a2"), "early alerts are checked")
        XCTAssertTrue(reminderIds.contains("p1@1200"), "hourly times are checked")
    }

    func testASidekickWithoutANameHasNoSubtitle() {
        let unknown = record("x1", sidekickId: "unlisted", ["at": .string("2026-10-25T09:00:00-07:00")])
        XCTAssertEqual(plan([unknown]).bookings.first?.subtitle, "")
    }

    func testTheBodyIsTheTimeThenTheNotes() throws {
        let at = ReminderRecord.parseDate(.string("2026-10-24T23:00:00-07:00"))!
        let timeText = ReminderExpansion.formatTime(at, zone: zone)
        let gratitude = record("g1", ["title": .string("Gratitude"), "at": .string("2026-10-24T23:00:00-07:00")])
        let dentist = record("d1", ["title": .string("Dentist"), "notes": .string("Bring the insurance card"), "at": .string("2026-10-24T23:00:00-07:00")])
        let result = plan([gratitude, dentist])
        let gratitudeBooking = try XCTUnwrap(bookings(of: result, reminderId: "g1").first)
        let dentistBooking = try XCTUnwrap(bookings(of: result, reminderId: "d1").first)
        XCTAssertEqual(gratitudeBooking.notificationBody, timeText, "no notes: the time alone, so the card has two lines")
        XCTAssertEqual(dentistBooking.notificationBody, timeText + " · Bring the insurance card")
        XCTAssertEqual(dentistBooking.body, "Bring the insurance card", "the notes stay the notes")
    }

    func testASnoozeShowsTheTimeTheReminderWasFor() throws {
        let at = ReminderRecord.parseDate(.string("2026-10-24T11:00:00-07:00"))!
        let walk = record("w1", ["at": .string("2026-10-24T11:00:00-07:00"), "repeat": .object(["every": .string("day")]),
                                 "snoozedUntil": .string("2026-10-24T12:10:00-07:00")])
        var snooze: PlannedBooking?
        for booking in plan([walk]).bookings where booking.kind == .snooze {
            snooze = booking
        }
        XCTAssertEqual(try XCTUnwrap(snooze).timeText, ReminderExpansion.formatTime(at, zone: zone))
    }

    func testTheNotificationCarriesLayoutAAndItsLevel() throws {
        let call = record("c1", ["title": .string("Call Amma"), "notes": .string("Say hi"), "at": .string("2026-10-24T18:00:00-07:00"),
                                 "reminderType": .string("normal")])
        let gym = record("y1", ["title": .string("Gym"), "at": .string("2026-10-24T18:00:00-07:00")])
        let result = plan([call, gym])
        let callContent = UserNotificationBooking.content(for: try XCTUnwrap(bookings(of: result, reminderId: "c1").first))
        let gymContent = UserNotificationBooking.content(for: try XCTUnwrap(bookings(of: result, reminderId: "y1").first))
        let sixPM = ReminderExpansion.formatTime(ReminderRecord.parseDate(.string("2026-10-24T18:00:00-07:00"))!, zone: zone)
        XCTAssertEqual(callContent.title, "Call Amma")
        XCTAssertEqual(callContent.subtitle, "Reminders")
        XCTAssertEqual(callContent.body, sixPM + " · Say hi")
        XCTAssertEqual(callContent.interruptionLevel, .active)
        XCTAssertEqual(gymContent.interruptionLevel, .timeSensitive)
        XCTAssertEqual(gymContent.body, sixPM)
    }

    func testEarlyAlertsSnoozesAndHourlyTimesKeepTheirReminderLevel() {
        let quiet = record("q1", ["at": .string("2026-10-27T13:00:00-07:00"), "alerts": twoAlerts, "reminderType": .string("normal"),
                                  "snoozedUntil": .string("2026-10-24T12:30:00-07:00")])
        let hourly = record("h1", ["at": .string("2026-10-25T08:00:00-07:00"), "repeat": .object(["every": .string("day")]),
                                   "everyHours": .number(3), "reminderType": .string("normal")])
        let result = plan([quiet, hourly])
        XCTAssertGreaterThan(result.bookings.count, 8)
        for booking in result.bookings {
            XCTAssertEqual(booking.level, .active, "\(booking.identifier) left its reminder's level")
        }
    }

    func testAnAlarmWithoutAlarmKitIsATimeSensitiveNotification() {
        let wake = record("a1", ["at": .string("2026-10-25T06:30:00-07:00"), "reminderType": .string("alarm")])
        let result = plan([wake], alarmsAllowed: false)
        XCTAssertEqual(result.bookings.count, 1)
        XCTAssertEqual(result.bookings.first?.level, .timeSensitive, "declined or before iOS 26")
    }

    func testAnAlarmRingsAndItsEarlyAlertsAreTimeSensitiveNotifications() throws {
        let flight = record("f1", ["at": .string("2026-10-27T13:00:00-07:00"), "alerts": twoAlerts, "reminderType": .string("alarm")])
        let result = plan([flight], alarmsAllowed: true)
        let own = try XCTUnwrap(bookings(of: result, reminderId: "f1").first)
        XCTAssertEqual(own.level, .alarm)
        XCTAssertEqual(own.kind, .occurrence)
        XCTAssertEqual(own.subtitle, "Reminders")
        XCTAssertEqual(bookings(of: result, reminderId: "f1~a1").first?.level, .timeSensitive)
        XCTAssertEqual(bookings(of: result, reminderId: "f1~a2").first?.level, .timeSensitive)
    }

    func testAlarmsDoNotCountAgainstThe48() {
        var records: [ReminderRecord] = []
        for index in 0..<60 {
            let at = now.addingTimeInterval(Double(index + 1) * 60)
            records.append(record(String(format: "r%02d", index), ["at": .string(ReminderRecord.formatDate(at))]))
        }
        // Later than every notification, so a shared budget would leave it out.
        let alarmAt = now.addingTimeInterval(5 * 3600)
        records.append(record("alarm", ["at": .string(ReminderRecord.formatDate(alarmAt)), "reminderType": .string("alarm")]))
        let result = plan(records, alarmsAllowed: true)
        var notificationCount = 0
        var alarmCount = 0
        for booking in result.bookings {
            if booking.level == .alarm {
                alarmCount += 1
            } else {
                notificationCount += 1
            }
        }
        XCTAssertEqual(notificationCount, 48)
        XCTAssertEqual(alarmCount, 1)
    }

    func testDailyAndWeeklyAlarmsUseAlarmKitsOwnSchedule() {
        let daily = record("d1", ["at": .string("2026-10-24T07:00:00-07:00"), "repeat": .object(["every": .string("day")]), "reminderType": .string("alarm")])
        let weekdays = record("w1", ["at": .string("2026-10-26T07:00:00-07:00"), "reminderType": .string("alarm"),
                                     "repeat": .object(["every": .string("week"), "weekdays": .array([.number(1), .number(3), .number(5)])])])
        let result = plan([daily, weekdays], alarmsAllowed: true)
        let dailyAlarms = bookings(of: result, reminderId: "d1")
        let weekdayAlarms = bookings(of: result, reminderId: "w1")
        XCTAssertEqual(dailyAlarms.count, 1)
        XCTAssertEqual(dailyAlarms.first?.kind, .repeating)
        XCTAssertEqual(dailyAlarms.first?.level, .alarm)
        XCTAssertEqual(weekdayAlarms.count, 3)
        for alarm in weekdayAlarms {
            XCTAssertEqual(alarm.kind, .repeating)
            XCTAssertEqual(alarm.level, .alarm)
        }
    }

    func testOtherRepeatsAreOneAlarmForTheNextOccurrence() {
        let everyOtherDay = record("e1", ["at": .string("2026-10-23T07:00:00-07:00"), "reminderType": .string("alarm"),
                                          "repeat": .object(["every": .string("day"), "interval": .number(2)])])
        let monthly = record("m1", ["at": .string("2026-10-05T07:00:00-07:00"), "reminderType": .string("alarm"),
                                    "repeat": .object(["every": .string("month")])])
        let yearly = record("y1", ["at": .string("2027-03-14T09:00:00-07:00"), "reminderType": .string("alarm"),
                                   "repeat": .object(["every": .string("year")])])
        let ending = record("u1", ["at": .string("2026-10-24T07:00:00-07:00"), "reminderType": .string("alarm"),
                                   "repeat": .object(["every": .string("day"), "until": .string("2026-12-31T23:59:59-08:00")])])
        let result = plan([everyOtherDay, monthly, yearly, ending], alarmsAllowed: true)
        let expectedNext: [String: String] = [
            "e1": "2026-10-25T07:00:00-07:00",
            "m1": "2026-11-05T07:00:00-08:00",
            "y1": "2027-03-14T09:00:00-07:00",
            "u1": "2026-10-25T07:00:00-07:00",
        ]
        for (reminderId, nextText) in expectedNext {
            let alarms = bookings(of: result, reminderId: reminderId)
            XCTAssertEqual(alarms.count, 1, "\(reminderId) books one alarm at a time")
            XCTAssertEqual(alarms.first?.kind, .occurrence)
            XCTAssertEqual(alarms.first?.level, .alarm)
            XCTAssertEqual(alarms.first?.fireDate, ReminderRecord.parseDate(.string(nextText)), "\(reminderId) next occurrence")
        }
    }

    func testAnAlarmsMissedNoticeIsTimeSensitive() throws {
        let late = record("l1", ["at": .string("2026-10-24T11:00:00-07:00"), "reminderType": .string("alarm")])
        let result = plan([late], alarmsAllowed: true)
        let missed = try XCTUnwrap(result.bookings.first)
        XCTAssertEqual(missed.kind, .missed)
        XCTAssertEqual(missed.level, .timeSensitive)
    }

    func testAnAlarmsHourlyTimesAreAlarms() {
        let pills = record("p1", ["at": .string("2026-10-25T08:00:00-07:00"), "repeat": .object(["every": .string("day")]),
                                  "everyHours": .number(4), "reminderType": .string("alarm")])
        let result = plan([pills], alarmsAllowed: true)
        XCTAssertEqual(result.bookings.count, 6)
        for booking in result.bookings {
            XCTAssertEqual(booking.level, .alarm, "\(booking.identifier)")
        }
    }

    func testEngineStateSavedBeforeLevelsStillLoads() throws {
        let booking = PlannedBooking(identifier: "reminder|reminders|a|occurrence|1", identity: ReminderIdentity(sidekickId: "reminders", reminderId: "a"),
                                     kind: .occurrence, trigger: .date(now), fireDate: now, occurrence: now, title: "A", body: "",
                                     subtitle: "Reminders", timeText: "12:00 PM", level: .active)
        let state = NotificationEngineState(ledger: ["reminders/a": now], bookings: [booking])
        let encoded = try JSONEncoder().encode(state)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var savedBookings = try XCTUnwrap(object["bookings"] as? [[String: Any]])
        for field in ["subtitle", "timeText", "level"] {
            savedBookings[0].removeValue(forKey: field)
        }
        object["bookings"] = savedBookings
        let oldShape = try JSONSerialization.data(withJSONObject: object)
        let loaded = try JSONDecoder().decode(NotificationEngineState.self, from: oldShape)
        XCTAssertEqual(loaded.ledger, state.ledger, "the ledger survives, so nothing fires twice")
        XCTAssertEqual(loaded.bookings.first?.level, .timeSensitive)
        XCTAssertEqual(loaded.bookings.first?.subtitle, "")
    }
}

// MARK: - The AlarmKit adapter's pieces

final class AlarmKitPiecesTests: XCTestCase {
    func testEachBookingHasItsOwnStableAlarmId() {
        let first = AlarmIdentifier.uuid(for: "reminder|reminders|a|occurrence|1")
        XCTAssertEqual(first, AlarmIdentifier.uuid(for: "reminder|reminders|a|occurrence|1"))
        XCTAssertNotEqual(first, AlarmIdentifier.uuid(for: "reminder|reminders|a|occurrence|2"))
    }

    func testAlarmSchedules() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit is iOS 26")
        }
        let identity = ReminderIdentity(sidekickId: "reminders", reminderId: "a")
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let once = PlannedBooking(identifier: "x", identity: identity, kind: .occurrence, trigger: .date(moment), fireDate: moment,
                                  occurrence: moment, title: "A", body: "", level: .alarm)
        XCTAssertEqual(AlarmKitBooking.schedule(for: once), .fixed(moment))
        let daily = PlannedBooking(identifier: "y", identity: identity, kind: .repeating, trigger: .repeating(DateComponents(hour: 7, minute: 30, second: 0)),
                                   fireDate: moment, occurrence: nil, title: "A", body: "", level: .alarm)
        let everyDay: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        XCTAssertEqual(AlarmKitBooking.schedule(for: daily), .relative(.init(time: .init(hour: 7, minute: 30), repeats: .weekly(everyDay))))
        let monday = PlannedBooking(identifier: "z", identity: identity, kind: .repeating, trigger: .repeating(DateComponents(hour: 8, minute: 0, second: 0, weekday: 2)),
                                    fireDate: moment, occurrence: nil, title: "A", body: "", level: .alarm)
        XCTAssertEqual(AlarmKitBooking.schedule(for: monday), .relative(.init(time: .init(hour: 8, minute: 0), repeats: .weekly([.monday]))))
    }

    func testTheCountdownCardsWords() {
        let usLocale = Locale(identifier: "en_US")
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let ringsAt = ReminderRecord.parseDate(.string("2026-10-24T23:09:00-07:00"))!
        let withName = AlarmCountdownCopy.subline(sidekickName: "Reminders", ringsAt: ringsAt, timeZone: losAngeles, locale: usLocale)
        let withoutName = AlarmCountdownCopy.subline(sidekickName: "", ringsAt: ringsAt, timeZone: losAngeles, locale: usLocale)
        XCTAssertEqual(withName.replacingOccurrences(of: "\u{202F}", with: " "), "Reminders · rings again at 11:09 PM")
        XCTAssertEqual(withoutName.replacingOccurrences(of: "\u{202F}", with: " "), "Rings again at 11:09 PM")
        XCTAssertEqual(AlarmCountdownCopy.remainingText(seconds: 539), "8:59")
        XCTAssertEqual(AlarmReminderShared.snoozeSeconds, 9 * 60, "9 minutes, as the mockup's 11:00 to 11:09")
    }
}

// MARK: - The engine with AlarmKit

@MainActor
final class NotificationLevelsEngineTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let startTime = ReminderRecord.parseDate(.string("2026-10-24T12:00:00-07:00"))!
    private var temporaryDirectory: URL!
    private var store: LocalRecordStore!
    private var notifications: LevelsFakeNotificationBooking!
    private var alarms: FakeAlarmBooking!
    private var clock: LevelsClock!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(path: "levels-\(UUID().uuidString)")
        store = LocalRecordStore(fileURL: temporaryDirectory.appending(path: "records.json"))
        notifications = LevelsFakeNotificationBooking()
        alarms = FakeAlarmBooking()
        clock = LevelsClock(now: startTime)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try await super.tearDown()
    }

    private func makeEngine(withAlarms: Bool = true) -> NotificationEngine {
        let phoneCalendar = ReminderSchedule.phoneCalendar(timeZone: losAngeles)
        func fixedCalendar() -> Calendar {
            phoneCalendar
        }
        func names() -> [String: String] {
            ["reminders": "Reminders"]
        }
        return NotificationEngine(store: store, booking: notifications, stateFileURL: temporaryDirectory.appending(path: "engine.json"),
                                  calendarProvider: fixedCalendar, clock: clock.currentTime, alarms: withAlarms ? alarms : nil, sidekickNames: names)
    }

    private func writeReminder(_ reminderId: String, minutesFromStart: Double, type: String?, title: String? = nil) throws {
        var fields: [String: JSONValue] = [
            "at": .string(ReminderRecord.formatDate(startTime.addingTimeInterval(minutesFromStart * 60))),
            "title": .string(title ?? reminderId),
        ]
        if let type {
            fields["reminderType"] = .string(type)
        }
        try store.set(sidekickId: "reminders", key: "reminder:\(reminderId)", value: .object(fields))
    }

    private func onlyAlarmId() throws -> UUID {
        XCTAssertEqual(alarms.held.count, 1)
        return try XCTUnwrap(alarms.held.keys.first)
    }

    func testTheSubtitleIsTheSidekicksName() async throws {
        try writeReminder("a", minutesFromStart: 5, type: nil)
        await makeEngine().refresh()
        XCTAssertEqual(notifications.pendingBookings().first?.subtitle, "Reminders")
        XCTAssertEqual(notifications.pendingBookings().first?.level, .timeSensitive)
    }

    func testAnAlarmReminderIsBookedWithAlarmKitNotAsANotification() async throws {
        try writeReminder("wake", minutesFromStart: 60, type: "alarm", title: "Wake up")
        await makeEngine().refresh()
        XCTAssertEqual(alarms.heldBookings().count, 1)
        XCTAssertEqual(alarms.heldBookings().first?.title, "Wake up")
        XCTAssertEqual(alarms.heldBookings().first?.subtitle, "Reminders")
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(notifications.authorizationRequests, 0, "no notification prompt for an alarm alone")
        XCTAssertEqual(alarms.authorizationRequests, 1)
    }

    func testAlarmPermissionIsNotAskedWithoutAnAlarmReminder() async throws {
        try writeReminder("a", minutesFromStart: 5, type: "timeSensitive")
        try writeReminder("b", minutesFromStart: 5, type: "normal")
        await makeEngine().refresh()
        XCTAssertEqual(alarms.authorizationRequests, 0)
        XCTAssertEqual(notifications.pending.count, 2)
    }

    func testDeclinedAlarmsArriveAsTimeSensitiveNotifications() async throws {
        alarms.authorizationAnswer = false
        try writeReminder("wake", minutesFromStart: 60, type: "alarm")
        await makeEngine().refresh()
        XCTAssertTrue(alarms.held.isEmpty)
        XCTAssertEqual(notifications.pendingBookings().count, 1)
        XCTAssertEqual(notifications.pendingBookings().first?.level, .timeSensitive)
    }

    func testWithoutAlarmKitAlarmsArriveAsTimeSensitiveNotifications() async throws {
        try writeReminder("wake", minutesFromStart: 60, type: "alarm")
        await makeEngine(withAlarms: false).refresh()
        XCTAssertEqual(notifications.pendingBookings().first?.level, .timeSensitive)
    }

    func testAnUnchangedAlarmIsNotBookedAgainAndAnEditReplacesIt() async throws {
        try writeReminder("wake", minutesFromStart: 60, type: "alarm", title: "Wake up")
        let engine = makeEngine()
        await engine.refresh()
        await engine.refresh()
        XCTAssertEqual(alarms.bookedIdentifiers.count, 1)
        try writeReminder("wake", minutesFromStart: 60, type: "alarm", title: "Get up")
        await engine.refresh()
        XCTAssertEqual(alarms.bookedIdentifiers.count, 2)
        XCTAssertEqual(alarms.heldBookings().first?.title, "Get up")
    }

    func testChangingAnAlarmToNormalCancelsTheAlarm() async throws {
        try writeReminder("wake", minutesFromStart: 60, type: "alarm")
        let engine = makeEngine()
        await engine.refresh()
        let alarmId = try onlyAlarmId()
        try writeReminder("wake", minutesFromStart: 60, type: "normal")
        await engine.refresh()
        XCTAssertTrue(alarms.cancelledIds.contains(alarmId))
        XCTAssertTrue(alarms.held.isEmpty)
        XCTAssertEqual(notifications.pendingBookings().first?.level, .active)
    }

    func testDeletingAnAlarmReminderCancelsTheAlarm() async throws {
        try writeReminder("wake", minutesFromStart: 60, type: "alarm")
        let engine = makeEngine()
        await engine.refresh()
        try store.delete(sidekickId: "reminders", key: "reminder:wake")
        await engine.refresh()
        XCTAssertTrue(alarms.held.isEmpty)
    }

    /// The alarm rings at +1 min; the person taps Snooze at +2 min.
    private func ringAndSnooze(_ engine: NotificationEngine) async throws -> UUID {
        try writeReminder("wake", minutesFromStart: 1, type: "alarm")
        await engine.refresh()
        let alarmId = try onlyAlarmId()
        clock.now = startTime.addingTimeInterval(2 * 60)
        alarms.held[alarmId] = .alerting
        await engine.refresh()
        XCTAssertEqual(alarms.held[alarmId], .alerting, "a ringing alarm is left alone")
        await engine.handleAlarm(button: .snooze, for: ReminderIdentity(sidekickId: "reminders", reminderId: "wake"), alarmId: alarmId)
        return alarmId
    }

    func testSnoozeStartsTheCountdownAndWritesTheSnooze() async throws {
        let engine = makeEngine()
        let alarmId = try await ringAndSnooze(engine)
        XCTAssertEqual(alarms.countdownIds, [alarmId])
        XCTAssertEqual(alarms.held[alarmId], .countingDown, "the countdown card stays")
        let stored = store.get(sidekickId: "reminders", key: "reminder:wake")
        let snoozedUntil = try XCTUnwrap(ReminderRecord.parseDate(stored?["snoozedUntil"]))
        XCTAssertEqual(snoozedUntil.timeIntervalSince1970, clock.now.addingTimeInterval(9 * 60).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(alarms.bookedIdentifiers.count, 1, "the countdown rings again; no second alarm")
        XCTAssertTrue(notifications.pending.isEmpty, "and no snooze notification")
        await engine.refresh()
        XCTAssertEqual(alarms.held[alarmId], .countingDown, "a later run keeps the countdown")
        XCTAssertEqual(alarms.bookedIdentifiers.count, 1)
    }

    func testDoneOnTheCountdownCardCompletesTheReminderAndEndsTheCountdown() async throws {
        let engine = makeEngine()
        let alarmId = try await ringAndSnooze(engine)
        await engine.handleAlarm(button: .done, for: ReminderIdentity(sidekickId: "reminders", reminderId: "wake"), alarmId: alarmId)
        let stored = store.get(sidekickId: "reminders", key: "reminder:wake")
        XCTAssertEqual(stored?["done"], .bool(true))
        XCTAssertNil(stored?["snoozedUntil"])
        XCTAssertTrue(alarms.stoppedIds.contains(alarmId))
        XCTAssertTrue(alarms.held.isEmpty)
    }

    func testStopOnTheCountdownCardRemovesTheSnoozeAndNothingElse() async throws {
        let engine = makeEngine()
        let alarmId = try await ringAndSnooze(engine)
        await engine.handleAlarm(button: .stop, for: ReminderIdentity(sidekickId: "reminders", reminderId: "wake"), alarmId: alarmId)
        let stored = store.get(sidekickId: "reminders", key: "reminder:wake")
        XCTAssertNil(stored?["snoozedUntil"], "it does not ring again")
        XCTAssertNil(stored?["done"], "Stop is not Done")
        XCTAssertTrue(alarms.held.isEmpty)
        XCTAssertTrue(notifications.pending.isEmpty)
    }

    func testDoneFromThePageDuringTheCountdownEndsIt() async throws {
        let engine = makeEngine()
        let alarmId = try await ringAndSnooze(engine)
        let current = try XCTUnwrap(store.get(sidekickId: "reminders", key: "reminder:wake"))
        let donePatch = ReminderChange.donePatch(for: current, part: .item, occurrence: nil, now: clock.now)
        try RecordWriter(store: store).update(sidekickId: "reminders", key: "reminder:wake", patch: donePatch)
        await engine.refresh()
        XCTAssertTrue(alarms.cancelledIds.contains(alarmId) || alarms.stoppedIds.contains(alarmId))
        XCTAssertTrue(alarms.held.isEmpty)
    }

    func testDoneOnADailyAlarmsCountdownKeepsTheDailyAlarm() async throws {
        try store.set(sidekickId: "reminders", key: "reminder:daily", value: .object([
            "at": .string(ReminderRecord.formatDate(startTime.addingTimeInterval(-3600))), "title": .string("Pills"),
            "repeat": .object(["every": .string("day")]), "reminderType": .string("alarm"),
        ]))
        let engine = makeEngine()
        await engine.refresh()
        let alarmId = try onlyAlarmId()
        XCTAssertEqual(alarms.heldBookings().first?.kind, .repeating)
        let identity = ReminderIdentity(sidekickId: "reminders", reminderId: "daily")
        await engine.handleAlarm(button: .snooze, for: identity, alarmId: alarmId)
        XCTAssertEqual(alarms.held[alarmId], .countingDown)
        await engine.handleAlarm(button: .done, for: identity, alarmId: alarmId)
        XCTAssertEqual(alarms.held[alarmId], .scheduled, "tomorrow's alarm stays")
        XCTAssertNotNil(store.get(sidekickId: "reminders", key: "reminder:daily")?["lastDoneAt"])
    }

    func testAnAlarmsEarlyAlertIsATimeSensitiveNotification() async throws {
        try store.set(sidekickId: "reminders", key: "reminder:flight", value: .object([
            "at": .string(ReminderRecord.formatDate(startTime.addingTimeInterval(3 * 3600))), "title": .string("Flight"),
            "reminderType": .string("alarm"),
            "alerts": .array([.object(["id": .string("a1"), "kind": .string("before"), "minutes": .number(60)])]),
        ]))
        await makeEngine().refresh()
        XCTAssertEqual(alarms.heldBookings().count, 1)
        XCTAssertEqual(notifications.pendingBookings().count, 1)
        XCTAssertEqual(notifications.pendingBookings().first?.identity.reminderId, "flight~a1")
        XCTAssertEqual(notifications.pendingBookings().first?.level, .timeSensitive)
    }
}

// MARK: - App configuration

final class NotificationLevelsConfigTests: XCTestCase {
    private var shellFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testInfoPlistAsksForAlarmsInOneActiveSentence() {
        let alarmText = Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") as? String
        XCTAssertEqual(alarmText, "Midas rings your alarm reminders even when your iPhone is on silent or in Focus.")
    }

    func testInfoPlistAllowsTheCountdownCard() {
        let supportsLiveActivities = Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool
        XCTAssertEqual(supportsLiveActivities, true)
    }

    func testBothAppEntitlementFilesCarryTimeSensitive() throws {
        for fileName in ["Midas.entitlements", "Midas-Test.entitlements"] {
            let fileURL = shellFolder.appending(path: "Midas").appending(path: fileName)
            let data = try Data(contentsOf: fileURL)
            let entitlements = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(entitlements["com.apple.developer.usernotifications.time-sensitive"] as? Bool, true, fileName)
        }
    }
}
