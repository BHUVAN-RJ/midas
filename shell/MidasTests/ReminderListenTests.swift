import XCTest
@testable import Midas

// Hydration plan N2 (founder, 2026-10-25; docs/briefs/hydration-sidekick.md section 2.2): a
// reminder with `listen` stays quiet when it is not needed. Goal met: none of today's times are
// booked, tomorrow's come back. Any write to the listened record (the page or the widget): nothing
// in the next `quietMinutes`; the run after the quiet goes back to iOS repeating triggers. Times
// kept quiet are never reported as missed. A reminder without `listen` behaves as before.

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: losAngeles)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// Stands in for iOS: holds what is booked.
@MainActor
private final class ListenFakeBooking: NotificationBooking {
    var pending: [String: PlannedBooking] = [:]

    func requestAuthorizationIfNeeded() async -> Bool {
        return true
    }

    func pendingIdentifiers() async -> [String] {
        return Array(pending.keys)
    }

    func book(_ booking: PlannedBooking) async throws {
        pending[booking.identifier] = booking
    }

    func cancel(identifiers: [String]) {
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }

    /// iOS forgets one-time notifications whose time came.
    func deliverDue(now: Date) {
        for (identifier, booking) in pending where booking.kind != .repeating && booking.fireDate <= now {
            pending.removeValue(forKey: identifier)
        }
    }

    var bookings: [PlannedBooking] {
        return Array(pending.values)
    }
}

@MainActor
private final class ListenClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func currentTime() -> Date {
        return now
    }
}

private let listenField = #""listen": { "key": "water:{today}", "field": "ml", "goal": "settings:main.goalMl", "dayGoalField": "goalMl", "quietMinutes": 45 }"#

@MainActor
final class ReminderListenTests: XCTestCase {
    private var directory: URL!
    private var store: LocalRecordStore!
    private var fakeBooking: ListenFakeBooking!
    private var clock: ListenClock!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "reminder-listen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        fakeBooking = ListenFakeBooking()
        clock = ListenClock(now: octoberPT(25, 8))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeEngine() -> NotificationEngine {
        let fixedCalendar: @MainActor () -> Calendar = { calendarPT }
        return NotificationEngine(store: store, booking: fakeBooking, stateFileURL: directory.appending(path: "engine.json"),
                                  calendarProvider: fixedCalendar, clock: clock.currentTime)
    }

    /// Every 2 hours from 9:00 to 21:00, listening to the day's water when `listening`.
    private func writeWaterReminder(listening: Bool = true) throws {
        let at = ReminderRecord.formatDate(octoberPT(25, 9))
        let listenText = listening ? ", " + listenField : ""
        let reminder = json(#"{ "title": "Water", "at": "\#(at)", "repeat": { "every": "day" }, "everyHours": 2, "endTime": "21:00", "timeZone": "America/Los_Angeles"\#(listenText) }"#)
        try store.set(sidekickId: "hydration", key: "reminder:water", value: reminder)
        try store.set(sidekickId: "hydration", key: "settings:main", value: json(#"{ "goalMl": 2500 }"#))
    }

    private func writeWater(_ day: String, ml: Int) throws {
        try store.set(sidekickId: "hydration", key: "water:\(day)", value: json(#"{ "ml": \#(ml) }"#))
    }

    /// Lets the store observer's re-plan run (it is started on the main actor after the write).
    private func waitForBookings(_ isDone: () -> Bool) async throws {
        for _ in 0..<200 where !isDone() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func bookings(firingFrom start: Date, before end: Date) -> [PlannedBooking] {
        var matching: [PlannedBooking] = []
        for booking in fakeBooking.bookings where booking.fireDate >= start && booking.fireDate < end {
            matching.append(booking)
        }
        return matching
    }

    private func hours(of bookings: [PlannedBooking]) -> Set<Int> {
        var bookedHours: Set<Int> = []
        for booking in bookings {
            bookedHours.insert(calendarPT.component(.hour, from: booking.fireDate))
        }
        return bookedHours
    }

    private func missedBookings() -> [PlannedBooking] {
        var missed: [PlannedBooking] = []
        for booking in fakeBooking.bookings where booking.kind == .missed {
            missed.append(booking)
        }
        return missed
    }

    // MARK: Goal met

    func testAMetGoalLeavesNothingBookedForTheRestOfToday() async throws {
        try writeWaterReminder()
        try writeWater("2026-10-25", ml: 2500)
        clock.now = octoberPT(25, 14, 30)
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertTrue(bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty, "a time was booked for later today")
        // Tomorrow every time is there: 9, 11 and 13 as repeating triggers, the later ones one by one.
        XCTAssertEqual(hours(of: bookings(firingFrom: octoberPT(26, 0), before: octoberPT(27, 0))), [9, 11, 13, 15, 17, 19, 21])
        XCTAssertTrue(missedBookings().isEmpty)
    }

    func testTheDaysOwnGoalCounts() async throws {
        try writeWaterReminder()
        try store.set(sidekickId: "hydration", key: "water:2026-10-25", value: json(#"{ "ml": 2000, "goalMl": 2000 }"#))
        clock.now = octoberPT(25, 14, 30)
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertTrue(bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty)
    }

    func testTomorrowsTimesComeBackAsRepeatingTriggers() async throws {
        try writeWaterReminder()
        try writeWater("2026-10-25", ml: 2500)
        clock.now = octoberPT(25, 14, 30)
        let engine = makeEngine()
        await engine.refresh()
        clock.now = octoberPT(26, 8)
        fakeBooking.deliverDue(now: clock.now)
        await engine.refresh()
        XCTAssertEqual(fakeBooking.bookings.count, 7)
        for booking in fakeBooking.bookings {
            XCTAssertEqual(booking.kind, .repeating)
        }
        XCTAssertEqual(hours(of: bookings(firingFrom: clock.now, before: octoberPT(27, 0))), [9, 11, 13, 15, 17, 19, 21])
        XCTAssertTrue(missedBookings().isEmpty, "yesterday's quiet times came back as missed")
    }

    func testAnUnmetGoalChangesNothing() async throws {
        try writeWaterReminder()
        try writeWater("2026-10-25", ml: 2499)
        clock.now = octoberPT(25, 14, 30)
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.bookings.count, 7)
        XCTAssertEqual(hours(of: bookings(firingFrom: clock.now, before: octoberPT(26, 0))), [15, 17, 19, 21])
    }

    // MARK: A write keeps it quiet

    func testAPageWriteKeepsTheNext45MinutesQuiet() async throws {
        try writeWaterReminder()
        clock.now = octoberPT(25, 14, 40)
        let engine = makeEngine()
        engine.startWatchingStore()
        await engine.refresh()
        XCTAssertEqual(hours(of: bookings(firingFrom: clock.now, before: octoberPT(26, 0))), [15, 17, 19, 21])
        try writeWater("2026-10-25", ml: 250)
        try await waitForBookings { bookings(firingFrom: clock.now, before: octoberPT(25, 15, 25)).isEmpty }
        XCTAssertTrue(bookings(firingFrom: clock.now, before: octoberPT(25, 15, 25)).isEmpty, "15:00 is within 45 minutes of the drink")
        XCTAssertEqual(hours(of: bookings(firingFrom: clock.now, before: octoberPT(26, 0))), [17, 19, 21])
        // Tomorrow: 9, 11 and 13 are repeating triggers next firing then, 15:00 is booked one by
        // one (its trigger would have fired in the quiet); 17, 19 and 21 fire today and repeat.
        XCTAssertEqual(hours(of: bookings(firingFrom: octoberPT(26, 0), before: octoberPT(27, 0))), [9, 11, 13, 15])
    }

    func testAfterTheQuietTheTimeIsARepeatingTriggerAgain() async throws {
        try writeWaterReminder()
        clock.now = octoberPT(25, 14, 40)
        let engine = makeEngine()
        engine.startWatchingStore()
        await engine.refresh()
        try writeWater("2026-10-25", ml: 250)
        try await waitForBookings { bookings(firingFrom: clock.now, before: octoberPT(25, 15, 25)).isEmpty }
        var fifteenHundred: [PlannedBooking] = []
        for booking in fakeBooking.bookings where booking.identity.reminderId == "water@1500" {
            fifteenHundred.append(booking)
        }
        XCTAssertFalse(fifteenHundred.isEmpty)
        for booking in fifteenHundred {
            XCTAssertEqual(booking.kind, .occurrence, "booked one by one while quiet")
        }
        clock.now = octoberPT(25, 15, 30)
        fakeBooking.deliverDue(now: clock.now)
        await engine.refresh()
        var afterQuiet: [PlannedBooking] = []
        for booking in fakeBooking.bookings where booking.identity.reminderId == "water@1500" {
            afterQuiet.append(booking)
        }
        XCTAssertEqual(afterQuiet.count, 1)
        XCTAssertEqual(afterQuiet.first?.kind, .repeating)
        XCTAssertEqual(afterQuiet.first?.fireDate, octoberPT(26, 15))
        XCTAssertTrue(missedBookings().isEmpty, "the quiet 15:00 came back as missed")
    }

    func testAWidgetTapKeepsItQuietToo() async throws {
        try writeWaterReminder()
        clock.now = octoberPT(25, 14, 40)
        let engine = makeEngine()
        engine.startWatchingStore()
        await engine.refresh()
        let tapTime = clock.now
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: "hydration", name: "Water")] }
        let doNothing: @MainActor () -> Void = {}
        let publisher = SidekickWidgetPublisher(fileURL: nil, store: store, sidekicks: listSidekicks, now: { tapTime },
                                                calendar: { calendarPT }, reloadWidget: doNothing)
        let tap = WidgetTapAction(kind: .increment, sidekickId: "hydration", key: "water:{today}", field: "ml", amount: 250, valueJSON: nil, occurrence: nil)
        XCTAssertTrue(publisher.write(tap))
        try await waitForBookings { bookings(firingFrom: clock.now, before: octoberPT(25, 15, 25)).isEmpty }
        XCTAssertTrue(bookings(firingFrom: clock.now, before: octoberPT(25, 15, 25)).isEmpty)
        XCTAssertEqual(hours(of: bookings(firingFrom: clock.now, before: octoberPT(26, 0))), [17, 19, 21])
    }

    func testAGoalReachedFromTheWidgetQuietsTheDay() async throws {
        try writeWaterReminder()
        try writeWater("2026-10-25", ml: 2250)
        clock.now = octoberPT(25, 14, 40)
        let engine = makeEngine()
        engine.startWatchingStore()
        await engine.refresh()
        let tapTime = clock.now
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: "hydration", name: "Water")] }
        let doNothing: @MainActor () -> Void = {}
        let publisher = SidekickWidgetPublisher(fileURL: nil, store: store, sidekicks: listSidekicks, now: { tapTime },
                                                calendar: { calendarPT }, reloadWidget: doNothing)
        let tap = WidgetTapAction(kind: .increment, sidekickId: "hydration", key: "water:{today}", field: "ml", amount: 250, valueJSON: nil, occurrence: nil)
        XCTAssertTrue(publisher.write(tap))
        try await waitForBookings { bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty }
        XCTAssertTrue(bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty)
    }

    func testAnUndoBelowTheGoalGivesTodayBack() async throws {
        try writeWaterReminder()
        try writeWater("2026-10-25", ml: 2500)
        clock.now = octoberPT(25, 14, 30)
        let engine = makeEngine()
        engine.startWatchingStore()
        await engine.refresh()
        XCTAssertTrue(bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty)
        // The last drink is taken back: under the goal again, quiet for 45 minutes only.
        try writeWater("2026-10-25", ml: 2250)
        try await waitForBookings { !bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty }
        XCTAssertEqual(hours(of: bookings(firingFrom: clock.now, before: octoberPT(26, 0))), [17, 19, 21])
    }

    func testAChangedGoalRePlans() async throws {
        try writeWaterReminder()
        try writeWater("2026-10-25", ml: 2000)
        clock.now = octoberPT(25, 14, 30)
        let engine = makeEngine()
        engine.startWatchingStore()
        await engine.refresh()
        XCTAssertFalse(bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty)
        try store.set(sidekickId: "hydration", key: "settings:main", value: json(#"{ "goalMl": 2000 }"#))
        try await waitForBookings { bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty }
        XCTAssertTrue(bookings(firingFrom: clock.now, before: octoberPT(26, 0)).isEmpty)
    }

    // MARK: Without listen

    func testAReminderWithoutListenIsUnchanged() async throws {
        try writeWaterReminder(listening: false)
        try writeWater("2026-10-25", ml: 2500)
        clock.now = octoberPT(25, 14, 30)
        let engine = makeEngine()
        engine.startWatchingStore()
        await engine.refresh()
        let before = fakeBooking.pending
        try writeWater("2026-10-25", ml: 3000)
        try await Task.sleep(nanoseconds: 200_000_000)
        await engine.refresh()
        XCTAssertEqual(fakeBooking.pending, before)
        XCTAssertEqual(fakeBooking.bookings.count, 7)
        XCTAssertEqual(hours(of: bookings(firingFrom: clock.now, before: octoberPT(26, 0))), [15, 17, 19, 21])
        XCTAssertNil(engine.currentState.listenWrites)
    }

    func testThePlannerIgnoresListeningFieldsItIsNotGiven() {
        let schedule = ReminderSchedule(calendar: calendarPT)
        let at = ReminderRecord.formatDate(octoberPT(25, 9))
        let value = json(#"{ "title": "Water", "at": "\#(at)", "repeat": { "every": "day" }, "everyHours": 2, "endTime": "21:00", "timeZone": "America/Los_Angeles" }"#)
        let plain = ReminderRecord.parse(sidekickId: "hydration", key: "reminder:water", value: value)!
        let expanded = ReminderExpansion(schedule: schedule).expand(plain, now: octoberPT(25, 14, 30))
        let planner = ReminderPlanner(schedule: schedule)
        let plan = planner.plan(records: expanded, ledger: [:], previousBookings: [], now: octoberPT(25, 14, 30))
        XCTAssertEqual(plan.bookings.count, 7)
        for booking in plan.bookings {
            XCTAssertEqual(booking.kind, .repeating)
        }
    }

    // MARK: The record

    func testListenIsReadFromTheRecord() {
        let at = ReminderRecord.formatDate(octoberPT(25, 9))
        let value = json(#"{ "title": "Water", "at": "\#(at)", \#(listenField) }"#)
        let listen = ReminderRecord.parse(sidekickId: "hydration", key: "reminder:water", value: value)?.listen
        XCTAssertEqual(listen?.key, "water:{today}")
        XCTAssertEqual(listen?.field, "ml")
        XCTAssertEqual(listen?.goalKey, "settings:main")
        XCTAssertEqual(listen?.goalField, "goalMl")
        XCTAssertEqual(listen?.dayGoalField, "goalMl")
        XCTAssertEqual(listen?.quietMinutes, 45)
        XCTAssertEqual(listen?.listenedKey(at: octoberPT(25, 23, 59), calendar: calendarPT), "water:2026-10-25")
    }

    func testABadListenIsRefused() {
        let at = ReminderRecord.formatDate(octoberPT(25, 9))
        let cases: [(String, String)] = [
            (#""listen": 5"#, "reminder.listen must be an object"),
            (#""listen": { "field": "ml" }"#, "reminder.listen.key must be the key of a record that is not a reminder"),
            (#""listen": { "key": "reminder:other" }"#, "reminder.listen.key must be the key of a record that is not a reminder"),
            (#""listen": { "key": "water:{today}", "field": "ml", "goal": "lots" }"#, "reminder.listen.goal must be a number or \"<key>.<field>\""),
            (#""listen": { "key": "water:{today}", "goal": 2000 }"#, "reminder.listen.goal needs field"),
            (#""listen": { "key": "water:{today}", "quietMinutes": 2000 }"#, "reminder.listen.quietMinutes must be a whole number from 0 to 1440"),
        ]
        for (listenText, expectedError) in cases {
            let value = json(#"{ "title": "Water", "at": "\#(at)", \#(listenText) }"#)
            XCTAssertEqual(ReminderRecord.validationError(value), expectedError, listenText)
        }
        let numberGoal = json(#"{ "title": "Water", "at": "\#(at)", "listen": { "key": "water:{today}", "field": "ml", "goal": 2000 } }"#)
        XCTAssertNil(ReminderRecord.validationError(numberGoal))
    }

    func testTheQuietIsTheLaterOfTheGoalAndTheWrite() {
        let listen = ReminderListen(key: "water:{today}", field: "ml", goalNumber: 2000, goalKey: nil, goalField: nil, dayGoalField: nil, quietMinutes: 45)
        let now = octoberPT(25, 23, 30)
        let metAndWritten = listen.quietUntil(listenedValue: json(#"{ "ml": 2000 }"#), goalValue: nil, lastWriteAt: octoberPT(25, 23, 30), now: now, calendar: calendarPT)
        XCTAssertEqual(metAndWritten, octoberPT(26, 0, 15))
        let metOnly = listen.quietUntil(listenedValue: json(#"{ "ml": 2000 }"#), goalValue: nil, lastWriteAt: nil, now: now, calendar: calendarPT)
        XCTAssertEqual(metOnly, octoberPT(26, 0))
        let nothing = listen.quietUntil(listenedValue: json(#"{ "ml": 100 }"#), goalValue: nil, lastWriteAt: nil, now: now, calendar: calendarPT)
        XCTAssertNil(nothing)
    }
}
