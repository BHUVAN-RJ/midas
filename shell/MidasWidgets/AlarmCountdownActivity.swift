import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

// L7, the countdown card after Snooze on an alarm reminder (founder, 2026-10-24; mockup
// docs/mockups/notification-levels-2026-10-24.html section 3). AlarmKit runs the countdown as a
// Live Activity in this layout: the reminder, "Reminders · rings again at 11:09 PM", the time left
// ticking by itself, Done and Stop. Without this widget "the system may unexpectedly dismiss alarms
// and fail to alert" (Apple, Scheduling an alarm with AlarmKit).

@available(iOS 26.0, *)
struct AlarmCountdownActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<MidasAlarmMetadata>.self) { context in
            AlarmCountdownCard(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color(white: 0.08, opacity: 0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AlarmCountdownTitle(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmCountdownClock(state: context.state, size: 32)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AlarmCountdownButtons(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                AlarmCountdownClock(state: context.state, size: 15)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }
}

@available(iOS 26.0, *)
private struct AlarmCountdownCard: View {
    let attributes: AlarmAttributes<MidasAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                AlarmCountdownTitle(attributes: attributes, state: state)
                Spacer(minLength: 8)
                AlarmCountdownClock(state: state, size: 40)
            }
            AlarmCountdownButtons(attributes: attributes, state: state)
        }
        .foregroundStyle(.white)
    }
}

@available(iOS 26.0, *)
private struct AlarmCountdownTitle: View {
    let attributes: AlarmAttributes<MidasAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attributes.metadata?.title ?? "")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Text(AlarmCountdownCopy.subline(sidekickName: attributes.metadata?.sidekickName ?? "", ringsAt: AlarmCountdownCopy.ringDate(of: state.mode)))
                .font(.system(size: 13, weight: .medium))
                .opacity(0.7)
                .lineLimit(1)
        }
    }
}

/// The time left, ticking by itself; paused shows what was left.
@available(iOS 26.0, *)
private struct AlarmCountdownClock: View {
    let state: AlarmPresentationState
    let size: CGFloat

    var body: some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
            case .paused(let paused):
                Text(AlarmCountdownCopy.remainingText(seconds: paused.totalCountdownDuration - paused.previouslyElapsedDuration))
            case .alert:
                Text("0:00")
            @unknown default:
                Text("")
            }
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

@available(iOS 26.0, *)
private struct AlarmCountdownButtons: View {
    let attributes: AlarmAttributes<MidasAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        let sidekickId = attributes.metadata?.sidekickId ?? ""
        let reminderId = attributes.metadata?.reminderId ?? ""
        HStack(spacing: 10) {
            Button(intent: DoneAlarmReminderIntent(alarmId: state.alarmID, sidekickId: sidekickId, reminderId: reminderId)) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
            Button(intent: StopAlarmReminderIntent(alarmId: state.alarmID, sidekickId: sidekickId, reminderId: reminderId)) {
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        }
    }
}
