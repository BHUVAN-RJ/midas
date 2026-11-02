import BackgroundTasks
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// The shell's long-lived pieces, created once at launch.
@MainActor
final class ShellServices {
    static let shared = ShellServices()

    let store: LocalRecordStore
    let storeChannel: SidekickStoreChannel
    let notificationEngine: NotificationEngine
    let directory: SidekickDirectory
    let router: SidekickRouter
    let recordSync: RecordSync
    let remindersImport: AppleRemindersImportCenter
    /// "Add to Home Screen": the sheet a Sidekick asks for (founder, 2026-10-26).
    let homeScreenWidgets: HomeScreenWidgetCenter
    let repairUploader: RepairUploader
    let sidekickWidgets: SidekickWidgetPublisher
    /// "Ask jess": the Listening screen, the parse call, the save and the banner.
    let voiceReminders: VoiceReminderFlow
    /// The one record validator (shell/sdk/record-schema.js in JavaScriptCore); every write
    /// passes through `recordGate` before it is stored.
    let recordSchema: RecordSchemaEngine
    let recordGate: RecordWriteGate
    /// Each Sidekick's tools.js per version, run in JavaScriptCore for the jess router.
    let sidekickTools: SidekickToolsLibrary
    /// Shows, after a sync, what came of requests jess sent to repair (jess grows the Sidekick).
    let jessGrowFollowUp: JessGrowFollowUp
    /// jess's requests, finished in the background, and their result cards on the home page.
    let jessResults: JessResults
    /// Turns a Workdesk card waiting on a plain repair green once the repair is done.
    let jessRepairFollowUp: JessRepairFollowUp
    /// A cut-off jess request is sent again when the network comes back.
    let jessNetworkWatch: JessNetworkWatch
    /// Repairs sent from a Sidekick and what came of them: the Repair tag (founder, 2026-10-23).
    let repairCenter: RepairCenter
    /// Make and the founder's Inbox (founder, 2026-10-24, docs/briefs/make-contract.md).
    let make: MakeCenter
    /// Notifications permission and the push token for Make.
    let pushRegistration: PushRegistration
    /// Settings: deleting a Sidekick, Sign Out, Delete Account (founder, 2026-10-31).
    let account: AccountCenter
    /// "Allow AI?" (Apple 5.1.2(i), founder 2026-11-02): asked before jess or Edit sends anything.
    let aiConsent: AIConsentCenter

    /// Records the shell reads, checked when a Sidekick writes them: a bad reminder or a broken
    /// `widget:` description is refused with the reason.
    static let reservedRecordValidators: [String: ReservedRecordValidator] = [
        ReminderRecord.keyPrefix: ReminderRecord.validationError,
        SidekickWidgetShared.recordPrefix: SidekickWidgetDescription.validationError,
    ]

    /// The session token the signed-in user holds, for requests the shell makes on their behalf.
    nonisolated static func currentSessionToken() -> String? {
        KeychainSessionStore().loadToken()
    }

    /// The session token for jess and Edit requests, which send data to AI: none until the person
    /// tapped Allow (AIConsent.swift), so nothing reaches OpenRouter or Anthropic before that.
    nonisolated static func aiRequestSessionToken() -> String? {
        AIConsentRules.tokenForAIRequest(memory: AIConsentMemory(), sessionToken: currentSessionToken)
    }

    private init() {
        let aiConsent = AIConsentCenter()
        self.aiConsent = aiConsent
        let store = LocalRecordStore(fileURL: LocalRecordStore.defaultFileURL())
        self.store = store
        self.storeChannel = SidekickStoreChannel(store: store, reservedValidators: Self.reservedRecordValidators)
        let directoryFetcher = RemoteSidekickDirectoryFetcher(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        let directoryCacheURL = SidekickDirectory.defaultCacheFileURL(platformOrigin: PlatformConfig.platformOrigin)
        let directory = SidekickDirectory(cacheFileURL: directoryCacheURL, fetcher: directoryFetcher)
        self.directory = directory
        self.router = SidekickRouter(directory: directory)
        // The notifications' subtitle is the Sidekick's name as on its home tile (layout A, founder
        // 2026-10-24); Alarm reminders ring through AlarmKit on iOS 26 and later.
        func sidekickNames() -> [String: String] {
            var names: [String: String] = [:]
            for entry in directory.entries {
                names[entry.id] = entry.name
            }
            return names
        }
        self.notificationEngine = NotificationEngine(store: store, booking: UserNotificationBooking(), stateFileURL: NotificationEngine.defaultStateFileURL(),
                                                     alarms: AlarmBookingFactory.live(), sidekickNames: sidekickNames)
        // The validator ships with the app; without it no write could be checked, so a missing
        // or broken script is a build error, not something to carry on from.
        let recordSchema: RecordSchemaEngine
        do {
            recordSchema = try RecordSchemaEngine()
        } catch {
            fatalError("record-schema.js could not be loaded: \(error)")
        }
        self.recordSchema = recordSchema
        let recordGate = RecordTypeGate.make(engine: recordSchema, directory: directory)
        self.recordGate = recordGate
        store.writeGate = recordGate
        store.sidekickVersionProvider = directory.version(forSidekickId:)
        let toolsFetcher = RemoteSidekickToolsFetcher(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        self.sidekickTools = SidekickToolsLibrary(cacheDirectoryURL: SidekickToolsLibrary.defaultCacheDirectoryURL(platformOrigin: PlatformConfig.platformOrigin), fetcher: toolsFetcher)
        // Files (plan section 7): saved on the phone, uploaded before the records that refer to them.
        let fileStore = FileStore(directoryURL: FileStore.defaultDirectoryURL())
        let fileTransfer = RemoteFileTransfer(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        self.storeChannel.fileStore = fileStore
        self.storeChannel.fileTransfer = fileTransfer
        let syncAPI = RemoteRecordSyncAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        self.recordSync = RecordSync(store: store, api: syncAPI, fileStore: fileStore, fileTransfer: fileTransfer)
        self.recordSync.startSyncingAfterWrites()
        let remindersImport = AppleRemindersImportCenter(store: store, source: EventKitRemindersSource())
        self.remindersImport = remindersImport
        let homeScreenWidgets = HomeScreenWidgetCenter(store: store)
        self.homeScreenWidgets = homeScreenWidgets
        let requestDispatch = ShellRequestDispatch(homeScreen: homeScreenWidgets, remindersImport: remindersImport)
        self.storeChannel.requestObserver = requestDispatch.handleRequestWritten
        // A page's Widget button shows only until its widget is on the Home Screen (founder, 2026-10-27)
        self.storeChannel.widgetPlacement = HomeScreenWidgetPlacement.live()
        // The Reminders widget was retired for the Sidekick widget (founder, 2026-10-26): its files go.
        RetiredRemindersWidgetFiles.remove()
        // Repair reports: queued on disk first, sent now or on a later launch.
        let repairAPI = RemoteRepairUploadAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.aiRequestSessionToken)
        let repairOutbox = RepairOutbox(directoryURL: RepairOutbox.defaultDirectoryURL())
        self.repairUploader = RepairUploader(api: repairAPI, outbox: repairOutbox)
        // The Sidekick widget: every Sidekick's `widget:` records, filled from its records.
        let sidekickWidgets = SidekickWidgetPublisher.live(store: store, directory: directory)
        self.sidekickWidgets = sidekickWidgets
        // Taps queued by the widget are written by the first publish, possibly long after they were
        // tapped: the engine watches the store from here so their write is noted, at the tap's time.
        let notificationEngine = self.notificationEngine
        notificationEngine.startWatchingStore()
        sidekickWidgets.writingQueuedTap = notificationEngine.noteWrites(tappedAt:_:)
        sidekickWidgets.startWatchingStore()
        sidekickWidgets.publish()
        let voiceAPI = RemoteVoiceReminderAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.aiRequestSessionToken)
        let jessAPI = RemoteJessRouter(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.aiRequestSessionToken)
        let jessRouter = JessRouter(dependencies: Self.liveJessRouterDependencies(store: store, directory: directory, tools: sidekickTools, api: jessAPI))
        let jessResults = JessResults(file: JessResultsFile(fileURL: JessResultsFile.defaultFileURL()), dependencies: Self.liveJessResultsDependencies(router: jessRouter))
        self.jessResults = jessResults
        var voiceDependencies = Self.liveVoiceReminderDependencies(store: store, api: voiceAPI)
        // jess router (founder, 2026-10-21): the Action button's Listening screen sends what was
        // said to jess, which runs one Sidekick tool, instead of only adding a reminder; it is
        // finished in the background and shown as a home page card (founder, 2026-10-22).
        func submitToJess(transcript: String, listenMs: Int) async {
            await jessResults.submit(transcript: transcript, listenMs: listenMs)
        }
        voiceDependencies.route = submitToJess
        // The jess screen opening is a chance to send a cut-off request again (founder, 2026-10-22)
        func resumeJessQueue() {
            Task { @MainActor in
                await jessResults.resume()
            }
        }
        voiceDependencies.opened = resumeJessQueue
        // "Allow AI?" before the Listening screen opens (founder, 2026-11-02, D1)
        func isAIAllowed() -> Bool {
            aiConsent.isAllowed
        }
        voiceDependencies.aiAllowed = isAIAllowed
        voiceDependencies.askForAI = aiConsent.run
        let voiceReminders = VoiceReminderFlow(dependencies: voiceDependencies)
        self.voiceReminders = voiceReminders
        let jessGrowFollowUp = JessGrowFollowUp(api: jessAPI, present: jessResults.present)
        // A grow's result goes to the card that waited on it
        jessGrowFollowUp.settle = jessResults.settleGrow
        self.jessGrowFollowUp = jessGrowFollowUp
        let repairNotices = RemoteJessRepairNotices(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        self.jessRepairFollowUp = JessRepairFollowUp(api: repairNotices, results: jessResults)
        let repairCenter = RepairCenter(notices: repairNotices, resender: repairUploader, sentReports: RepairOutbox(directoryURL: RepairCenter.defaultSentReportsURL()), file: RepairCenterFile(fileURL: RepairCenterFile.defaultFileURL()))
        // A fix that landed while the user was elsewhere: the listing (version, agent block) is
        // fetched again now, and the page itself loads fresh on the next open
        func refreshAfterFixAway(sidekickId: String) {
            Task { @MainActor in
                await directory.refresh()
            }
        }
        repairCenter.onFixedAway = refreshAfterFixAway
        repairCenter.startPolling()
        self.repairCenter = repairCenter
        let jessNetworkWatch = JessNetworkWatch(onBack: resumeJessQueue)
        self.jessNetworkWatch = jessNetworkWatch
        jessNetworkWatch.start()
        self.make = Self.makeCenter(store: store, recordSync: recordSync, recordGate: recordGate, storeChannel: storeChannel)
        let pushAPI = PushRegisterAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        func registerToken(_ body: PushRegisterAPI.Body) async {
            await pushAPI.register(body)
        }
        self.pushRegistration = PushRegistration(system: LivePushSystem(), send: registerToken)
        let accountAPI = RemoteAccountAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        self.account = AccountCenter(dependencies: Self.liveAccountDependencies(api: accountAPI, store: store, directory: directory, recordSync: recordSync, notificationEngine: notificationEngine, sidekickWidgets: sidekickWidgets, router: router))
    }

    /// The live steps of Settings' flows (AccountCenter).
    private static func liveAccountDependencies(api: RemoteAccountAPI, store: LocalRecordStore, directory: SidekickDirectory, recordSync: RecordSync, notificationEngine: NotificationEngine, sidekickWidgets: SidekickWidgetPublisher, router: SidekickRouter) -> AccountCenter.Dependencies {
        func syncNow() async {
            await recordSync.syncNow()
        }
        func removeSidekickOnServer(_ sidekickId: String) async throws {
            try await api.removeSidekick(id: sidekickId)
        }
        func forgetSidekickLocally(_ sidekickId: String) {
            try? store.forgetSidekick(sidekickId)
            directory.removeEntry(withId: sidekickId)
        }
        // A deleted Reminders' notifications are taken off, the widget redrawn, the list refetched
        func afterRecordsLeft() async {
            await notificationEngine.refresh()
            sidekickWidgets.publish()
            await directory.refresh()
        }
        func signOutOnServer() async throws {
            try await api.signOut()
        }
        func requestDeletionOnServer() async throws {
            try await api.requestAccountDeletion()
        }
        func eraseAccountLocally() {
            try? store.eraseAll()
            directory.clear()
            Task { @MainActor in
                await notificationEngine.refresh()
                sidekickWidgets.publish()
            }
        }
        func goHome() {
            router.goHome()
        }
        return AccountCenter.Dependencies(syncNow: syncNow, removeSidekickOnServer: removeSidekickOnServer, forgetSidekickLocally: forgetSidekickLocally, afterRecordsLeft: afterRecordsLeft, signOutOnServer: signOutOnServer, requestDeletionOnServer: requestDeletionOnServer, eraseAccountLocally: eraseAccountLocally, goHome: goHome)
    }

    /// Before the restore of a signed-in account: another account's records and list leave the
    /// phone first (LocalRecordStore.adoptOwner), and its notifications with them.
    func adoptAccount(userId: String) {
        let wasEmptied = (try? store.adoptOwner(userId)) ?? false
        guard wasEmptied else {
            return
        }
        directory.clear()
        let notificationEngine = self.notificationEngine
        let sidekickWidgets = self.sidekickWidgets
        Task { @MainActor in
            await notificationEngine.refresh()
            sidekickWidgets.publish()
        }
    }

    /// Make's records live in the shared store and sync with everything else. A DEBUG run with
    /// the seeds uses a store of its own that never syncs (`MakeSeeds`).
    private static func makeCenter(store: LocalRecordStore, recordSync: RecordSync, recordGate: @escaping RecordWriteGate, storeChannel: SidekickStoreChannel) -> MakeCenter {
        let api = MakeAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        func fileData(_ fileId: String) async -> Data? {
            await storeChannel.fileData(fileId: fileId)?.data
        }
        if MakeSeeds.isOn {
            let seedFile = URL.temporaryDirectory.appending(path: "midas-make-seeds.json")
            let seedStore = LocalRecordStore(fileURL: seedFile)
            seedStore.writeGate = recordGate
            MakeSeeds.fill(seedStore)
            func noSync() async {}
            let center = MakeCenter(store: seedStore, api: api, sync: noSync)
            center.fileData = fileData
            return center
        }
        func pull() async {
            guard currentSessionToken() != nil else {
                return
            }
            await recordSync.syncNow()
        }
        let center = MakeCenter(store: store, api: api, sync: pull)
        center.fileData = fileData
        return center
    }

    /// The real pieces behind jess's background requests: the router, iOS background time, the
    /// session and the clock.
    private static func liveJessResultsDependencies(router: JessRouter) -> JessResultsDependencies {
        func route(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
            await router.route(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone, onApplied: onApplied)
        }
        func isSignedIn() -> Bool {
            currentSessionToken() != nil
        }
        func isInForeground() -> Bool {
            UIApplication.shared.applicationState == .active
        }
        func now() -> Date {
            Date()
        }
        func timeZone() -> TimeZone {
            TimeZone.current
        }
        return JessResultsDependencies(route: route, backgroundTime: SystemJessBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    }

    /// The real pieces behind the jess router: the listed Sidekicks with an agent block, their
    /// tools.js from the library, their records from the phone's store, the one shell writer.
    private static func liveJessRouterDependencies(store: LocalRecordStore, directory: SidekickDirectory, tools: SidekickToolsLibrary, api: JessRouting) -> JessRouterDependencies {
        let writer = RecordWriter(store: store)
        func sidekicks() -> [JessSidekickSource] {
            var sources: [JessSidekickSource] = []
            for entry in directory.entries {
                guard let agent = directory.agent(forSidekickId: entry.id) else {
                    continue
                }
                sources.append(JessSidekickSource(id: entry.id, name: entry.name, version: entry.version, agent: agent))
            }
            return sources
        }
        func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
            try await tools.engine(sidekickId: sidekickId, version: version)
        }
        func records(sidekickId: String) -> [LocalRecord] {
            store.query(sidekickId: sidekickId, keyPrefix: "")
        }
        func apply(sidekickId: String, ops: [SidekickToolOp]) throws {
            try writer.apply(sidekickId: sidekickId, ops: ops)
        }
        func now() -> Date {
            Date()
        }
        func timeZone() -> TimeZone {
            TimeZone.current
        }
        func app() -> VoiceParseApp {
            let device = RepairDeviceInfo.current()
            return VoiceParseApp(version: device.appVersion, build: device.appBuild, ios: device.iosVersion, device: device.device)
        }
        func refreshDirectory() async {
            await directory.refresh()
        }
        func directoryVersion(sidekickId: String) -> String? {
            directory.version(forSidekickId: sidekickId)
        }
        return JessRouterDependencies(sidekicks: sidekicks, engine: engine, records: records, apply: apply, api: api, now: now, timeZone: timeZone, app: app, refreshDirectory: refreshDirectory, directoryVersion: directoryVersion)
    }

    /// The real pieces behind voice reminders: the shared on-device transcriber, the user's
    /// Reminders lists from the phone's store, and the one shell writer for the save.
    private static func liveVoiceReminderDependencies(store: LocalRecordStore, api: VoiceReminderParsing) -> VoiceReminderDependencies {
        let writer = RecordWriter(store: store)
        func isSignedIn() -> Bool {
            currentSessionToken() != nil
        }
        func lists() -> [VoiceReminderList] {
            VoiceReminderRecord.lists(in: store)
        }
        func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing {
            OnDeviceSpeechTranscriber(options: options, audioLevel: meter)
        }
        func save(_ reminder: VoiceResolvedReminder) throws {
            try VoiceReminderRecord.save(reminder, writer: writer, now: Date())
        }
        func now() -> Date {
            Date()
        }
        func timeZone() -> TimeZone {
            TimeZone.current
        }
        func app() -> VoiceParseApp {
            let device = RepairDeviceInfo.current()
            return VoiceParseApp(version: device.appVersion, build: device.appBuild, ios: device.iosVersion, device: device.device)
        }
        return VoiceReminderDependencies(isSignedIn: isSignedIn, lists: lists, makeTranscriber: makeTranscriber, api: api, save: save, now: now, timeZone: timeZone, app: app)
    }
}

/// Which Sidekick is open. Tapping a reminder notification or a widget tile opens the Sidekick
/// that owns it; a midas://home link goes back to the grid.
@MainActor
@Observable
final class SidekickRouter {
    var path: [SidekickEntry] = []
    private let directory: SidekickDirectory

    init(directory: SidekickDirectory) {
        self.directory = directory
    }

    /// Opens only a Sidekick the user has; a notification for one no longer listed is ignored.
    /// jess has no page: its link opens the Listening screen.
    func open(sidekickId: String) {
        guard let entry = listedEntry(withId: sidekickId) else {
            return
        }
        if JessSidekick.isJess(entry) {
            openJess()
            return
        }
        path = [entry]
    }

    /// The listed Sidekick, or Make's local entry in a DEBUG build before the server lists it.
    private func listedEntry(withId sidekickId: String) -> SidekickEntry? {
        let entries = MakeSidekick.listedEntries(directory.entries)
        for entry in entries where entry.id == sidekickId {
            return entry
        }
        return nil
    }

    /// A Make push for the person (a card, Built): Make, then that request's thread.
    func openMakeRequest(_ reqId: String, center: MakeCenter) {
        guard let entry = listedEntry(withId: MakeSidekick.id) else {
            return
        }
        center.pendingRequestId = reqId
        path = [entry]
    }

    /// A Make push for the founder (a person's message or answer): the Inbox, then that thread.
    func openInboxThread(userId: String, reqId: String, center: MakeCenter) {
        guard let entry = listedEntry(withId: MakeSidekick.inboxId) else {
            return
        }
        center.pendingInboxThread = MakeThreadRef(userId: userId, reqId: reqId)
        path = [entry]
    }

    /// Set by the shell to the Listening screen (MidasApp.openVoiceReminder).
    @ObservationIgnored var openJess: @MainActor () -> Void = MidasApp.openVoiceReminder

    /// Back to the home grid, whatever was open.
    func goHome() {
        path = []
    }
}

/// Lets the engine top up the booked batch even when the user does not open Midas. iOS decides
/// when (and whether) this runs; it is one of several chances, not a guarantee.
@MainActor
enum BackgroundRefresh {
    static let taskIdentifier = "com.bhuvanrj.midas.reminders-refresh"
    static let minimumInterval: TimeInterval = 60 * 60

    static func register() {
        // The main queue keeps the handler on the main actor, where the engine lives.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main, launchHandler: handleLaunch)
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handleLaunch(_ task: BGTask) {
        let taskBox = BackgroundTaskBox(task: task)
        MainActor.assumeIsolated {
            runRefresh(taskBox)
        }
    }

    private static func runRefresh(_ taskBox: BackgroundTaskBox) {
        scheduleNext()
        let refreshWork = Task { @MainActor in
            // Taps queued by the Sidekick widget are retried here too, then the widget redrawn.
            ShellServices.shared.sidekickWidgets.publish()
            await ShellServices.shared.notificationEngine.refresh()
            taskBox.task.setTaskCompleted(success: true)
        }
        taskBox.task.expirationHandler = refreshWork.cancel
    }
}

/// BGTask is not marked Sendable, but iOS allows completing it from any thread; the box lets the
/// refresh Task carry it.
private final class BackgroundTaskBox: @unchecked Sendable {
    let task: BGTask

    init(task: BGTask) {
        self.task = task
    }
}

/// Launch setup and the notification delegate: shows reminders while Midas is open, and turns
/// Done / Snooze / tap into record changes.
final class ShellAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        UserNotificationBooking.registerCategories(center: center)
        BackgroundRefresh.register()
        // Watching the store starts in ShellServices, before the widget's queued taps are written.
        let engine = ShellServices.shared.notificationEngine
        // Alarm reminders' buttons (Snooze, Done, Stop) run in this process (AlarmReminderShared).
        AlarmReminderIntentBridge.press = Self.handleAlarmButton
        Task { @MainActor in
            await engine.refresh()
        }
        return true
    }

    // The push token for Make: to the server on every launch.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            await ShellServices.shared.pushRegistration.didRegister(deviceToken: deviceToken)
        }
    }

    // No Push capability on the App ID, or no network: Make works without pushes.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {}

    // Both notification callbacks use the completion-handler form and call it on the main thread.
    // The async form hands the answer back to iOS from a background thread, and UIKit aborts the
    // app when that happens while Midas is in the background (crash 2026-10-26 21:00, Midas Test
    // build 18: a reminder button pressed from the lock screen, "abort() called" in
    // -[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let makePayload = MakePushPayload(userInfo: userInfo)
        Task { @MainActor in
            if let makePayload {
                let options = await Self.presentMake(makePayload)
                completionHandler(options)
                return
            }
            // A reminder fired while Midas is open: one slot freed, so top the batch up.
            await Self.refreshEngine()
            completionHandler([.banner, .list, .sound])
        }
    }

    /// A Make push while Midas is open: pull, so the thread has it, and show the banner unless
    /// that thread is already on screen.
    @MainActor
    private static func presentMake(_ payload: MakePushPayload) async -> UNNotificationPresentationOptions {
        let make = ShellServices.shared.make
        await make.sync()
        guard payload.showsBanner(openThread: make.openThread) else {
            return []
        }
        return [.banner, .list, .sound]
    }

    /// A tap on a Make push opens its thread: the person's request, or the founder's inbox thread.
    @MainActor
    private static func openMake(_ payload: MakePushPayload) async {
        let services = ShellServices.shared
        if payload.isForFounder {
            services.router.openInboxThread(userId: payload.userId, reqId: payload.requestId, center: services.make)
        } else {
            services.router.openMakeRequest(payload.requestId, center: services.make)
        }
        await services.make.sync()
    }

    @MainActor
    private static func handleAlarmButton(_ button: AlarmReminderButton, sidekickId: String, reminderId: String, alarmId: UUID?) async {
        let identity = ReminderIdentity(sidekickId: sidekickId, reminderId: reminderId)
        await ShellServices.shared.notificationEngine.handleAlarm(button: button, for: identity, alarmId: alarmId)
    }

    @MainActor
    private static func refreshEngine() async {
        await ShellServices.shared.notificationEngine.refresh()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let makePayload = MakePushPayload(userInfo: userInfo)
        let payload = NotificationPayload(userInfo: userInfo)
        Task { @MainActor in
            if let makePayload {
                await Self.openMake(makePayload)
            } else {
                await Self.handleResponse(actionIdentifier: actionIdentifier, payload: payload)
            }
            completionHandler()
        }
    }

    @MainActor
    private static func handleResponse(actionIdentifier: String, payload: NotificationPayload?) async {
        let services = ShellServices.shared
        guard let payload else {
            await services.notificationEngine.refresh()
            return
        }
        if let reminderAction = ReminderAction(rawValue: actionIdentifier) {
            await services.notificationEngine.handle(action: reminderAction, for: payload.identity)
            return
        }
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            services.router.open(sidekickId: payload.identity.sidekickId)
        }
        await services.notificationEngine.refresh()
    }
}
