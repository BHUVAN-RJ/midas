import XCTest
@testable import Midas

// A widget tick is queued in the App Group before it is written, and stays queued until the write
// lands (founder, 2026-10-11: show the tick at once, make sure the work happens in the background).

private let queueCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func queueMoment(_ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: 11, hour: hour, minute: minute)
    return queueCalendar.date(from: components)!
}

@MainActor
private final class QueueReloadCounter {
    var count = 0

    func increment() {
        count += 1
    }
}

@MainActor
final class RemindersWidgetTickQueueTests: XCTestCase {
    private var temporaryFolder: URL!
    private var sharedFileURL: URL!
    private var ticksFileURL: URL!

    override func setUp() async throws {
        temporaryFolder = FileManager.default.temporaryDirectory.appending(path: "tick-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        sharedFileURL = temporaryFolder.appending(path: "widget.json")
        ticksFileURL = temporaryFolder.appending(path: "ticks.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryFolder)
    }

    private func makePublisher(store: LocalRecordStore) -> RemindersWidgetPublisher {
        let fixedNow = queueMoment(15)
        let reloads = QueueReloadCounter()
        return RemindersWidgetPublisher(fileURL: sharedFileURL, store: store,
                                        isAvailable: { true },
                                        now: { fixedNow },
                                        calendar: { queueCalendar },
                                        reloadWidget: reloads.increment,
                                        pendingTicksFileURL: ticksFileURL)
    }

    private func callValue() -> JSONValue {
        .object(["at": .string(ReminderRecord.formatDate(queueMoment(18))), "title": .string("Call Amma"), "done": .bool(false)])
    }

    func testATickLandsInTheRecordAndLeavesTheQueueEmpty() throws {
        let store = LocalRecordStore(fileURL: temporaryFolder.appending(path: "records.json"))
        try store.set(sidekickId: "reminders", key: "reminder:call", value: callValue())
        let publisher = makePublisher(store: store)
        publisher.startWatchingStore()

        publisher.tick(reminderId: "call", occurrence: queueMoment(18))

        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:call")?["done"], .bool(true))
        XCTAssertEqual(PendingReminderTicksFile.read(from: ticksFileURL), [])
        // Written once, even though the write makes the watched store publish again mid-pass.
        let writesForCall = store.pendingOps().filter(isCallWrite)
        XCTAssertEqual(writesForCall.count, 2)
    }

    private func isCallWrite(_ pendingOp: PendingOp) -> Bool {
        pendingOp.key == "reminder:call"
    }

    func testAFailedWriteStaysQueuedForTheNextTry() throws {
        // A plain file sits where the store's folder should be, so every save throws.
        let blockingFile = temporaryFolder.appending(path: "not-a-folder")
        try Data("x".utf8).write(to: blockingFile)
        let store = LocalRecordStore(fileURL: blockingFile.appending(path: "records.json"))
        XCTAssertThrowsError(try store.set(sidekickId: "reminders", key: "reminder:call", value: callValue()))
        let publisher = makePublisher(store: store)

        publisher.tick(reminderId: "call", occurrence: queueMoment(18))

        let stillQueued = PendingReminderTicksFile.read(from: ticksFileURL)
        XCTAssertEqual(stillQueued.count, 1)
        XCTAssertEqual(stillQueued.first?.reminderId, "call")
        XCTAssertEqual(stillQueued.first?.occurrence, queueMoment(18))
    }

    func testTheWidgetHidesAQueuedTickUntilItLands() throws {
        let queuedTick = PendingReminderTick(reminderId: "call", occurrence: queueMoment(18), tickedAt: queueMoment(15))
        let call = SharedReminder(id: "call", title: "Call Amma", at: queueMoment(18), allDay: false, colorHex: "#007AFF")
        let gym = SharedReminder(id: "gym", title: "Gym", at: queueMoment(19, 30), allDay: false, colorHex: "#007AFF")
        let day = SharedRemindersDay(dayStart: queueMoment(0), reminders: [call, gym])
        let file = SharedTodayReminders(days: [day], savedAt: queueMoment(15))

        let screen = RemindersWidgetLayout.screen(file: file, now: queueMoment(15), calendar: queueCalendar, family: .medium,
                                                  requestedPage: 0, pendingTicks: [queuedTick])
        guard case .reminders(let count, let rows) = screen.content else {
            return XCTFail("expected rows")
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(rows.first?.reminder.id, "gym")
    }
}
