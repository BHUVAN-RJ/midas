import XCTest
@testable import Midas

final class ReminderRecordTests: XCTestCase {
    private func decode(_ json: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testParsesAllThreeDateForms() {
        let expectedDate = Date(timeIntervalSince1970: 1_791_475_200)
        let fractional = ReminderRecord.parseDate(.string("2026-10-08T16:00:00.000Z"))
        let plain = ReminderRecord.parseDate(.string("2026-10-08T09:00:00-07:00"))
        let epochMilliseconds = ReminderRecord.parseDate(.number(1_791_475_200_000))
        XCTAssertEqual(fractional, expectedDate)
        XCTAssertEqual(plain, expectedDate)
        XCTAssertEqual(epochMilliseconds, expectedDate)
        XCTAssertNil(ReminderRecord.parseDate(.string("tomorrow at 9")))
    }

    func testParsesAFullRecord() throws {
        let value = decode(#"""
        {"at":"2026-10-08T16:00:00.000Z","title":"Gym","body":"Leg day","timeZone":"America/New_York",
         "repeat":{"every":"week","interval":2,"weekdays":[5,1,1]},"snoozedUntil":"2026-10-08T16:10:00.000Z"}
        """#)
        let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: "reminders", key: "reminder:gym", value: value))
        XCTAssertEqual(record.identity, ReminderIdentity(sidekickId: "reminders", reminderId: "gym"))
        XCTAssertEqual(record.title, "Gym")
        XCTAssertEqual(record.body, "Leg day")
        XCTAssertEqual(record.timeZone?.identifier, "America/New_York")
        XCTAssertEqual(record.repeatRule?.frequency, .week)
        XCTAssertEqual(record.repeatRule?.interval, 2)
        XCTAssertEqual(record.repeatRule?.weekdays, [1, 5])
        XCTAssertEqual(record.snoozedUntil, Date(timeIntervalSince1970: 1_791_475_800))
        XCTAssertFalse(record.done)
    }

    func testMinimalRecordGetsDefaults() throws {
        let value = decode(#"{"at":1791475200000,"title":"Call mom"}"#)
        let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: "reminders", key: "reminder:1", value: value))
        XCTAssertEqual(record.body, "")
        XCTAssertNil(record.repeatRule)
        XCTAssertNil(record.timeZone)
        XCTAssertNil(record.snoozedUntil)
    }

    func testRepeatIntervalDefaultsToOne() throws {
        let value = decode(#"{"at":1791475200000,"title":"Water plants","repeat":{"every":"day"}}"#)
        let record = try XCTUnwrap(ReminderRecord.parse(sidekickId: "reminders", key: "reminder:1", value: value))
        XCTAssertEqual(record.repeatRule?.interval, 1)
        XCTAssertEqual(record.repeatRule?.weekdays, [])
    }

    func testRejectsBadRecordsWithAReason() {
        let badRecords = [
            #""just a string""#,
            #"{"at":"someday","title":"bad time"}"#,
            #"{"at":1791475200000}"#,
            #"{"at":1791475200000,"title":""}"#,
            #"{"at":1791475200000,"title":"x","body":5}"#,
            #"{"at":1791475200000,"title":"x","done":"yes"}"#,
            #"{"at":1791475200000,"title":"x","timeZone":"Mars/Olympus"}"#,
            #"{"at":1791475200000,"title":"x","repeat":{"every":"fortnight"}}"#,
            #"{"at":1791475200000,"title":"x","repeat":{"every":"day","interval":0}}"#,
            #"{"at":1791475200000,"title":"x","repeat":{"every":"day","interval":1.5}}"#,
            #"{"at":1791475200000,"title":"x","repeat":{"every":"day","weekdays":[1]}}"#,
            #"{"at":1791475200000,"title":"x","repeat":{"every":"week","weekdays":[7]}}"#,
            #"{"at":1791475200000,"title":"x","repeat":{"every":"week","weekdays":[]}}"#,
            #"{"at":1791475200000,"title":"x","repeat":{"every":"day","until":"never"}}"#,
        ]
        for badRecord in badRecords {
            let value = decode(badRecord)
            XCTAssertNotNil(ReminderRecord.validationError(value), "accepted: \(badRecord)")
            XCTAssertNil(ReminderRecord.parse(sidekickId: "reminders", key: "reminder:1", value: value), "parsed: \(badRecord)")
        }
    }

    /// An undated item (no `at`) is a valid reminders.item since 2026-10-15; it is stored but
    /// notifies nobody, so it parses to nothing for the engine.
    func testAnUndatedItemIsAcceptedButIsNotANotification() {
        let value = decode(#"{"title":"Buy milk","list":"groceries"}"#)
        XCTAssertNil(ReminderRecord.validationError(value))
        XCTAssertNil(ReminderRecord.parse(sidekickId: "reminders", key: "reminder:1", value: value))
    }

    func testKeysOutsideTheReminderPrefixAreNotReminders() {
        let value = decode(#"{"at":1791475200000,"title":"x"}"#)
        XCTAssertNil(ReminderRecord.parse(sidekickId: "reminders", key: "note:1", value: value))
    }

    func testShellDatesReadBackAsTheSameMoment() {
        let moment = Date(timeIntervalSince1970: 1_791_475_200.25)
        let formatted = ReminderRecord.formatDate(moment)
        XCTAssertEqual(formatted, "2026-10-08T16:00:00.250Z")
        let parsedBack = ReminderRecord.parseDate(.string(formatted))!
        XCTAssertEqual(parsedBack.timeIntervalSince1970, moment.timeIntervalSince1970, accuracy: 0.001)
    }
}
