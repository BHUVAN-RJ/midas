import UserNotifications
import XCTest
@testable import Midas

/// Stands in for iOS: holds pending bookings and can "deliver" the ones whose time came.
@MainActor
private final class FakeNotificationBooking: NotificationBooking {
    var isAuthorized = true
    var authorizationRequests = 0
    var pending: [String: PlannedBooking] = [:]
    var otherAppNotifications: Set<String> = []
    var bookedIdentifiers: [String] = []
    var cancelledIdentifiers: [String] = []

    func requestAuthorizationIfNeeded() async -> Bool {
        authorizationRequests += 1
        return isAuthorized
    }

    func pendingIdentifiers() async -> [String] {
        Array(pending.keys) + Array(otherAppNotifications)
    }

    func book(_ booking: PlannedBooking) async throws {
        bookedIdentifiers.append(booking.identifier)
        pending[booking.identifier] = booking
    }

    func cancel(identifiers: [String]) {
        cancelledIdentifiers.append(contentsOf: identifiers)
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
            otherAppNotifications.remove(identifier)
        }
    }

    /// iOS fires and forgets one-time notifications whose time came; repeating ones stay.
    func deliverDue(now: Date) {
        for (identifier, booking) in pending where booking.kind != .repeating && booking.fireDate <= now {
            pending.removeValue(forKey: identifier)
        }
    }

    func pendingTitles() -> [String] {
        let sortedBookings = pending.values.sorted(by: Self.isEarlier)
        var titles: [String] = []
        for booking in sortedBookings {
            titles.append(booking.title)
        }
        return titles
    }

    func pendingKinds() -> [BookingKind] {
        var kinds: [BookingKind] = []
        for booking in pending.values {
            kinds.append(booking.kind)
        }
        return kinds
    }

    private static func isEarlier(_ first: PlannedBooking, _ second: PlannedBooking) -> Bool {
        first.fireDate < second.fireDate
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func currentTime() -> Date {
        now
    }

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }
}

@MainActor
final class NotificationEngineTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let startTime = ReminderRecord.parseDate(.string("2026-10-08T12:00:00-07:00"))!
    private var temporaryDirectory: URL!
    private var store: LocalRecordStore!
    private var fakeBooking: FakeNotificationBooking!
    private var clock: TestClock!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(path: "engine-\(UUID().uuidString)")
        store = LocalRecordStore(fileURL: temporaryDirectory.appending(path: "records.json"))
        fakeBooking = FakeNotificationBooking()
        clock = TestClock(now: startTime)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try await super.tearDown()
    }

    private func makeEngine() -> NotificationEngine {
        let phoneCalendar = ReminderSchedule.phoneCalendar(timeZone: losAngeles)
        func fixedCalendar() -> Calendar {
            phoneCalendar
        }
        return NotificationEngine(store: store, booking: fakeBooking, stateFileURL: temporaryDirectory.appending(path: "engine.json"),
                                  calendarProvider: fixedCalendar, clock: clock.currentTime)
    }

    private func writeReminder(_ reminderId: String, minutesFromStart: Double, title: String? = nil,
                               repeatEvery: String? = nil, sidekickId: String = "reminders") throws {
        let reminderAt = startTime.addingTimeInterval(minutesFromStart * 60)
        var fields: [String: JSONValue] = [
            "at": .string(ReminderRecord.formatDate(reminderAt)),
            "title": .string(title ?? reminderId),
        ]
        if let repeatEvery {
            fields["repeat"] = .object(["every": .string(repeatEvery)])
        }
        try store.set(sidekickId: sidekickId, key: "reminder:\(reminderId)", value: .object(fields))
    }

    func testWrittenReminderIsBookedWithIOS() async throws {
        try writeReminder("call-mom", minutesFromStart: 2, title: "Call mom")
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.pendingTitles(), ["Call mom"])
        XCTAssertEqual(fakeBooking.authorizationRequests, 1)
    }

    func testNoPermissionPromptUntilThereIsSomethingToBook() async {
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.authorizationRequests, 0)
    }

    func testBatchIsToppedUpAfterRemindersFire() async throws {
        for index in 0..<60 {
            try writeReminder(String(format: "r%02d", index), minutesFromStart: Double(index + 1))
        }
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.pending.count, 48)

        clock.advance(minutes: 10)
        fakeBooking.deliverDue(now: clock.now)
        XCTAssertEqual(fakeBooking.pending.count, 38)

        await engine.refresh()
        XCTAssertEqual(fakeBooking.pending.count, 48)
        XCTAssertEqual(fakeBooking.pendingTitles().first, "r10")
        XCTAssertEqual(fakeBooking.pendingTitles().last, "r57")
        XCTAssertFalse(fakeBooking.pendingKinds().contains(.missed), "delivered reminders came back as missed")
    }

    func testUnchangedPlanIsNotBookedAgain() async throws {
        try writeReminder("a", minutesFromStart: 5)
        let engine = makeEngine()
        await engine.refresh()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.bookedIdentifiers.count, 1)
    }

    func testEditReplacesTheBookingUnderTheSameIdentifier() async throws {
        try writeReminder("a", minutesFromStart: 5, title: "Old title")
        let engine = makeEngine()
        await engine.refresh()
        try writeReminder("a", minutesFromStart: 5, title: "New title")
        await engine.refresh()
        XCTAssertEqual(fakeBooking.bookedIdentifiers.count, 2)
        XCTAssertEqual(Set(fakeBooking.bookedIdentifiers).count, 1)
        XCTAssertEqual(fakeBooking.pendingTitles(), ["New title"])
    }

    func testDeleteCancelsTheBooking() async throws {
        try writeReminder("a", minutesFromStart: 5)
        let engine = makeEngine()
        await engine.refresh()
        try store.delete(sidekickId: "reminders", key: "reminder:a")
        await engine.refresh()
        XCTAssertEqual(fakeBooking.pending.count, 0)
        XCTAssertEqual(fakeBooking.cancelledIdentifiers.count, 1)
    }

    func testNotificationsThatAreNotRemindersAreLeftAlone() async throws {
        fakeBooking.otherAppNotifications = ["widget|refresh"]
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.cancelledIdentifiers, [])
        XCTAssertEqual(fakeBooking.otherAppNotifications, ["widget|refresh"])
    }

    func testDeniedPermissionBooksNothingAndTheReminderFiresAsMissedOnceAllowed() async throws {
        fakeBooking.isAuthorized = false
        try writeReminder("a", minutesFromStart: 5)
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.pending.count, 0)
        XCTAssertEqual(engine.currentState.bookings, [])

        clock.advance(minutes: 30)
        fakeBooking.isAuthorized = true
        await engine.refresh()
        XCTAssertEqual(fakeBooking.pendingKinds(), [.missed])
    }

    func testEngineStateSurvivesARestartSoNothingFiresTwice() async throws {
        try writeReminder("a", minutesFromStart: 5)
        let firstEngine = makeEngine()
        await firstEngine.refresh()
        clock.advance(minutes: 10)
        fakeBooking.deliverDue(now: clock.now)

        let engineAfterRelaunch = makeEngine()
        await engineAfterRelaunch.refresh()
        XCTAssertEqual(fakeBooking.pending.count, 0)
        XCTAssertEqual(fakeBooking.bookedIdentifiers.count, 1)
    }

    func testDoneOnAOneTimeReminderCompletesItAndCancelsItsSnooze() async throws {
        try writeReminder("a", minutesFromStart: -1)
        let engine = makeEngine()
        await engine.refresh()
        let identity = ReminderIdentity(sidekickId: "reminders", reminderId: "a")
        await engine.handle(action: .snoozeTenMinutes, for: identity)
        XCTAssertTrue(fakeBooking.pendingKinds().contains(.snooze))

        await engine.handle(action: .done, for: identity)
        let storedValue = store.get(sidekickId: "reminders", key: "reminder:a")
        XCTAssertEqual(storedValue?["done"], .bool(true))
        XCTAssertNil(storedValue?["snoozedUntil"], "the snooze is removed, not set to null (rule: no null, 2026-10-15)")
        XCTAssertFalse(fakeBooking.pendingKinds().contains(.snooze))
    }

    func testSnoozeWritesTheRecordAndBooksTheSnooze() async throws {
        try writeReminder("a", minutesFromStart: 1)
        let engine = makeEngine()
        await engine.refresh()
        clock.advance(minutes: 2)
        fakeBooking.deliverDue(now: clock.now)

        let identity = ReminderIdentity(sidekickId: "reminders", reminderId: "a")
        await engine.handle(action: .snoozeTenMinutes, for: identity)
        let expectedSnooze = clock.now.addingTimeInterval(10 * 60)
        let storedValue = store.get(sidekickId: "reminders", key: "reminder:a")
        XCTAssertEqual(ReminderRecord.parseDate(storedValue?["snoozedUntil"])!.timeIntervalSince1970, expectedSnooze.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(fakeBooking.pendingKinds(), [.snooze])
    }

    func testDoneOnARepeatKeepsTheRepeatGoing() async throws {
        try writeReminder("daily", minutesFromStart: -60, repeatEvery: "day")
        let engine = makeEngine()
        await engine.refresh()
        XCTAssertEqual(fakeBooking.pendingKinds(), [.repeating])

        await engine.handle(action: .done, for: ReminderIdentity(sidekickId: "reminders", reminderId: "daily"))
        let storedValue = store.get(sidekickId: "reminders", key: "reminder:daily")
        XCTAssertNil(storedValue?["done"])
        XCTAssertNotNil(storedValue?["lastDoneAt"]?.stringValue)
        XCTAssertEqual(fakeBooking.pendingKinds(), [.repeating])
    }

    func testAReminderWrittenByASidekickIsBookedWithoutAnyoneCallingRefresh() async throws {
        let engine = makeEngine()
        engine.startWatchingStore()
        try writeReminder("a", minutesFromStart: 5, title: "From the Sidekick")
        for _ in 0..<100 where fakeBooking.pending.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fakeBooking.pendingTitles(), ["From the Sidekick"])
    }

    func testNonReminderWritesDoNotTriggerAPass() async throws {
        let engine = makeEngine()
        engine.startWatchingStore()
        try store.set(sidekickId: "reminders", key: "note:1", value: .string("hello"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fakeBooking.authorizationRequests, 0)
        XCTAssertEqual(engine.currentState, NotificationEngineState())
    }
}

/// The pieces that talk to iOS, checked without needing notification permission.
final class UserNotificationBookingTests: XCTestCase {
    private let identity = ReminderIdentity(sidekickId: "reminders", reminderId: "a")

    private func booking(kind: BookingKind, trigger: BookingTrigger, fireDate: Date) -> PlannedBooking {
        PlannedBooking(identifier: "reminder|reminders|a|\(kind.rawValue)|1", identity: identity, kind: kind, trigger: trigger,
                       fireDate: fireDate, occurrence: fireDate, title: "Title", body: "Body")
    }

    func testOneTimeTriggerFiresAtTheExactMoment() throws {
        let fireDate = Date().addingTimeInterval(3 * 3600).rounded()
        let trigger = UserNotificationBooking.trigger(for: booking(kind: .occurrence, trigger: .date(fireDate), fireDate: fireDate))
        let calendarTrigger = try XCTUnwrap(trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(calendarTrigger.repeats)
        XCTAssertEqual(calendarTrigger.nextTriggerDate(), fireDate)
    }

    func testRepeatingTriggerRepeats() throws {
        let components = DateComponents(hour: 9, minute: 0, second: 0)
        let trigger = UserNotificationBooking.trigger(for: booking(kind: .repeating, trigger: .repeating(components), fireDate: Date()))
        let calendarTrigger = try XCTUnwrap(trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(calendarTrigger.repeats)
        XCTAssertEqual(calendarTrigger.dateComponents.hour, 9)
    }

    func testMissedTriggerFiresRightAway() throws {
        let trigger = UserNotificationBooking.trigger(for: booking(kind: .missed, trigger: .immediately, fireDate: Date()))
        let intervalTrigger = try XCTUnwrap(trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertLessThanOrEqual(intervalTrigger.timeInterval, 1)
    }

    func testContentCarriesTheButtonsAndTheOwningReminder() {
        let content = UserNotificationBooking.content(for: booking(kind: .occurrence, trigger: .date(Date()), fireDate: Date()))
        XCTAssertEqual(content.title, "Title")
        XCTAssertEqual(content.body, "Body")
        XCTAssertEqual(content.categoryIdentifier, ReminderAction.categoryIdentifier)
        XCTAssertEqual(content.threadIdentifier, "reminders")
        XCTAssertEqual(NotificationPayload(userInfo: content.userInfo)?.identity, identity)
    }
}

private extension Date {
    func rounded() -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded())
    }
}
