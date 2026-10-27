import AlarmKit
import AppIntents
import Foundation

// Alarm reminders (L5) and their countdown card after Snooze (L7), founder 2026-10-24 (brief
// docs/briefs/notification-levels.md). Compiled into the app and the widget extension: the
// widget draws the card from the metadata, and the card's buttons and the alarm's own buttons run
// these intents. LiveActivityIntent runs in the app's process, where the app has plugged in its
// handler at launch (as SidekickWidgetIntents.swift does for the Sidekick widget's taps).

/// The buttons of an alarm reminder: Snooze on the ringing alarm, Done and Stop on the countdown
/// card, Stop on the ringing alarm (drawn by iOS).
enum AlarmReminderButton: String, Sendable {
    case done
    case snooze
    case stop
}

enum AlarmReminderShared {
    /// Snooze on an alarm counts down 9 minutes, as Apple's Reminders and the mockup do
    /// (notification-levels-2026-10-24, L7: "rings again at 11:09 PM" for 11:00 PM).
    static let snoozeSeconds: TimeInterval = 9 * 60
}

/// What the countdown card shows, carried with the alarm.
@available(iOS 26.0, *)
struct MidasAlarmMetadata: AlarmMetadata {
    let sidekickId: String
    /// The engine's reminder id: the item's, or `<id>@HHMM` for an hourly time.
    let reminderId: String
    let title: String
    /// The Sidekick's name as on its home tile.
    let sidekickName: String
}

/// Where the app plugs in its alarm button handler at launch. Nil in the widget extension.
@MainActor
enum AlarmReminderIntentBridge {
    static var press: (@MainActor (_ button: AlarmReminderButton, _ sidekickId: String, _ reminderId: String, _ alarmId: UUID?) async -> Void)?
}

/// Runs one alarm button in the app.
@MainActor
private func pressAlarmButton(_ button: AlarmReminderButton, sidekickId: String, reminderId: String, alarmId: String) async {
    let alarmUUID = UUID(uuidString: alarmId)
    guard let pressHandler = AlarmReminderIntentBridge.press else {
        return
    }
    await pressHandler(button, sidekickId, reminderId, alarmUUID)
}

/// Snooze on the ringing alarm: starts the countdown card and writes the snooze into the record.
struct SnoozeAlarmReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm")
    var alarmId: String
    @Parameter(title: "Sidekick")
    var sidekickId: String
    @Parameter(title: "Reminder")
    var reminderId: String

    init() {}

    init(alarmId: UUID, sidekickId: String, reminderId: String) {
        self.alarmId = alarmId.uuidString
        self.sidekickId = sidekickId
        self.reminderId = reminderId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await pressAlarmButton(.snooze, sidekickId: sidekickId, reminderId: reminderId, alarmId: alarmId)
        return .result()
    }
}

/// Done on the countdown card: completes the reminder the way the notification's Done does.
struct DoneAlarmReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Alarm Reminder Done"
    static let isDiscoverable = false

    @Parameter(title: "Alarm")
    var alarmId: String
    @Parameter(title: "Sidekick")
    var sidekickId: String
    @Parameter(title: "Reminder")
    var reminderId: String

    init() {}

    init(alarmId: UUID, sidekickId: String, reminderId: String) {
        self.alarmId = alarmId.uuidString
        self.sidekickId = sidekickId
        self.reminderId = reminderId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await pressAlarmButton(.done, sidekickId: sidekickId, reminderId: reminderId, alarmId: alarmId)
        return .result()
    }
}

/// Stop, on the ringing alarm or on the countdown card: ends it without completing the reminder.
struct StopAlarmReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm")
    var alarmId: String
    @Parameter(title: "Sidekick")
    var sidekickId: String
    @Parameter(title: "Reminder")
    var reminderId: String

    init() {}

    init(alarmId: UUID, sidekickId: String, reminderId: String) {
        self.alarmId = alarmId.uuidString
        self.sidekickId = sidekickId
        self.reminderId = reminderId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await pressAlarmButton(.stop, sidekickId: sidekickId, reminderId: reminderId, alarmId: alarmId)
        return .result()
    }
}

/// The countdown card's words (mockup notification-levels-2026-10-24, L7).
enum AlarmCountdownCopy {
    /// "Reminders · rings again at 11:09 PM"; just "Rings again at 11:09 PM" without a name.
    static func subline(sidekickName: String, ringsAt: Date?, timeZone: TimeZone = .current, locale: Locale = .autoupdatingCurrent) -> String {
        guard let ringsAt else {
            return sidekickName
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let ringTime = formatter.string(from: ringsAt)
        guard !sidekickName.isEmpty else {
            return "Rings again at " + ringTime
        }
        return sidekickName + " · rings again at " + ringTime
    }

    /// "8:59" for what is left of a paused countdown.
    static func remainingText(seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    /// When the countdown rings again; nil when it is not counting down.
    @available(iOS 26.0, *)
    static func ringDate(of mode: AlarmPresentationState.Mode) -> Date? {
        guard case .countdown(let countdown) = mode else {
            return nil
        }
        return countdown.fireDate
    }
}
