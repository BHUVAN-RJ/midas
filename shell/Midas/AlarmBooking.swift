@preconcurrency import AlarmKit
import CryptoKit
import Foundation
import SwiftUI

/// What an alarm held by iOS is doing right now.
enum HeldAlarmState: Equatable, Sendable {
    /// Waiting for its time.
    case scheduled
    /// Counting down after Snooze: the countdown card (L7) is on the Lock Screen.
    case countingDown
    /// Ringing now.
    case alerting
}

/// What the engine needs from AlarmKit (L5, founder 2026-10-24). The real one is
/// `AlarmKitBooking`; tests use a fake.
@MainActor
protocol AlarmBooking: AnyObject {
    /// Asks once, the first time an alarm reminder needs booking; false when declined.
    func requestAuthorizationIfNeeded() async -> Bool
    /// Every alarm Midas has with iOS, by its id.
    func heldAlarms() async -> [UUID: HeldAlarmState]
    func book(_ booking: PlannedBooking) async throws
    /// Removes alarms, schedule and all.
    func cancel(alarmIds: [UUID])
    /// Ends a ringing or counting-down alarm; a weekly alarm keeps its schedule.
    func stop(alarmIds: [UUID])
    /// Snooze: the ringing alarm becomes the countdown card.
    func startCountdown(alarmIds: [UUID])
}

/// AlarmKit ids are UUIDs; each booking's id is derived from its engine identifier, so the same
/// booking always has the same alarm and nothing needs remembering to find it again.
enum AlarmIdentifier {
    static func uuid(for identifier: String) -> UUID {
        let digest = SHA256.hash(data: Data(identifier.utf8))
        var bytes = Array(digest.prefix(16))
        // Version 5 style (name-based) and the RFC 4122 variant bits.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuidBytes = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                         bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuidBytes)
    }
}

enum AlarmBookingFactory {
    /// AlarmKit on iOS 26 and later; nil before, so Alarm reminders are booked as Time Sensitive
    /// notifications (founder, 2026-10-24).
    @MainActor
    static func live() -> AlarmBooking? {
        if #available(iOS 26.0, *) {
            return AlarmKitBooking()
        }
        return nil
    }
}

/// Books alarm reminders with AlarmKit: the ringing screen (Stop by iOS, Snooze ours) and, after
/// Snooze, the countdown card drawn by the widget extension (`AlarmCountdownActivity`).
@available(iOS 26.0, *)
@MainActor
final class AlarmKitBooking: AlarmBooking {
    private let manager: AlarmManager

    init(manager: AlarmManager = .shared) {
        self.manager = manager
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let answer = try? await manager.requestAuthorization()
            return answer == .authorized
        @unknown default:
            return false
        }
    }

    func heldAlarms() async -> [UUID: HeldAlarmState] {
        guard manager.authorizationState == .authorized, let alarms = try? manager.alarms else {
            return [:]
        }
        var held: [UUID: HeldAlarmState] = [:]
        for alarm in alarms {
            held[alarm.id] = Self.heldState(of: alarm.state)
        }
        return held
    }

    func book(_ booking: PlannedBooking) async throws {
        let alarmId = AlarmIdentifier.uuid(for: booking.identifier)
        let configuration = Self.configuration(for: booking, alarmId: alarmId)
        _ = try await manager.schedule(id: alarmId, configuration: configuration)
    }

    func cancel(alarmIds: [UUID]) {
        for alarmId in alarmIds {
            try? manager.cancel(id: alarmId)
        }
    }

    func stop(alarmIds: [UUID]) {
        for alarmId in alarmIds {
            try? manager.stop(id: alarmId)
        }
    }

    func startCountdown(alarmIds: [UUID]) {
        for alarmId in alarmIds {
            try? manager.countdown(id: alarmId)
        }
    }

    nonisolated static func heldState(of state: Alarm.State) -> HeldAlarmState {
        switch state {
        case .scheduled:
            return .scheduled
        case .countdown, .paused:
            return .countingDown
        case .alerting:
            return .alerting
        @unknown default:
            return .alerting
        }
    }

    /// The alarm for one booking: title the reminder's, Snooze starting a 9 minute countdown,
    /// white like the mockup's ringing screen.
    nonisolated static func configuration(for booking: PlannedBooking, alarmId: UUID) -> AlarmManager.AlarmConfiguration<MidasAlarmMetadata> {
        let title = LocalizedStringResource("\(booking.title)")
        let snoozeButton = AlarmButton(text: "Snooze", textColor: .black, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: snoozeButton, secondaryButtonBehavior: .countdown)
        } else {
            let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
            alert = AlarmPresentation.Alert(title: title, stopButton: stopButton, secondaryButton: snoozeButton, secondaryButtonBehavior: .countdown)
        }
        let countdown = AlarmPresentation.Countdown(title: title)
        let presentation = AlarmPresentation(alert: alert, countdown: countdown)
        let metadata = MidasAlarmMetadata(sidekickId: booking.identity.sidekickId, reminderId: booking.identity.reminderId,
                                          title: booking.title, sidekickName: booking.subtitle)
        let attributes = AlarmAttributes(presentation: presentation, metadata: metadata, tintColor: .white)
        let countdownDuration = Alarm.CountdownDuration(preAlert: nil, postAlert: AlarmReminderShared.snoozeSeconds)
        let stopIntent = StopAlarmReminderIntent(alarmId: alarmId, sidekickId: booking.identity.sidekickId, reminderId: booking.identity.reminderId)
        let snoozeIntent = SnoozeAlarmReminderIntent(alarmId: alarmId, sidekickId: booking.identity.sidekickId, reminderId: booking.identity.reminderId)
        return AlarmManager.AlarmConfiguration(countdownDuration: countdownDuration, schedule: schedule(for: booking), attributes: attributes,
                                               stopIntent: stopIntent, secondaryIntent: snoozeIntent, sound: .default)
    }

    /// A one-time moment is a fixed date; a repeating trigger (daily, or weekly on one weekday)
    /// is AlarmKit's weekly schedule at that time of day.
    nonisolated static func schedule(for booking: PlannedBooking) -> Alarm.Schedule {
        switch booking.trigger {
        case .date(let fireDate):
            return .fixed(fireDate)
        case .immediately:
            return .fixed(Date().addingTimeInterval(1))
        case .repeating(let components):
            let time = Alarm.Schedule.Relative.Time(hour: components.hour ?? 0, minute: components.minute ?? 0)
            let weekdays = alarmWeekdays(for: components)
            return .relative(Alarm.Schedule.Relative(time: time, repeats: .weekly(weekdays)))
        }
    }

    /// Calendar weekday (1 is Sunday) to AlarmKit's; no weekday means every day.
    nonisolated static func alarmWeekdays(for components: DateComponents) -> [Locale.Weekday] {
        let everyDay: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let weekday = components.weekday, weekday >= 1, weekday <= 7 else {
            return everyDay
        }
        return [everyDay[weekday - 1]]
    }
}
