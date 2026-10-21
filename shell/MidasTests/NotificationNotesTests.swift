import UserNotifications
import XCTest
@testable import Midas

// Founder decision 2026-10-20: the notification engine reads the item's `notes` as the
// notification text, under the title, on every notification the item makes (its own, a snooze,
// its early alerts, its hourly times). `body` is not read. These tests fail if notes stop
// showing anywhere the engine books.

final class NotificationNotesTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private var calendar: Calendar {
        ReminderSchedule.phoneCalendar(timeZone: zone)
    }
    private var expansion: ReminderExpansion {
        ReminderExpansion(schedule: ReminderSchedule(calendar: calendar))
    }
    private var planner: ReminderPlanner {
        ReminderPlanner(schedule: ReminderSchedule(calendar: calendar))
    }

    private func date(_ text: String) -> Date {
        ReminderRecord.parseDate(.string(text))!
    }

    private func record(_ key: String, _ fields: [String: JSONValue]) -> ReminderRecord {
        var allFields = fields
        allFields["timeZone"] = .string(zone.identifier)
        return ReminderRecord.parse(sidekickId: "care-reminders", key: key, value: .object(allFields))!
    }

    private let threeRules: JSONValue = .array([
        .object(["id": .string("a1"), "kind": .string("daysBefore"), "days": .number(1), "time": .string("18:00")]),
        .object(["id": .string("a2"), "kind": .string("morningOf"), "time": .string("08:00")]),
        .object(["id": .string("a3"), "kind": .string("before"), "minutes": .number(60)]),
    ])

    func testTheItemsNotesAreReadFromNotes() {
        let dentist = record("reminder:d1", ["title": .string("Dentist"), "notes": .string("Bring the insurance card"),
                                             "at": .string("2026-10-18T13:00:00-07:00")])
        XCTAssertEqual(dentist.notes, "Bring the insurance card")
        let plain = record("reminder:d2", ["title": .string("Dentist"), "at": .string("2026-10-18T13:00:00-07:00")])
        XCTAssertEqual(plain.notes, "", "no notes, no text")
    }

    func testEveryBookingOfAnItemCarriesItsNotes() {
        let now = date("2026-10-15T12:00:00-07:00")
        let dentist = record("reminder:d1", [
            "title": .string("Dentist"), "notes": .string("Bring the insurance card"),
            "at": .string("2026-10-18T13:00:00-07:00"), "alerts": threeRules,
            "snoozedUntil": .string("2026-10-15T12:30:00-07:00"),
        ])
        let plan = planner.plan(records: expansion.expand(dentist, now: now), ledger: [:], previousBookings: [], now: now)
        var bookedIds: Set<String> = []
        var bookedKinds: Set<BookingKind> = []
        for booking in plan.bookings {
            XCTAssertEqual(booking.body, "Bring the insurance card", "\(booking.identifier) lost the notes")
            bookedIds.insert(booking.identity.reminderId)
            bookedKinds.insert(booking.kind)
        }
        XCTAssertEqual(bookedIds, ["d1", "d1~a1", "d1~a2", "d1~a3"], "the item and its three early alerts are booked")
        XCTAssertTrue(bookedKinds.contains(.snooze), "the item's snooze is booked")
        XCTAssertTrue(bookedKinds.contains(.occurrence))
    }

    func testEveryHourlyTimeCarriesTheItemsNotes() {
        let now = date("2026-10-15T12:00:00-07:00")
        let pills = record("reminder:h1", [
            "title": .string("Pills"), "notes": .string("With food"), "at": .string("2026-10-16T08:00:00-07:00"),
            "repeat": .object(["every": .string("day")]), "everyHours": .number(3),
        ])
        let expanded = expansion.expand(pills, now: now)
        XCTAssertEqual(expanded.count, 8)
        for slot in expanded {
            XCTAssertEqual(slot.notes, "With food", "\(slot.identity.reminderId) lost the notes")
        }
        let plan = planner.plan(records: expanded, ledger: [:], previousBookings: [], now: now)
        XCTAssertFalse(plan.bookings.isEmpty)
        for booking in plan.bookings {
            XCTAssertEqual(booking.body, "With food", "\(booking.identifier) lost the notes")
        }
    }

    func testTheNotificationShowsTheNotesUnderTheTitle() {
        let now = date("2026-10-15T12:00:00-07:00")
        let call = record("reminder:c1", ["title": .string("Call Amma"), "notes": .string("Say hi from all of us"),
                                          "at": .string("2026-10-15T18:00:00-07:00")])
        let plan = planner.plan(records: [call], ledger: [:], previousBookings: [], now: now)
        let booking = try! XCTUnwrap(plan.bookings.first)
        let content = UserNotificationBooking.content(for: booking)
        XCTAssertEqual(content.title, "Call Amma")
        XCTAssertEqual(content.body, "Say hi from all of us")
    }

    func testBodyIsNoLongerReadWhenNotesArePresent() {
        let both = record("reminder:b1", ["title": .string("Gym"), "notes": .string("Leg day"), "body": .string("Old text"),
                                          "at": .string("2026-10-18T13:00:00-07:00")])
        XCTAssertEqual(both.notes, "Leg day")
        let emptyNotes = record("reminder:b2", ["title": .string("Gym"), "notes": .string(""), "body": .string("Old text"),
                                                "at": .string("2026-10-18T13:00:00-07:00")])
        XCTAssertEqual(emptyNotes.notes, "", "notes the person cleared stay cleared")
    }

    func testBodyAloneIsNotReadAsNotes() {
        let bodyOnly = record("reminder:u1", ["title": .string("Gym"), "body": .string("Leg day"),
                                              "at": .string("2026-10-18T13:00:00-07:00")])
        XCTAssertEqual(bodyOnly.notes, "", "body is not read")
    }

    func testTheShellCheckNamesNotesNotBody() {
        let badNotes: JSONValue = .object(["title": .string("x"), "notes": .number(5)])
        XCTAssertEqual(ReminderRecord.validationError(badNotes), "reminder.notes must be a string")
        let nullNotes: JSONValue = .object(["title": .string("x"), "notes": .null])
        XCTAssertNil(ReminderRecord.validationError(nullNotes))
        let oddBody: JSONValue = .object(["title": .string("x"), "body": .number(5)])
        XCTAssertNil(ReminderRecord.validationError(oddBody), "body is not checked any more")
    }
}
