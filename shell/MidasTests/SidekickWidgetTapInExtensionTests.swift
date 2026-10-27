import AppIntents
import XCTest
@testable import Midas

// A widget tap shows at once (founder, 2026-10-27: "clicking the button doesn't update it
// instantly. It takes a couple of seconds"; docs/PRODUCT.md "Widget taps at once", commit ca5d6d5).
// The tap's intent runs in the widget extension: it queues the tap and reloads the widget, which
// redraws from the tap preview. The app writes the queue when it next runs, each tap once, on the
// day it was tapped, and a listening reminder's quiet starts at the tap, not at the write.

private let calendarPT = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberPT(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendarPT.date(from: components)!
}

private func json(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

// Water's shape: one record per day, a button that adds 250 ml to the day it was tapped.
private let waterDayWidget = json(#"""
{ "name": "Today",
  "sources": { "day": { "record": "water:{today}" } },
  "small": { "vstack": [ { "text": "$day.ml" }, { "button": "+", "action": { "increment": "water:{today}", "field": "ml", "by": 250 } } ] } }
"""#)

private let plusQuarterLitre = WidgetTapAction(kind: .increment, sidekickId: "hydration", key: "water:{today}", field: "ml",
                                               amount: 250, valueJSON: nil, occurrence: nil)

/// Stands in for iOS: holds what is booked.
@MainActor
private final class TapFakeBooking: NotificationBooking {
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
}

@MainActor
private final class TapClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func currentTime() -> Date {
        return now
    }
}

@MainActor
final class SidekickWidgetTapInExtensionTests: XCTestCase {
    private var directory: URL!
    private var store: LocalRecordStore!
    private var widgetsFileURL: URL!
    private var actionsFileURL: URL!
    private var recordsFileURL: URL!
    private var listedSidekicks: [(id: String, name: String)] = [(id: "hydration", name: "Water")]
    private var clock: TapClock!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "tap-in-extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        widgetsFileURL = directory.appending(path: "widgets.json")
        actionsFileURL = directory.appending(path: "actions.json")
        recordsFileURL = directory.appending(path: "records-snapshot.json")
        clock = TapClock(now: octoberPT(26, 10))
        try store.set(sidekickId: "hydration", key: "widget:today", value: waterDayWidget)
        try store.set(sidekickId: "hydration", key: "water:2026-10-26", value: json(#"{ "ml": 1000 }"#))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePublisher() -> SidekickWidgetPublisher {
        let tapClock = clock!
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [unowned self] in self.listedSidekicks }
        let ignoreReload: @MainActor () -> Void = {}
        return SidekickWidgetPublisher(fileURL: widgetsFileURL, store: store, sidekicks: listSidekicks,
                                       now: tapClock.currentTime, calendar: { calendarPT }, reloadWidget: ignoreReload,
                                       pendingActionsFileURL: actionsFileURL, recordsFileURL: recordsFileURL)
    }

    /// What the intent does in the widget extension.
    private func tapInTheExtension(_ action: WidgetTapAction, at moment: Date) {
        let ignoreReload: () -> Void = {}
        SidekickWidgetTapQueue.queue(action, tappedAt: moment, pendingActionsFileURL: actionsFileURL, reloadWidget: ignoreReload)
    }

    /// What the widget draws now: the preview when it has one, else the published widget.
    private func drawnText(at moment: Date) throws -> String? {
        let file = try XCTUnwrap(SharedSidekickWidgets.read(from: widgetsFileURL))
        let published = try XCTUnwrap(file.widget(choiceId: "hydration/today"))
        let preview = SidekickWidgetTapPreview.widget(published, snapshot: SidekickWidgetRecordsSnapshot.read(from: recordsFileURL),
                                                      pendingActions: PendingWidgetActionsFile.read(from: actionsFileURL),
                                                      now: moment, calendar: calendarPT)
        let drawn = preview ?? published
        guard case .vstack(let stack)? = drawn.look(at: moment)?.small else {
            return nil
        }
        for child in stack.children {
            if case .text(let textPiece) = child {
                return textPiece.text
            }
        }
        return nil
    }

    private func storedMl(_ day: String) -> JSONValue? {
        return store.get(sidekickId: "hydration", key: "water:\(day)")?["ml"]
    }

    // MARK: The intent

    func testTheTapIsPerformedInTheWidgetExtensionAndTheAlarmButtonsStayInTheApp() {
        // A LiveActivityIntent is performed in the app's process, which iOS first launches.
        let tapIntent = SidekickWidgetActionIntent(action: plusQuarterLitre)
        XCTAssertFalse((tapIntent as Any) is any LiveActivityIntent, "the widget's tap would wait for Midas to launch")
        XCTAssertTrue((StopAlarmReminderIntent() as Any) is any LiveActivityIntent)
        XCTAssertTrue((SnoozeAlarmReminderIntent() as Any) is any LiveActivityIntent)
        XCTAssertTrue((DoneAlarmReminderIntent() as Any) is any LiveActivityIntent)
    }

    func testTheExtensionQueuesTheTapReloadsTheWidgetAndWritesNoRecord() throws {
        var reloads = 0
        func countReload() {
            reloads += 1
        }
        SidekickWidgetTapQueue.queue(plusQuarterLitre, tappedAt: clock.now, pendingActionsFileURL: actionsFileURL, reloadWidget: countReload)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(PendingWidgetActionsFile.read(from: actionsFileURL), [PendingWidgetAction(action: plusQuarterLitre, tappedAt: clock.now)])
        XCTAssertEqual(storedMl("2026-10-26"), .number(1000))
    }

    func testTheWidgetDrawsTheQueuedTap() throws {
        makePublisher().publish()
        XCTAssertEqual(try drawnText(at: clock.now), "1000")
        tapInTheExtension(plusQuarterLitre, at: clock.now)
        XCTAssertEqual(try drawnText(at: clock.now), "1250")
    }

    func testThreeQuickTapsAddThreeQuartersOfALitreAndTheAppWritesThemOnce() throws {
        makePublisher().publish()
        for _ in 0..<3 {
            tapInTheExtension(plusQuarterLitre, at: clock.now)
        }
        XCTAssertEqual(try drawnText(at: clock.now), "1750")
        clock.now = octoberPT(26, 10, 30)
        let publisher = makePublisher()
        publisher.publish()
        XCTAssertEqual(storedMl("2026-10-26"), .number(1750))
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty)
        publisher.publish()
        makePublisher().publish()
        XCTAssertEqual(storedMl("2026-10-26"), .number(1750), "a tap was written twice")
        XCTAssertEqual(try drawnText(at: clock.now), "1750")
    }

    func testATapAt2359WrittenAfterMidnightLandsOnTheDayItWasTapped() throws {
        makePublisher().publish()
        tapInTheExtension(plusQuarterLitre, at: octoberPT(26, 23, 59))
        clock.now = octoberPT(27, 0, 5)
        makePublisher().publish()
        XCTAssertEqual(storedMl("2026-10-26"), .number(1250))
        XCTAssertNil(store.get(sidekickId: "hydration", key: "water:2026-10-27"))
    }

    func testTapsQueuedWhileSignedOutWaitForASignedInRun() throws {
        makePublisher().publish()
        tapInTheExtension(plusQuarterLitre, at: clock.now)
        listedSidekicks = []
        makePublisher().publish()
        XCTAssertEqual(PendingWidgetActionsFile.read(from: actionsFileURL).count, 1, "the tap was dropped")
        XCTAssertEqual(storedMl("2026-10-26"), .number(1000))
        listedSidekicks = [(id: "hydration", name: "Water")]
        makePublisher().publish()
        XCTAssertEqual(storedMl("2026-10-26"), .number(1250))
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty)
    }

    func testAReminderTickQueuedInTheExtensionIsWrittenOnce() throws {
        let at = ReminderRecord.formatDate(octoberPT(26, 9))
        try store.set(sidekickId: "hydration", key: "reminder:pill", value: json(#"{ "title": "Pill", "at": "\#(at)", "timeZone": "America/Los_Angeles" }"#))
        let tick = WidgetTapAction(kind: .tick, sidekickId: "hydration", key: "reminder:pill", field: nil, amount: nil, valueJSON: nil, occurrence: octoberPT(26, 9))
        makePublisher().publish()
        tapInTheExtension(tick, at: clock.now)
        clock.now = octoberPT(26, 10, 30)
        makePublisher().publish()
        let ticked = try XCTUnwrap(store.get(sidekickId: "hydration", key: "reminder:pill"))
        XCTAssertEqual(ticked["done"], .bool(true))
        XCTAssertEqual(ticked["completedAt"], .string(ReminderRecord.formatDate(octoberPT(26, 10))), "done at the tap, not at the write")
        XCTAssertTrue(PendingWidgetActionsFile.read(from: actionsFileURL).isEmpty)
        clock.now = octoberPT(26, 11)
        makePublisher().publish()
        XCTAssertEqual(store.get(sidekickId: "hydration", key: "reminder:pill"), ticked)
    }

    // MARK: The listening reminder

    private func writeListeningWaterReminder() throws {
        let at = ReminderRecord.formatDate(octoberPT(26, 9))
        let listen = #""listen": { "key": "water:{today}", "field": "ml", "goal": "settings:main.goalMl", "quietMinutes": 45 }"#
        let reminder = json(#"{ "title": "Water", "at": "\#(at)", "repeat": { "every": "day" }, "everyHours": 2, "endTime": "21:00", "timeZone": "America/Los_Angeles", \#(listen) }"#)
        try store.set(sidekickId: "hydration", key: "reminder:water", value: reminder)
        try store.set(sidekickId: "hydration", key: "settings:main", value: json(#"{ "goalMl": 2500 }"#))
    }

    private func makeEngine(booking: TapFakeBooking) -> NotificationEngine {
        let fixedCalendar: @MainActor () -> Calendar = { calendarPT }
        return NotificationEngine(store: store, booking: booking, stateFileURL: directory.appending(path: "engine.json"),
                                  calendarProvider: fixedCalendar, clock: clock.currentTime)
    }

    private func bookedHoursToday(_ booking: TapFakeBooking) -> Set<Int> {
        var bookedHours: Set<Int> = []
        for planned in booking.pending.values where planned.fireDate >= clock.now && planned.fireDate < octoberPT(27, 0) {
            bookedHours.insert(calendarPT.component(.hour, from: planned.fireDate))
        }
        return bookedHours
    }

    func testAQueuedDrinkKeepsTheReminderQuietFromTheTapNotFromTheWrite() async throws {
        try writeListeningWaterReminder()
        let booking = TapFakeBooking()
        let engine = makeEngine(booking: booking)
        engine.startWatchingStore()
        makePublisher().publish()
        // Drunk at 14:00 on the widget; Midas runs at 14:50. Quiet ends 14:45, so 15:00 is booked.
        tapInTheExtension(plusQuarterLitre, at: octoberPT(26, 14))
        clock.now = octoberPT(26, 14, 50)
        let publisher = makePublisher()
        publisher.writingQueuedTap = engine.noteWrites(tappedAt:_:)
        publisher.publish()
        await engine.refresh()
        XCTAssertEqual(storedMl("2026-10-26"), .number(1250))
        let writeKey = NotificationEngine.listenWriteKey(sidekickId: "hydration", key: "water:2026-10-26")
        XCTAssertEqual(engine.currentState.listenWrites?[writeKey], octoberPT(26, 14))
        XCTAssertEqual(bookedHoursToday(booking), [15, 17, 19, 21], "the quiet ran from the write, not the tap")
    }

    func testAnOlderTapDoesNotPullBackALaterWrite() async throws {
        try writeListeningWaterReminder()
        let booking = TapFakeBooking()
        let engine = makeEngine(booking: booking)
        engine.startWatchingStore()
        clock.now = octoberPT(26, 14, 30)
        try store.set(sidekickId: "hydration", key: "water:2026-10-26", value: json(#"{ "ml": 1250 }"#))
        func writeOlderTap() {
            try? store.set(sidekickId: "hydration", key: "water:2026-10-26", value: json(#"{ "ml": 1500 }"#))
        }
        engine.noteWrites(tappedAt: octoberPT(26, 14), writeOlderTap)
        let writeKey = NotificationEngine.listenWriteKey(sidekickId: "hydration", key: "water:2026-10-26")
        XCTAssertEqual(engine.currentState.listenWrites?[writeKey], octoberPT(26, 14, 30))
    }

    func testAPageWriteIsStillNotedAtItsOwnTime() async throws {
        try writeListeningWaterReminder()
        let engine = makeEngine(booking: TapFakeBooking())
        engine.startWatchingStore()
        clock.now = octoberPT(26, 14, 30)
        try store.set(sidekickId: "hydration", key: "water:2026-10-26", value: json(#"{ "ml": 1250 }"#))
        let writeKey = NotificationEngine.listenWriteKey(sidekickId: "hydration", key: "water:2026-10-26")
        XCTAssertEqual(engine.currentState.listenWrites?[writeKey], octoberPT(26, 14, 30))
    }

    // MARK: Wiring

    func testTheAppNotesQueuedTapsFromItsFirstPublish() throws {
        let shellDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let services = try String(contentsOf: shellDirectory.appending(path: "Midas/ShellServices.swift"), encoding: .utf8)
        let watching = try XCTUnwrap(services.range(of: "notificationEngine.startWatchingStore()"))
        let noting = try XCTUnwrap(services.range(of: "sidekickWidgets.writingQueuedTap = notificationEngine.noteWrites(tappedAt:_:)"))
        let firstPublish = try XCTUnwrap(services.range(of: "sidekickWidgets.publish()"))
        XCTAssertLessThan(watching.lowerBound, firstPublish.lowerBound, "taps written at launch would start no quiet")
        XCTAssertLessThan(noting.lowerBound, firstPublish.lowerBound)
        XCTAssertFalse(services.contains("engine.startWatchingStore()\n"), "the engine watches the store once")
        let intents = try String(contentsOf: shellDirectory.appending(path: "Shared/SidekickWidgetIntents.swift"), encoding: .utf8)
        XCTAssertTrue(intents.contains("SidekickWidgetTapQueue.queue(action"), "the intent queues the tap")
        XCTAssertTrue(intents.contains("reloadWidget: SidekickWidgetTapQueue.reloadSidekickTimelines"), "and reloads the widget")
    }
}
