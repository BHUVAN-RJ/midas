import Foundation
import Observation
import SwiftUI

// AI consent (Apple guideline 5.1.2(i); founder, 2026-11-02; docs/mockups/ai-consent-2026-11-02.html):
// before anything goes to a third-party AI the person is told where it goes and taps Allow.
// jess sends what was said (as text) and a summary of the Sidekicks through OpenRouter; Edit sends
// the request, a screenshot and the Sidekick's data to Anthropic.
// A1: asked once in onboarding, after the four teaching cards, before Home; someone signed in
// before this build sees it once on first open. D1: after Not Now, the same screen comes up at
// each jess or Edit use until Allow. The AI switch in Settings turns it off or on again.

/// The person's answer on this install.
enum AIConsentAnswer: String, Equatable, Sendable {
    case notAsked
    case allowed
    case declined
}

/// The answer, kept in UserDefaults so it survives launches.
struct AIConsentMemory: Sendable {
    static let answerKey = "midas.aiConsent.answer"
    /// UserDefaults is thread-safe; `nonisolated(unsafe)` lets the network backstop read it.
    nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var answer: AIConsentAnswer {
        let stored = defaults.string(forKey: Self.answerKey) ?? ""
        return AIConsentAnswer(rawValue: stored) ?? .notAsked
    }

    func save(_ answer: AIConsentAnswer) {
        if answer == .notAsked {
            defaults.removeObject(forKey: Self.answerKey)
            return
        }
        defaults.set(answer.rawValue, forKey: Self.answerKey)
    }

    var isAllowed: Bool {
        answer == .allowed
    }
}

enum AIConsentRules {
    /// The full-screen ask replaces Home until it is answered once (A1). Home is where a new user
    /// lands after the teaching cards and where anyone signed in before this build lands.
    static func showsOnboardingScreen(stage: OnboardingStage, answer: AIConsentAnswer) -> Bool {
        stage == .home && answer == .notAsked
    }

    /// The session token for a request that sends data to AI: none until the person allowed it,
    /// so jess and Edit requests cannot leave the phone even if a screen forgot to ask.
    static func tokenForAIRequest(memory: AIConsentMemory, sessionToken: () -> String?) -> String? {
        guard memory.isAllowed else {
            return nil
        }
        return sessionToken()
    }
}

/// The shell's consent state and the sheet asking at use.
@MainActor
@Observable
final class AIConsentCenter {
    private(set) var answer: AIConsentAnswer
    /// The sheet is up, asked by jess or Edit.
    var isAskShown = false
    @ObservationIgnored private let memory: AIConsentMemory
    /// What jess or Edit was about to do; runs once the sheet has gone after Allow.
    @ObservationIgnored private var pendingAction: (@MainActor () -> Void)?

    init(memory: AIConsentMemory = AIConsentMemory()) {
        self.memory = memory
        self.answer = memory.answer
    }

    var isAllowed: Bool {
        answer == .allowed
    }

    /// jess and Edit call this before sending: runs the action at once when allowed, otherwise
    /// shows the sheet and keeps the action for Allow.
    func run(_ action: @escaping @MainActor () -> Void) {
        if isAllowed {
            action()
            return
        }
        pendingAction = action
        isAskShown = true
    }

    /// Allow, on the onboarding screen or the sheet.
    func allow() {
        record(.allowed)
        isAskShown = false
    }

    /// Not Now: nothing is sent; the kept action is dropped.
    func decline() {
        record(.declined)
        pendingAction = nil
        isAskShown = false
    }

    /// The sheet has gone (Allow, Not Now or a swipe down). After Allow the kept action runs now,
    /// so a screen it opens is not shown while the sheet is still leaving.
    func askDismissed() {
        isAskShown = false
        let action = pendingAction
        pendingAction = nil
        guard isAllowed, let action else {
            return
        }
        action()
    }

    /// The AI switch in Settings. Off counts as Not Now; on is Allow (the switch says what it does).
    func setAllowed(_ isOn: Bool) {
        record(isOn ? .allowed : .declined)
    }

    /// Signing out: the next person to sign in on this phone is asked again.
    func forget() {
        record(.notAsked)
        pendingAction = nil
        isAskShown = false
    }

    private func record(_ newAnswer: AIConsentAnswer) {
        memory.save(newAnswer)
        answer = newAnswer
    }
}

/// Every word on the consent screen (docs/WRITING.md). Founder, 2026-11-02 (build 22 feedback):
/// no feature or provider names on the screen; who gets what is on the Privacy Policy page.
enum AIConsentCopy {
    static let title = "Third-Party Services"
    static let line = "Midas uses third-party services."
    static let privacyPolicy = "Privacy Policy"
    static let allow = "Allow"
    static let notNow = "Not Now"
    static let settingsSwitch = "Third-Party Services"

    /// The privacy page on the same server the app talks to (backend/src/public-pages.ts).
    static func privacyURL(platformOrigin: URL) -> URL {
        platformOrigin.appending(path: "privacy")
    }
}

/// "Third-Party Services": full screen in onboarding, and the body of the sheet at use.
struct AIConsentView: View {
    /// The full-screen version has more room at the top.
    var isSheet = false
    let onAllow: () -> Void
    let onNotNow: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Text(AIConsentCopy.title)
                .font(.system(size: isSheet ? 28 : 34, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(tokens.ink.color)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            Text(AIConsentCopy.line)
                .font(.system(size: 17))
                .foregroundStyle(tokens.ink2.color)
                .fixedSize(horizontal: false, vertical: true)
            Button(AIConsentCopy.privacyPolicy, action: openPrivacyPolicy)
                .font(.system(size: 15))
                .underline()
                .foregroundStyle(tokens.ink.color)
                .padding(.top, 14)
            Spacer(minLength: 24)
            buttons(tokens)
        }
        .padding(.horizontal, 28)
        .padding(.top, isSheet ? 22 : 72)
        .padding(.bottom, isSheet ? 8 : 24)
        .frame(maxWidth: .infinity, maxHeight: isSheet ? nil : .infinity, alignment: .topLeading)
        // The sheet draws its own background (BottomEdgeSheet); full screen fills the page
        .background(isSheet ? Color.clear : tokens.paper.color, ignoresSafeAreaEdges: .all)
    }

    private func buttons(_ tokens: RepairTokens) -> some View {
        VStack(spacing: 10) {
            Button(action: onAllow) {
                Text(AIConsentCopy.allow)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.paper.color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(tokens.ink.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: onNotNow) {
                Text(AIConsentCopy.notNow)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink.color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func openPrivacyPolicy() {
        openURL(AIConsentCopy.privacyURL(platformOrigin: PlatformConfig.platformOrigin))
    }
}

extension View {
    /// The consent sheet jess and Edit ask with (D1).
    func aiConsentAsk(_ center: AIConsentCenter) -> some View {
        modifier(AIConsentAskModifier(center: center))
    }
}

private struct AIConsentAskModifier: ViewModifier {
    @Bindable var center: AIConsentCenter

    func body(content: Content) -> some View {
        content
            // On the bottom edge, not a floating card (founder, 2026-11-02, BottomEdgeSheet)
            .bottomEdgeSheet(isPresented: $center.isAskShown, onDismiss: center.askDismissed) {
                AIConsentView(isSheet: true, onAllow: center.allow, onNotNow: center.decline)
            }
    }
}
