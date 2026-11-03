import SwiftUI
import UIKit

/// The Listening screen (approved mockup, docs/mockups/jess-orb-2026-10-15.html), now jess's
/// Workdesk (founder, 2026-10-22; docs/mockups/jess-workdesk-2026-10-22.html): every task jess has
/// done as a stack at the top (JessWorkdeskStack), the orb at the bottom centre with the live
/// transcript over it, and one button: Cancel before any words, Done after. A new task comes out
/// of the orb onto the stack; tapping the orb listens again. SF Pro at iOS sizes.
struct VoiceCaptureView: View {
    let flow: VoiceReminderFlow
    /// The Workdesk's tasks; nil shows the orb alone.
    var results: JessResults? = nil
    /// A done card tapped: its Sidekick opens at the change (JessScreen).
    var onOpen: ((JessResultCard) -> Void)? = nil

    /// Listening starts when jess opens, not again when a Sidekick pushed over it goes back.
    @State private var hasStartedListening = false
    /// iOS's camera is up (jess's camera, founder 2026-11-02).
    @State private var isCameraShown = false

    static let orbSize: Double = 160
    static let stackTopPadding: Double = 16
    static let bottomPadding: Double = 22
    static let buttonHeight: Double = 44
    static let orbToButton: Double = 12

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let results {
                    JessWorkdeskStack(cards: results.log, riseFromOrb: Self.riseFromOrb(height: geometry.size.height), onRetry: results.retry, onDelete: results.removeFromLog, onOpen: openCard, photoFor: results.photo(for:))
                        .padding(.horizontal, 16)
                        .padding(.top, Self.stackTopPadding)
                }
                Spacer(minLength: 0)
                middleText
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .padding(.horizontal, 18)
                ZStack {
                    // Tap to listen, tap again to stop (founder, 2026-11-02)
                    Button(action: orbTapped) {
                        JessOrb(state: orbState, level: levelReader)
                            .frame(width: Self.orbSize, height: Self.orbSize)
                    }
                    .buttonStyle(.plain)
                    .disabled(!flow.orbTapWorks)
                    // jess's camera, right of the orb (founder, 2026-11-02)
                    if flow.hasCamera {
                        JessCameraButton(action: openCamera)
                            .disabled(!flow.cameraTapWorks)
                            .offset(x: Self.cameraOffset)
                    }
                }
                buttons
                    .frame(height: Self.buttonHeight)
                    .padding(.top, Self.orbToButton)
            }
            .padding(.bottom, Self.bottomPadding)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(uiColor: .systemBackground))
        .fullScreenCover(isPresented: $isCameraShown) {
            JessCameraPicker(onFinish: cameraFinished)
                .ignoresSafeArea()
        }
        .task {
            guard !hasStartedListening else {
                return
            }
            hasStartedListening = true
            await flow.startListening()
        }
    }

    private func openCard(_ cardId: UUID) {
        guard let log = results?.log else {
            return
        }
        for card in log where card.id == cardId {
            onOpen?(card)
            return
        }
    }

    /// From the big card's centre down to the orb's centre.
    static func riseFromOrb(height: Double) -> Double {
        let orbCenter = height - bottomPadding - buttonHeight - orbToButton - orbSize / 2
        let bigCardCenter = stackTopPadding + JessWorkdeskLayout.slots[0].height / 2
        return max(orbCenter - bigCardCenter, 0)
    }

    /// While listening or sending, the flow's state; once the task is on its card, that card's
    /// result (green, red, or grey while it waits).
    private var orbState: JessOrbState {
        if flow.phase == .ready, let newest = results?.log.first {
            return newest.workdeskOrbState
        }
        return flow.phase.orbState
    }

    /// From the orb's centre to the camera button's centre.
    static let cameraOffset: Double = orbSize / 2 + JessCameraSpec.gapFromOrb + JessCameraSpec.buttonSize / 2

    private func openCamera() {
        flow.holdForCamera()
        isCameraShown = true
    }

    /// Use Photo sends it with the words heard; Cancel sends the words alone, or listens again.
    private func cameraFinished(_ image: UIImage?) {
        isCameraShown = false
        let voiceFlow = flow
        guard let image, let jpeg = JessCameraSpec.jpeg(from: image) else {
            Task { @MainActor in
                await voiceFlow.cameraCancelled()
            }
            return
        }
        voiceFlow.sendPhoto(jpeg)
    }

    private func orbTapped() {
        let voiceFlow = flow
        Task { @MainActor in
            await voiceFlow.orbTapped()
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
        case .ready:
            // The words are on their card now
            Color.clear
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
            // Once the words are in, jess finishes in the background: the way out only closes
            Button(flow.buttonTitle, action: flow.cancel)
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
                let bodyText = VoiceReminderCopy.body(for: banner.kind, now: Date(), calendar: .current, locale: .current)
                if !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.system(size: 13))
                        .opacity(0.6)
                        .lineLimit(2)
                }
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
        guard banner.hidesByItself else {
            return
        }
        try? await Task.sleep(for: Self.addedShownFor)
        guard !Task.isCancelled else {
            return
        }
        onDismiss()
    }
}

/// One result card at the top of the home page (founder, 2026-10-22): a red core with what was said
/// and Try Again. Home shows Not Done cards only; one stays until swiped sideways (founder,
/// 2026-10-31).
struct JessResultCardView: View {
    let card: JessResultCard
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            JessOrb(state: card.orbState)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(VoiceReminderCopy.cardTitle(card))
                    .font(.system(size: 15, weight: .semibold))
                let bodyText = VoiceReminderCopy.cardBody(card, now: Date(), calendar: .current, locale: .current)
                if !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.system(size: 13))
                        .opacity(0.6)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = VoiceReminderCopy.cardActionTitle(card) {
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
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .swipeSidewaysToDelete(onDismiss)
        .padding(.horizontal, 14)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let fill = colorScheme == .dark ? Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255) : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.04)
        let stroke = colorScheme == .dark ? Color.white.opacity(0.10) : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.08)
        return shape
            .fill(fill)
            .overlay(shape.stroke(stroke, lineWidth: 1))
    }
}

/// The Not Done cards, newest first, above the home grid.
struct JessResultCardStack: View {
    let results: JessResults

    var body: some View {
        let shown = results.homeCards
        VStack(spacing: 10) {
            ForEach(shown) { card in
                JessResultCardView(card: card, onRetry: retryAction(for: card), onDismiss: dismissAction(for: card))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: shown)
    }

    private func retryAction(for card: JessResultCard) -> () -> Void {
        let cardId = card.id
        let jessResults = results
        func retryCard() {
            jessResults.retry(cardId: cardId)
        }
        return retryCard
    }

    private func dismissAction(for card: JessResultCard) -> () -> Void {
        let cardId = card.id
        let jessResults = results
        func dismissCard() {
            jessResults.dismiss(cardId: cardId)
        }
        return dismissCard
    }
}

extension View {
    /// The Listening screen over Midas while it is up, and the reminder parse's banner on top
    /// afterwards (jess's results are cards on the home page instead).
    func voiceReminders(_ flow: VoiceReminderFlow) -> some View {
        modifier(VoiceRemindersModifier(flow: flow))
    }
}

private struct VoiceRemindersModifier: ViewModifier {
    @Bindable var flow: VoiceReminderFlow

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $flow.isPresented) {
                // The Workdesk, and the Sidekicks its cards open (JessLinkNavigation.swift)
                JessScreen(flow: flow, results: ShellServices.shared.jessResults)
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
