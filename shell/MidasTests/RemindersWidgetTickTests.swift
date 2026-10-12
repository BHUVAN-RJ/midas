import XCTest
@testable import Midas

// The Reminders widget's tick and paging (brief docs/briefs/widget-reminders.md steps 4 and 5,
// founder 2026-10-11): a tick writes the record as the Sidekick does and the row leaves; the large
// size shows 8 rows; more than fits pages with up and down arrows.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func iso(_ date: Date) -> JSONValue {
    .string(ReminderRecord.formatDate(date))
}

private func sharedReminder(_ reminderId: String, hour: Int, minute: Int = 0) -> SharedReminder {
    SharedReminder(id: reminderId, title: reminderId, at: octoberPT(11, hour, minute), allDay: false, colorHex: "#007AFF")
}

/// A file whose today holds `count` reminders, one each half hour from 8:00 AM.
private func fileWith(count: Int) -> SharedTodayReminders {
    var todayReminders: [SharedReminder] = []
    for index in 0..<count {
        todayReminders.append(sharedReminder("r\(index)", hour: 8 + index / 2, minute: (index % 2) * 30))
    }
    let today = SharedRemindersDay(dayStart: octoberPT(11, 0), reminders: todayReminders)
    return SharedTodayReminders(days: [today], savedAt: octoberPT(11, 7))
}

private func shownIds(_ screen: RemindersWidgetScreen) -> [String] {
    guard case .reminders(_, let rows) = screen.content else {
        return []
    }
    var reminderIds: [String] = []
    for row in rows {
        reminderIds.append(row.reminder.id)
    }
    return reminderIds
}

final class RemindersWidgetTickValueTests: XCTestCase {
    private let now = octoberPT(11, 15)

    func testTickingAOneTimeReminderMarksItDoneAsTheSidekickDoes() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(11, 18)), "title": .string("Call Amma"), "done": .bool(false),
            "snoozedUntil": iso(octoberPT(11, 18, 10)), "list": .string("personal"),
        ])
        let ticked = RemindersWidgetPublisher.tickedValue(value, occurrence: octoberPT(11, 18), now: now)
        XCTAssertEqual(ticked["done"], .bool(true))
        XCTAssertEqual(ticked["completedAt"], iso(now))
        XCTAssertNil(ticked["snoozedUntil"])
        XCTAssertNil(ticked["doneThrough"])
        XCTAssertEqual(ticked["list"], .string("personal"))
    }

    func testTickingARepeatRecordsTodaysOccurrenceAndCarriesOn() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(1, 19, 30)), "title": .string("Gym"), "done": .bool(false),
            "repeat": .object(["every": .string("day")]), "doneThrough": iso(octoberPT(10, 19, 30)),
        ])
        let ticked = RemindersWidgetPublisher.tickedValue(value, occurrence: octoberPT(11, 19, 30), now: now)
        XCTAssertEqual(ticked["done"], .bool(false))
        XCTAssertEqual(ticked["lastDoneAt"], iso(now))
        XCTAssertEqual(ticked["doneThrough"], iso(octoberPT(11, 19, 30)))
        XCTAssertNil(ticked["completedAt"])
    }

    func testTickingAnOlderOccurrenceNeverMovesDoneThroughBack() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(1, 9)), "title": .string("Pills"),
            "repeat": .object(["every": .string("day")]), "doneThrough": iso(octoberPT(12, 9)),
        ])
        let ticked = RemindersWidgetPublisher.tickedValue(value, occurrence: octoberPT(11, 9), now: now)
        XCTAssertEqual(ticked["doneThrough"], iso(octoberPT(12, 9)))
    }

    func testATickedRepeatLeavesTodayButComesBackTomorrow() {
        let value: JSONValue = .object([
            "at": iso(octoberPT(1, 19, 30)), "title": .string("Gym"), "timeZone": .string("America/Los_Angeles"),
            "repeat": .object(["every": .string("day")]),
        ])
        let ticked = RemindersWidgetPublisher.tickedValue(value, occurrence: octoberPT(11, 19, 30), now: now)
        let record = LocalRecord(sidekickId: "reminders", key: "reminder:gym", value: ticked)
        let planner = TodayReminderPlanner(calendar: calendarPT)
        let days = planner.days(reminderRecords: [record], listRecords: [], now: now)
        XCTAssertEqual(days[0].reminders.count, 0)
        XCTAssertEqual(days[1].reminders.count, 1)
    }
}

final class RemindersWidgetPagingTests: XCTestCase {
    private let now = octoberPT(11, 7)

    func testLargeShowsUpToEightRows() {
        let screen = RemindersWidgetLayout.screen(file: fileWith(count: 8), now: now, calendar: calendarPT, family: .large,
                                                  requestedPage: 0, pendingTicks: [])
        XCTAssertEqual(shownIds(screen), ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7"])
        XCTAssertFalse(screen.showsPageArrows)
    }

    func testMoreThanFitsPagesThroughToday() {
        let file = fileWith(count: 7)
        let firstPage = RemindersWidgetLayout.screen(file: file, now: now, calendar: calendarPT, family: .small,
                                                     requestedPage: 0, pendingTicks: [])
        XCTAssertEqual(shownIds(firstPage), ["r0", "r1", "r2"])
        XCTAssertEqual(firstPage.pageCount, 3)
        XCTAssertTrue(firstPage.showsPageArrows)
        XCTAssertFalse(firstPage.canPageUp)
        XCTAssertTrue(firstPage.canPageDown)

        let lastPage = RemindersWidgetLayout.screen(file: file, now: now, calendar: calendarPT, family: .medium,
                                                    requestedPage: 2, pendingTicks: [])
        XCTAssertEqual(shownIds(lastPage), ["r6"])
        XCTAssertTrue(lastPage.canPageUp)
        XCTAssertFalse(lastPage.canPageDown)
        guard case .reminders(let count, _) = lastPage.content else {
            return XCTFail("expected rows")
        }
        XCTAssertEqual(count, 7)
    }

    func testAPageBeyondTheEndClampsToTheLastPage() {
        let screen = RemindersWidgetLayout.screen(file: fileWith(count: 4), now: now, calendar: calendarPT, family: .small,
                                                  requestedPage: 5, pendingTicks: [])
        XCTAssertEqual(screen.pageIndex, 1)
        XCTAssertEqual(shownIds(screen), ["r3"])
    }

    func testThreeOrFewerHasNoArrows() {
        let screen = RemindersWidgetLayout.screen(file: fileWith(count: 3), now: now, calendar: calendarPT, family: .small,
                                                  requestedPage: 0, pendingTicks: [])
        XCTAssertFalse(screen.showsPageArrows)
    }

    func testAPendingTickHidesTheRowAndLowersTheCount() {
        let tick = PendingReminderTick(reminderId: "r1", occurrence: octoberPT(11, 8, 30), tickedAt: now)
        let screen = RemindersWidgetLayout.screen(file: fileWith(count: 4), now: now, calendar: calendarPT, family: .small,
                                                  requestedPage: 0, pendingTicks: [tick])
        XCTAssertEqual(shownIds(screen), ["r0", "r2", "r3"])
        guard case .reminders(let count, _) = screen.content else {
            return XCTFail("expected rows")
        }
        XCTAssertEqual(count, 3)
    }

    func testTickingTheLastOneShowsAllDone() {
        let tick = PendingReminderTick(reminderId: "r0", occurrence: octoberPT(11, 8), tickedAt: now)
        let screen = RemindersWidgetLayout.screen(file: fileWith(count: 1), now: now, calendar: calendarPT, family: .large,
                                                  requestedPage: 0, pendingTicks: [tick])
        XCTAssertEqual(screen.content, .allDone)
    }

    func testPageFileMovesAndStaysInRange() throws {
        let pagesURL = FileManager.default.temporaryDirectory.appending(path: "pages-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: pagesURL) }
        XCTAssertEqual(RemindersWidgetPagesFile.page(for: .small, in: pagesURL), 0)

        RemindersWidgetPagesFile.movePage(for: .small, by: -1, pageCount: 3, in: pagesURL)
        XCTAssertEqual(RemindersWidgetPagesFile.page(for: .small, in: pagesURL), 0)
        RemindersWidgetPagesFile.movePage(for: .small, by: 1, pageCount: 3, in: pagesURL)
        RemindersWidgetPagesFile.movePage(for: .small, by: 1, pageCount: 3, in: pagesURL)
        RemindersWidgetPagesFile.movePage(for: .small, by: 1, pageCount: 3, in: pagesURL)
        XCTAssertEqual(RemindersWidgetPagesFile.page(for: .small, in: pagesURL), 2)
        XCTAssertEqual(RemindersWidgetPagesFile.page(for: .large, in: pagesURL), 0)
    }

    func testPendingTicksFileRoundTripAndClear() {
        let ticksURL = FileManager.default.temporaryDirectory.appending(path: "ticks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ticksURL) }
        let first = PendingReminderTick(reminderId: "call", occurrence: octoberPT(11, 18), tickedAt: octoberPT(11, 15))
        let second = PendingReminderTick(reminderId: "gym", occurrence: octoberPT(11, 19, 30), tickedAt: octoberPT(11, 15, 1))
        PendingReminderTicksFile.append(first, to: ticksURL)
        PendingReminderTicksFile.append(second, to: ticksURL)
        XCTAssertEqual(PendingReminderTicksFile.read(from: ticksURL), [first, second])

        PendingReminderTicksFile.write([], to: ticksURL)
        XCTAssertEqual(PendingReminderTicksFile.read(from: ticksURL), [])
    }
}

@MainActor
private final class TickReloadCounter {
    var count = 0

    func increment() {
        count += 1
    }
}

@MainActor
final class RemindersWidgetTickFlowTests: XCTestCase {
    private var sharedFileURL: URL!
    private var storeFileURL: URL!
    private var ticksFileURL: URL!

    override func setUp() async throws {
        let uniqueName = UUID().uuidString
        let temporary = FileManager.default.temporaryDirectory
        sharedFileURL = temporary.appending(path: "tick-widget-\(uniqueName).json")
        storeFileURL = temporary.appending(path: "tick-records-\(uniqueName).json")
        ticksFileURL = temporary.appending(path: "tick-pending-\(uniqueName).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: sharedFileURL)
        try? FileManager.default.removeItem(at: storeFileURL)
        try? FileManager.default.removeItem(at: ticksFileURL)
    }

    private func makePublisher(store: LocalRecordStore, reloads: TickReloadCounter) -> RemindersWidgetPublisher {
        let fixedNow = octoberPT(11, 15)
        return RemindersWidgetPublisher(fileURL: sharedFileURL, store: store,
                                        isAvailable: { true },
                                        now: { fixedNow },
                                        calendar: { calendarPT },
                                        reloadWidget: reloads.increment,
                                        pendingTicksFileURL: ticksFileURL)
    }

    private func todayIds() throws -> [String] {
        let data = try Data(contentsOf: sharedFileURL)
        let file = try XCTUnwrap(SharedTodayReminders.decoded(from: data))
        var reminderIds: [String] = []
        for reminder in file.days[0].reminders {
            reminderIds.append(reminder.id)
        }
        return reminderIds
    }

    private func seed(_ store: LocalRecordStore) throws {
        let callValue: JSONValue = .object(["at": iso(octoberPT(11, 18)), "title": .string("Call Amma"), "done": .bool(false)])
        let pushValue: JSONValue = .object(["at": iso(octoberPT(11, 14)), "title": .string("Push"), "done": .bool(false)])
        try store.set(sidekickId: "reminders", key: "reminder:call", value: callValue)
        try store.set(sidekickId: "reminders", key: "reminder:push", value: pushValue)
    }

    func testATickWritesTheRecordQueuesItForSyncAndTheRowLeaves() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        try seed(store)
        let reloads = TickReloadCounter()
        let publisher = makePublisher(store: store, reloads: reloads)
        publisher.publish()
        XCTAssertEqual(try todayIds(), ["push", "call"])
        let outboxBefore = store.pendingOpCount

        publisher.tick(reminderId: "call", occurrence: octoberPT(11, 18))

        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:call")?["done"], .bool(true))
        XCTAssertEqual(store.pendingOpCount, outboxBefore + 1)
        XCTAssertEqual(try todayIds(), ["push"])
        XCTAssertEqual(reloads.count, 2)
    }

    func testTicksSavedByTheWidgetAreAppliedAtTheNextPublish() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        try seed(store)
        let pendingTick = PendingReminderTick(reminderId: "push", occurrence: octoberPT(11, 14), tickedAt: octoberPT(11, 14, 30))
        PendingReminderTicksFile.append(pendingTick, to: ticksFileURL)
        let publisher = makePublisher(store: store, reloads: TickReloadCounter())

        publisher.publish()

        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:push")?["done"], .bool(true))
        XCTAssertEqual(try todayIds(), ["call"])
        XCTAssertEqual(PendingReminderTicksFile.read(from: ticksFileURL), [])
    }

    func testTickingAReminderThatIsGoneDoesNothing() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        let publisher = makePublisher(store: store, reloads: TickReloadCounter())
        publisher.tick(reminderId: "missing", occurrence: octoberPT(11, 18))
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:missing"))
        XCTAssertEqual(store.pendingOpCount, 0)
    }

    func testTheIntentUsesTheAppsHandlerWhenRegistered() async throws {
        var handled: [String] = []
        RemindersWidgetIntentBridge.tick = { reminderId, _ in
            handled.append(reminderId)
        }
        defer { RemindersWidgetIntentBridge.tick = nil }
        let intent = TickReminderIntent(reminderId: "call", occurrence: octoberPT(11, 18))
        _ = try await intent.perform()
        XCTAssertEqual(handled, ["call"])
    }
}
