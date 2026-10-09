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
    let router: SidekickRouter

    private init() {
        let store = LocalRecordStore(fileURL: LocalRecordStore.defaultFileURL())
        let reminderValidators: [String: ReservedRecordValidator] = [ReminderRecord.keyPrefix: ReminderRecord.validationError]
        self.store = store
        self.storeChannel = SidekickStoreChannel(store: store, reservedValidators: reminderValidators)
        self.notificationEngine = NotificationEngine(store: store, booking: UserNotificationBooking(), stateFileURL: NotificationEngine.defaultStateFileURL())
        self.router = SidekickRouter()
    }
}

/// Which Sidekick is open. Tapping a reminder notification opens the Sidekick that owns it.
@MainActor
@Observable
final class SidekickRouter {
    var path: [SidekickEntry] = []

    func open(sidekickId: String) {
        for entry in SidekickCatalog.all where entry.id == sidekickId {
            path = [entry]
            return
        }
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
