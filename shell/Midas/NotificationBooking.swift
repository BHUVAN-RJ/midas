import Foundation
import UserNotifications

/// What the engine needs from iOS's notification center. The real one is
/// `UserNotificationBooking`; tests use a fake.
@MainActor
protocol NotificationBooking: AnyObject {
    /// Asks for permission the first time, then answers from the stored decision.
    func requestAuthorizationIfNeeded() async -> Bool
    func pendingIdentifiers() async -> [String]
    func book(_ booking: PlannedBooking) async throws
    func cancel(identifiers: [String])
}

/// Books Midas reminders with UNUserNotificationCenter. The shell owns notification permission:
/// asked once, for itself, never by a Sidekick.
@MainActor
final class UserNotificationBooking: NotificationBooking {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// The Done and Snooze buttons. Registered at launch, before any notification can arrive.
    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        var actions: [UNNotificationAction] = []
        for reminderAction in ReminderAction.allCases {
            let action = UNNotificationAction(identifier: reminderAction.rawValue, title: reminderAction.buttonTitle, options: [])
            actions.append(action)
        }
        let category = UNNotificationCategory(identifier: ReminderAction.categoryIdentifier, actions: actions, intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted ?? false
        @unknown default:
            return false
        }
    }

    func pendingIdentifiers() async -> [String] {
        let pendingRequests = await center.pendingNotificationRequests()
        var identifiers: [String] = []
        for pendingRequest in pendingRequests {
            identifiers.append(pendingRequest.identifier)
        }
        return identifiers
    }

    func book(_ booking: PlannedBooking) async throws {
        let content = Self.content(for: booking)
        let trigger = Self.trigger(for: booking)
        let request = UNNotificationRequest(identifier: booking.identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    nonisolated static func content(for booking: PlannedBooking) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        // Layout A (founder, 2026-10-24): title the reminder, subtitle the Sidekick, body the
        // time then the notes.
        content.title = booking.title
        content.subtitle = booking.subtitle
        content.body = booking.notificationBody
        content.interruptionLevel = interruptionLevel(for: booking.level)
        content.sound = .default
        content.categoryIdentifier = ReminderAction.categoryIdentifier
        // Groups notifications per Sidekick under Midas.
        content.threadIdentifier = booking.identity.sidekickId
        content.userInfo = NotificationPayload(identity: booking.identity).userInfo
        return content
    }

    /// Normal is Active (L2), Time Sensitive is L3. An alarm reaching here (it should not) is
    /// Time Sensitive. If the person turned Time Sensitive off for Midas, iOS delivers it as Active.
    nonisolated static func interruptionLevel(for level: BookingLevel) -> UNNotificationInterruptionLevel {
        switch level {
        case .active:
            return .active
        case .timeSensitive, .alarm:
            return .timeSensitive
        }
    }

    nonisolated static func trigger(for booking: PlannedBooking) -> UNNotificationTrigger {
        switch booking.trigger {
        case .immediately:
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        case .repeating(let components):
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .date(let fireDate):
            // Components carrying a time zone fire at that exact moment, even if the phone
            // changes zone or its clock is adjusted before then.
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let components = utcCalendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute, .second], from: fireDate)
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
    }
}

/// The reminder a notification belongs to, carried in its userInfo.
struct NotificationPayload: Equatable, Sendable {
    let identity: ReminderIdentity

    var userInfo: [String: String] {
        ["midasSidekickId": identity.sidekickId, "midasReminderId": identity.reminderId]
    }

    init(identity: ReminderIdentity) {
        self.identity = identity
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let sidekickId = userInfo["midasSidekickId"] as? String, let reminderId = userInfo["midasReminderId"] as? String else {
            return nil
        }
        self.identity = ReminderIdentity(sidekickId: sidekickId, reminderId: reminderId)
    }
}
