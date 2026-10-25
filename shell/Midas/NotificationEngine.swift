import Foundation
import OSLog

/// What the engine remembers between runs: the ledger (which occurrences were handled) and the
/// bookings it last handed to iOS.
struct NotificationEngineState: Codable, Equatable, Sendable {
    var ledger: ReminderLedger = [:]
    var bookings: [PlannedBooking] = []
    /// When a record some reminder listens to was last written, by "<sidekickId>|<key>"
    /// (hydration plan N2). Optional so a state saved before listening existed still loads.
    var listenWrites: [String: Date]? = nil
}

/// The shell's notification engine. Midas keeps its own unlimited queue (every `reminder:`
/// record of every Sidekick, in the local store), books only the soonest batch with iOS, and
/// tops it up whenever the app gets to run: app opened, a reminder written, a notification
/// acted on, background refresh. Each run re-plans from scratch and applies only the difference.
@MainActor
final class NotificationEngine {
    private let store: LocalRecordStore
    private let recordWriter: RecordWriter
    private let booking: NotificationBooking
    private let stateFileURL: URL
    private let calendarProvider: @MainActor () -> Calendar
    private let clock: @MainActor () -> Date
    private var state: NotificationEngineState
    private var latestRefresh: Task<Void, Never>?

    init(store: LocalRecordStore, booking: NotificationBooking, stateFileURL: URL,
         calendarProvider: @escaping @MainActor () -> Calendar = NotificationEngine.currentPhoneCalendar,
         clock: @escaping @MainActor () -> Date = NotificationEngine.currentTime) {
        self.store = store
        self.recordWriter = RecordWriter(store: store)
        self.booking = booking
        self.stateFileURL = stateFileURL
        self.calendarProvider = calendarProvider
        self.clock = clock
        self.state = Self.loadState(from: stateFileURL)
    }

    static func defaultStateFileURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "midas-notification-engine.json")
    }

    static func currentPhoneCalendar() -> Calendar {
        ReminderSchedule.phoneCalendar(timeZone: .current)
    }

    static func currentTime() -> Date {
        Date()
    }

    var currentState: NotificationEngineState {
        state
    }

    /// Re-plans whenever a Sidekick writes or deletes a reminder, or a record a reminder listens
    /// to (its listened record or its goal; hydration plan N2).
    func startWatchingStore() {
        store.addChangeObserver(handleStoreChange)
    }

    private func handleStoreChange(_ change: LocalRecordChange) {
        if !change.key.hasPrefix(ReminderRecord.keyPrefix) {
            guard noteListenedChange(change) else {
                return
            }
        }
        Task { @MainActor in
            await self.refresh()
        }
    }

    /// True when a reminder of the same Sidekick listens to the changed record or reads its goal
    /// from it. A write to a listened record is remembered: it starts that reminder's quiet.
    private func noteListenedChange(_ change: LocalRecordChange) -> Bool {
        let now = clock()
        let calendar = calendarProvider()
        var isListened = false
        for listen in listens(ofSidekick: change.sidekickId) {
            if listen.listenedKey(at: now, calendar: calendar) == change.key {
                var listenWrites = state.listenWrites ?? [:]
                listenWrites[Self.listenWriteKey(sidekickId: change.sidekickId, key: change.key)] = now
                state.listenWrites = listenWrites
                saveState()
                isListened = true
            } else if listen.goalKey == change.key {
                isListened = true
            }
        }
        return isListened
    }

    /// What the Sidekick's reminders listen to.
    private func listens(ofSidekick sidekickId: String) -> [ReminderListen] {
        var sidekickListens: [ReminderListen] = []
        for storedRecord in store.query(sidekickId: sidekickId, keyPrefix: ReminderRecord.keyPrefix) {
            if let listen = ReminderRecord.parse(sidekickId: sidekickId, key: storedRecord.key, value: storedRecord.value)?.listen {
                sidekickListens.append(listen)
            }
        }
        return sidekickListens
    }

    static func listenWriteKey(sidekickId: String, key: String) -> String {
        "\(sidekickId)|\(key)"
    }

    /// Runs one full plan-and-apply pass. Calls made while a pass is running queue up behind
    /// it, so passes never interleave and the last one always sees the latest records.
    func refresh() async {
        let previousRefresh = latestRefresh
        let thisRefresh = Task { @MainActor in
            await previousRefresh?.value
            await self.performRefresh()
        }
        latestRefresh = thisRefresh
        await thisRefresh.value
    }

    /// Applies a notification button press to the reminder record, then re-plans. A notification
    /// for an early alert (`<id>~<rule>`) or an hourly time (`<id>@HHMM`) belongs to the item
    /// record `reminder:<id>`; the change lands there (ReminderExpansion).
    func handle(action: ReminderAction, for identity: ReminderIdentity) async {
        let (itemId, part) = ReminderExpansion.split(reminderId: identity.reminderId)
        let key = ReminderRecord.keyPrefix + itemId
        guard let currentValue = store.get(sidekickId: identity.sidekickId, key: key) else {
            return
        }
        let now = clock()
        let calendar = calendarProvider()
        let occurrence = occurrenceServed(by: part, of: currentValue, sidekickId: identity.sidekickId, key: key, now: now, calendar: calendar)
        let patch = action.patch(for: currentValue, part: part, occurrence: occurrence, now: now, calendar: calendar)
        // The store's change observer schedules a refresh too; this one makes the caller wait
        // until the new booking is in place (iOS ends the app's background time after).
        do {
            try recordWriter.update(sidekickId: identity.sidekickId, key: key, patch: patch)
        } catch {
            Self.logger.error("notification \(action.rawValue, privacy: .public) on \(key, privacy: .public) refused: \(String(describing: error), privacy: .public)")
        }
        await refresh()
    }

    private static let logger = Logger(subsystem: "com.bhuvanrj.midas", category: "NotificationEngine")

    /// The occurrence a notification was for: an early alert serves the item's target
    /// occurrence; the item itself the latest occurrence at or before now.
    private func occurrenceServed(by part: ReminderExpansion.Part, of value: JSONValue, sidekickId: String, key: String, now: Date, calendar: Calendar) -> Date? {
        guard let record = ReminderRecord.parse(sidekickId: sidekickId, key: key, value: value) else {
            return nil
        }
        let schedule = ReminderSchedule(calendar: calendar)
        let expansion = ReminderExpansion(schedule: schedule)
        switch part {
        case .alert:
            return expansion.targetOccurrence(of: record, now: now)
        case .item, .slot:
            return schedule.latestOccurrence(of: record, after: .distantPast, notAfter: now) ?? record.at
        }
    }

    private func performRefresh() async {
        let records = currentReminderRecords()
        let now = clock()
        let planner = ReminderPlanner(schedule: ReminderSchedule(calendar: calendarProvider()))
        let plan = planner.plan(records: records, ledger: state.ledger, previousBookings: state.bookings, now: now)

        // Permission is asked the first time there is something to book.
        let hasSomethingToBook = !plan.bookings.isEmpty
        let isAuthorized = hasSomethingToBook ? await booking.requestAuthorizationIfNeeded() : true
        let appliedBookings = isAuthorized ? await apply(plan.bookings) : []
        // Assigned field by field: a listened write noted while this run waited on iOS stays.
        state.ledger = plan.ledger
        state.bookings = appliedBookings
        forgetOldListenWrites(now: now)
        saveState()
    }

    /// Every stored reminder, each expanded into the notifications it stands for (its own time,
    /// its hourly times, its early alerts). A listening reminder's repeats carry its quiet.
    private func currentReminderRecords() -> [ReminderRecord] {
        let storedRecords = store.queryAllSidekicks(keyPrefix: ReminderRecord.keyPrefix)
        let calendar = calendarProvider()
        let expansion = ReminderExpansion(schedule: ReminderSchedule(calendar: calendar))
        let now = clock()
        var reminderRecords: [ReminderRecord] = []
        for storedRecord in storedRecords {
            // Records were validated on write; anything unparseable is skipped, not fatal.
            guard let reminderRecord = ReminderRecord.parse(sidekickId: storedRecord.sidekickId, key: storedRecord.key, value: storedRecord.value) else {
                continue
            }
            guard let listen = reminderRecord.listen else {
                reminderRecords.append(contentsOf: expansion.expand(reminderRecord, now: now))
                continue
            }
            let quietUntil = self.quietUntil(of: listen, sidekickId: storedRecord.sidekickId, now: now, calendar: calendar)
            for var expandedRecord in expansion.expand(reminderRecord, now: now) {
                // The item and its hourly times; early alerts are one-time and stay as they are.
                if expandedRecord.repeatRule != nil {
                    expandedRecord.listen = listen
                    expandedRecord.quietUntil = quietUntil
                }
                reminderRecords.append(expandedRecord)
            }
        }
        return reminderRecords
    }

    /// Until when a listening reminder stays quiet now: from today's listened record, its goal
    /// and the last write to it (ReminderListen.quietUntil).
    private func quietUntil(of listen: ReminderListen, sidekickId: String, now: Date, calendar: Calendar) -> Date? {
        let listenedKey = listen.listenedKey(at: now, calendar: calendar)
        let listenedValue = store.get(sidekickId: sidekickId, key: listenedKey)
        var goalValue: JSONValue?
        if let goalKey = listen.goalKey {
            goalValue = store.get(sidekickId: sidekickId, key: goalKey)
        }
        let lastWriteAt = state.listenWrites?[Self.listenWriteKey(sidekickId: sidekickId, key: listenedKey)]
        return listen.quietUntil(listenedValue: listenedValue, goalValue: goalValue, lastWriteAt: lastWriteAt, now: now, calendar: calendar)
    }

    /// Writes older than the longest quiet can no longer keep anything quiet.
    private func forgetOldListenWrites(now: Date) {
        guard let listenWrites = state.listenWrites else {
            return
        }
        let oldest = now.addingTimeInterval(-Double(ReminderListen.maximumQuietMinutes) * 60)
        var recentWrites: [String: Date] = [:]
        for (writeKey, writtenAt) in listenWrites where writtenAt >= oldest {
            recentWrites[writeKey] = writtenAt
        }
        state.listenWrites = recentWrites.isEmpty ? nil : recentWrites
    }

    /// Makes iOS hold exactly the planned reminder bookings. Only identifiers with the
    /// reminder prefix are touched. Returns the bookings iOS accepted; one it refused is left
    /// out so the ledger never counts it as delivered.
    private func apply(_ plannedBookings: [PlannedBooking]) async -> [PlannedBooking] {
        let allPending = await booking.pendingIdentifiers()
        var pendingReminderIds: Set<String> = []
        for identifier in allPending where identifier.hasPrefix(PlannedBooking.identifierPrefix) {
            pendingReminderIds.insert(identifier)
        }
        var previousById: [String: PlannedBooking] = [:]
        for previousBooking in state.bookings {
            previousById[previousBooking.identifier] = previousBooking
        }
        var plannedIds: Set<String> = []
        for plannedBooking in plannedBookings {
            plannedIds.insert(plannedBooking.identifier)
        }

        // A missed reminder fires a second after booking; cancelling it would swallow it.
        var identifiersToCancel: [String] = []
        for pendingId in pendingReminderIds.sorted() where !plannedIds.contains(pendingId) {
            let isMissedNotice = previousById[pendingId]?.kind == .missed
            if !isMissedNotice {
                identifiersToCancel.append(pendingId)
            }
        }
        if !identifiersToCancel.isEmpty {
            booking.cancel(identifiers: identifiersToCancel)
        }

        var acceptedBookings: [PlannedBooking] = []
        for plannedBooking in plannedBookings {
            let isAlreadyPending = pendingReminderIds.contains(plannedBooking.identifier)
            let isUnchanged = previousById[plannedBooking.identifier] == plannedBooking
            if isAlreadyPending && isUnchanged {
                acceptedBookings.append(plannedBooking)
                continue
            }
            // Booking under the same identifier replaces the old one; that is how edits land.
            do {
                try await booking.book(plannedBooking)
                acceptedBookings.append(plannedBooking)
            } catch {
                continue
            }
        }
        return acceptedBookings
    }

    private func saveState() {
        guard let encodedState = try? JSONEncoder().encode(state) else {
            return
        }
        let directory = stateFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? encodedState.write(to: stateFileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func loadState(from fileURL: URL) -> NotificationEngineState {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return NotificationEngineState()
        }
        let decodedState = try? JSONDecoder().decode(NotificationEngineState.self, from: fileData)
        return decodedState ?? NotificationEngineState()
    }
}
