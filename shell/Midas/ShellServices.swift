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
    let remindersWidget: RemindersWidgetPublisher
    let sidekickWidgets: SidekickWidgetPublisher

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

    private init() {
        let store = LocalRecordStore(fileURL: LocalRecordStore.defaultFileURL())
        self.store = store
        self.storeChannel = SidekickStoreChannel(store: store, reservedValidators: Self.reservedRecordValidators)
        self.notificationEngine = NotificationEngine(store: store, booking: UserNotificationBooking(), stateFileURL: NotificationEngine.defaultStateFileURL())
        let directoryFetcher = RemoteSidekickDirectoryFetcher(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        let directoryCacheURL = SidekickDirectory.defaultCacheFileURL(platformOrigin: PlatformConfig.platformOrigin)
        let directory = SidekickDirectory(cacheFileURL: directoryCacheURL, fetcher: directoryFetcher)
        self.directory = directory
        self.router = SidekickRouter(directory: directory)
        let syncAPI = RemoteRecordSyncAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        self.recordSync = RecordSync(store: store, api: syncAPI)
        self.recordSync.startSyncingAfterWrites()
        let remindersImport = AppleRemindersImportCenter(store: store, source: EventKitRemindersSource())
        self.remindersImport = remindersImport
        self.storeChannel.requestObserver = remindersImport.handleRequestWritten
        // The Reminders widget's Today list: written at launch and on every reminder or list change.
        let remindersWidget = RemindersWidgetPublisher.live(store: store, directory: directory)
        self.remindersWidget = remindersWidget
        remindersWidget.startWatchingStore()
        remindersWidget.publish()
        // The Sidekick widget: every Sidekick's `widget:` records, filled from its records.
        let sidekickWidgets = SidekickWidgetPublisher.live(store: store, directory: directory)
        self.sidekickWidgets = sidekickWidgets
        sidekickWidgets.startWatchingStore()
        sidekickWidgets.publish()
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
    func open(sidekickId: String) {
        guard let entry = directory.entry(withId: sidekickId) else {
            return
        }
        path = [entry]
    }

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
            // Ticks queued by the Reminders widget are retried here too, then the widget redrawn.
            ShellServices.shared.remindersWidget.publish()
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
        let engine = ShellServices.shared.notificationEngine
        engine.startWatchingStore()
        Task { @MainActor in
            await engine.refresh()
        }
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // A reminder fired while Midas is open: one slot freed, so top the batch up.
        await Self.refreshEngine()
        return [.banner, .list, .sound]
    }

    @MainActor
    private static func refreshEngine() async {
        await ShellServices.shared.notificationEngine.refresh()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let actionIdentifier = response.actionIdentifier
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        await Self.handleResponse(actionIdentifier: actionIdentifier, payload: payload)
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
