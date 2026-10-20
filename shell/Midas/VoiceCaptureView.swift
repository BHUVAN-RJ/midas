import SwiftUI
import UIKit

/// The Listening screen (approved mockup, docs/mockups/jess-orb-2026-10-15.html): full screen,
/// jess's orb centred, the live transcript under it, Cancel only. SF Pro at iOS sizes (17 pt).
struct VoiceCaptureView: View {
    let flow: VoiceReminderFlow

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            JessOrb(state: flow.phase.orbState, level: levelReader)
                .frame(width: 160, height: 160)
            Spacer(minLength: 0)
            middleText
                .frame(maxWidth: .infinity, minHeight: 66)
                .padding(.horizontal, 18)
            buttons
        }
        .padding(.top, 56)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .task {
            await flow.startListening()
        }
    }

    /// Read on the orb's frame clock, not as SwiftUI state.
    private var levelReader: @Sendable () -> Double {
        let meter = flow.audioLevel
        return { Double(meter.level) }
    }

    @ViewBuilder
    private var middleText: some View {
        switch flow.phase {
        case .listening, .sending:
            Text(flow.transcript)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        case .unavailable(let problem):
            Text(VoiceReminderCopy.problemTitle(problem))
                .font(.headline)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            if case .unavailable(.permissionDenied) = flow.phase {
                Button(VoiceReminderCopy.openSettings, action: openSettings)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            Button(VoiceReminderCopy.cancel, action: flow.cancel)
                .font(.body)
                .foregroundStyle(.primary)
                .opacity(0.55)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
        flow.cancel()
    }
}

/// The result banner at the very top of Midas (approved mockup): the orb with a green or red core,
/// "Added" with the title and time, or "Not Added" with what was said and Try Again. Added leaves
/// by itself; Not Added stays until Try Again or a swipe up, so nothing said is lost.
struct VoiceResultBanner: View {
    let banner: VoiceBanner
    let onRetry: () -> Void
    let onDismiss: () -> Void

    static let addedShownFor: Duration = .seconds(4)

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            JessOrb(state: banner.orbState)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(VoiceReminderCopy.title(for: banner.kind))
                    .font(.system(size: 15, weight: .semibold))
                Text(VoiceReminderCopy.body(for: banner.kind, now: Date(), calendar: .current, locale: .current))
                    .font(.system(size: 13))
                    .opacity(0.6)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = VoiceReminderCopy.actionTitle(for: banner.kind) {
                Button(actionTitle, action: onRetry)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(colorScheme == .dark ? Color.white : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(bannerBackground)
        .padding(.horizontal, 14)
        .gesture(DragGesture(minimumDistance: 10).onEnded(dismissOnSwipeUp))
        .task(id: banner.id) {
            await hideAddedAfterAWhile()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bannerBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if colorScheme == .dark {
            shape
                .fill(Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255))
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 1))
        } else {
            shape
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.14), radius: 11, y: 6)
                .overlay(shape.stroke(Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.08), lineWidth: 1))
        }
    }

    private func dismissOnSwipeUp(_ value: DragGesture.Value) {
        if value.translation.height < -20 {
            onDismiss()
        }
    }

    private func hideAddedAfterAWhile() async {
        guard case .added = banner.kind else {
            return
        }
        try? await Task.sleep(for: Self.addedShownFor)
        guard !Task.isCancelled else {
            return
        }
        onDismiss()
    }
}

extension View {
    /// The Listening screen over Midas while it is up, and the result banner on top afterwards.
    func voiceReminders(_ flow: VoiceReminderFlow) -> some View {
        modifier(VoiceRemindersModifier(flow: flow))
    }
}

private struct VoiceRemindersModifier: ViewModifier {
    @Bindable var flow: VoiceReminderFlow

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $flow.isPresented) {
                VoiceCaptureView(flow: flow)
            }
            .overlay(alignment: .top) {
                if let banner = flow.banner {
                    VoiceResultBanner(banner: banner, onRetry: flow.retry, onDismiss: flow.dismissBanner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: flow.banner)
    }
}
