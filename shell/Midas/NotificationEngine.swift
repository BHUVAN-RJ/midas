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
    /// AlarmKit, nil before iOS 26 (and in tests that do not need it).
    private let alarms: AlarmBooking?
    /// Each Sidekick's name as on its home tile, the notifications' subtitle.
    private let sidekickNames: @MainActor () -> [String: String]
    private let stateFileURL: URL
    private let calendarProvider: @MainActor () -> Calendar
    private let clock: @MainActor () -> Date
    private var state: NotificationEngineState
    private var latestRefresh: Task<Void, Never>?

    init(store: LocalRecordStore, booking: NotificationBooking, stateFileURL: URL,
         calendarProvider: @escaping @MainActor () -> Calendar = NotificationEngine.currentPhoneCalendar,
         clock: @escaping @MainActor () -> Date = NotificationEngine.currentTime,
         alarms: AlarmBooking? = nil,
         sidekickNames: @escaping @MainActor () -> [String: String] = NotificationEngine.noSidekickNames) {
        self.store = store
        self.recordWriter = RecordWriter(store: store)
        self.booking = booking
        self.alarms = alarms
        self.sidekickNames = sidekickNames
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

    static func noSidekickNames() -> [String: String] {
        [:]
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
        await writeChange(named: action.rawValue, for: identity) { currentValue, part, occurrence, now, calendar in
            action.patch(for: currentValue, part: part, occurrence: occurrence, now: now, calendar: calendar)
        }
    }

    /// An alarm reminder's button (founder, 2026-10-24). Done is the notification's Done. Snooze
    /// starts the countdown card and writes the snooze as the notification's Snooze does, 9
    /// minutes out, the time the countdown rings again. Stop ends the alarm or the countdown and
    /// removes a pending snooze, so it does not ring again; the reminder stays as it is.
    func handleAlarm(button: AlarmReminderButton, for identity: ReminderIdentity, alarmId: UUID?) async {
        switch button {
        case .done:
            if let alarmId {
                alarms?.stop(alarmIds: [alarmId])
            }
            await handle(action: .done, for: identity)
        case .snooze:
            if let alarmId {
                alarms?.startCountdown(alarmIds: [alarmId])
            }
            await writeChange(named: "alarm snooze", for: identity) { _, part, _, now, _ in
                ReminderChange.snoozePatch(until: now.addingTimeInterval(AlarmReminderShared.snoozeSeconds), part: part)
            }
        case .stop:
            if let alarmId {
                alarms?.stop(alarmIds: [alarmId])
            }
            await writeChange(named: "alarm stop", for: identity) { currentValue, part, _, _, _ in
                ReminderChange.snoozeRemovalPatch(for: currentValue, part: part)
            }
        }
    }

    /// Writes one button's change into the item record, then re-plans. Nil from `makePatch`
    /// means nothing to change.
    private func writeChange(named changeName: String, for identity: ReminderIdentity,
                             makePatch: (JSONValue, ReminderExpansion.Part, Date?, Date, Calendar) -> JSONValue?) async {
        let (itemId, part) = ReminderExpansion.split(reminderId: identity.reminderId)
        let key = ReminderRecord.keyPrefix + itemId
        guard let currentValue = store.get(sidekickId: identity.sidekickId, key: key) else {
            await refresh()
            return
        }
        let now = clock()
        let calendar = calendarProvider()
        let occurrence = occurrenceServed(by: part, of: currentValue, sidekickId: identity.sidekickId, key: key, now: now, calendar: calendar)
        // The store's change observer schedules a refresh too; this one makes the caller wait
        // until the new booking is in place (iOS ends the app's background time after).
        if let patch = makePatch(currentValue, part, occurrence, now, calendar) {
            do {
                try recordWriter.update(sidekickId: identity.sidekickId, key: key, patch: patch)
            } catch {
                Self.logger.error("notification \(changeName, privacy: .public) on \(key, privacy: .public) refused: \(String(describing: error), privacy: .public)")
            }
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
        let alarmsAllowed = await alarmsAllowed(for: records)
        let planner = ReminderPlanner(schedule: ReminderSchedule(calendar: calendarProvider()))
        let plan = planner.plan(records: records, ledger: state.ledger, previousBookings: state.bookings, now: now,
                                sidekickNames: sidekickNames(), alarmsAllowed: alarmsAllowed)
        var notificationBookings: [PlannedBooking] = []
        var alarmBookings: [PlannedBooking] = []
        for plannedBooking in plan.bookings {
            if plannedBooking.level == .alarm {
                alarmBookings.append(plannedBooking)
            } else {
                notificationBookings.append(plannedBooking)
            }
        }

        // Permission is asked the first time there is something to book.
        let hasSomethingToBook = !notificationBookings.isEmpty
        let isAuthorized = hasSomethingToBook ? await booking.requestAuthorizationIfNeeded() : true
        let appliedNotifications = isAuthorized ? await apply(notificationBookings) : []
        let appliedAlarms = await applyAlarms(alarmBookings)
        // Assigned field by field: a listened write noted while this run waited on iOS stays.
        state.ledger = plan.ledger
        state.bookings = appliedNotifications + appliedAlarms
        forgetOldListenWrites(now: now)
        saveState()
    }

    /// AlarmKit is asked once, the first time an Alarm reminder needs booking (founder,
    /// 2026-10-24). Declined, or no AlarmKit (before iOS 26): Alarm reminders are Time Sensitive
    /// notifications.
    private func alarmsAllowed(for records: [ReminderRecord]) async -> Bool {
        guard let alarms else {
            return false
        }
        var needsAnAlarm = false
        for record in records where record.reminderType == .alarm && !record.done {
            needsAnAlarm = true
            break
        }
        guard needsAnAlarm else {
            return false
        }
        return await alarms.requestAuthorizationIfNeeded()
    }

    /// Makes AlarmKit hold exactly the planned alarms, leaving alone what the person is in the
    /// middle of: a ringing alarm, and the countdown after Snooze while the record still holds that
    /// snooze. Returns the alarms AlarmKit holds for the plan.
    private func applyAlarms(_ plannedAlarms: [PlannedBooking]) async -> [PlannedBooking] {
        guard let alarms else {
            return []
        }
        let held = await alarms.heldAlarms()
        if held.isEmpty && plannedAlarms.isEmpty {
            return []
        }
        var identityByAlarmId: [UUID: ReminderIdentity] = [:]
        var previousById: [String: PlannedBooking] = [:]
        var previousByAlarmId: [UUID: PlannedBooking] = [:]
        for previousBooking in state.bookings where previousBooking.level == .alarm {
            let alarmId = AlarmIdentifier.uuid(for: previousBooking.identifier)
            identityByAlarmId[alarmId] = previousBooking.identity
            previousById[previousBooking.identifier] = previousBooking
            previousByAlarmId[alarmId] = previousBooking
        }
        var plannedAlarmIds: Set<UUID> = []
        var snoozedIdentities: Set<ReminderIdentity> = []
        for plannedAlarm in plannedAlarms {
            let alarmId = AlarmIdentifier.uuid(for: plannedAlarm.identifier)
            plannedAlarmIds.insert(alarmId)
            identityByAlarmId[alarmId] = plannedAlarm.identity
            if plannedAlarm.kind == .snooze {
                snoozedIdentities.insert(plannedAlarm.identity)
            }
        }

        var alarmsToStop: [UUID] = []
        var alarmsToCancel: [UUID] = []
        var countingDownIdentities: Set<ReminderIdentity> = []
        // Ringing or counting-down alarms whose time has passed are no longer planned; they stay
        // in the engine's state so a later run still knows whose they are.
        var keptUnplanned: [PlannedBooking] = []
        for (alarmId, heldState) in held {
            let identity = identityByAlarmId[alarmId]
            let isPlanned = plannedAlarmIds.contains(alarmId)
            switch heldState {
            case .alerting:
                // Ringing now: the person's Stop or Snooze ends it.
                if !isPlanned, let previousBooking = previousByAlarmId[alarmId] {
                    keptUnplanned.append(previousBooking)
                }
            case .countingDown:
                // The countdown stands for the record's snooze; once that is gone (Done, Stop, an
                // edit from the page) it ends. A planned weekly alarm keeps its schedule.
                if let identity, snoozedIdentities.contains(identity) {
                    countingDownIdentities.insert(identity)
                    if !isPlanned, let previousBooking = previousByAlarmId[alarmId] {
                        keptUnplanned.append(previousBooking)
                    }
                } else if plannedAlarmIds.contains(alarmId) {
                    alarmsToStop.append(alarmId)
                } else {
                    alarmsToCancel.append(alarmId)
                }
            case .scheduled:
                if !plannedAlarmIds.contains(alarmId) {
                    alarmsToCancel.append(alarmId)
                }
            }
        }
        if !alarmsToStop.isEmpty {
            alarms.stop(alarmIds: alarmsToStop)
        }
        if !alarmsToCancel.isEmpty {
            alarms.cancel(alarmIds: alarmsToCancel)
        }

        var acceptedAlarms: [PlannedBooking] = keptUnplanned
        for plannedAlarm in plannedAlarms {
            let alarmId = AlarmIdentifier.uuid(for: plannedAlarm.identifier)
            // The countdown after Snooze already rings again at the snooze time.
            if plannedAlarm.kind == .snooze && countingDownIdentities.contains(plannedAlarm.identity) {
                acceptedAlarms.append(plannedAlarm)
                continue
            }
            let heldState = held[alarmId]
            let isUnchanged = previousById[plannedAlarm.identifier] == plannedAlarm
            if heldState == .alerting || heldState == .countingDown || (heldState == .scheduled && isUnchanged) {
                acceptedAlarms.append(plannedAlarm)
                continue
            }
            // An edit (title, Sidekick name) replaces the alarm under the same id.
            if heldState == .scheduled {
                alarms.cancel(alarmIds: [alarmId])
            }
            do {
                try await alarms.book(plannedAlarm)
                acceptedAlarms.append(plannedAlarm)
            } catch {
                Self.logger.error("alarm \(plannedAlarm.identifier, privacy: .public) refused: \(String(describing: error), privacy: .public)")
            }
        }
        return acceptedAlarms
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
