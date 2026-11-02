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

/// Every word on the consent screen (docs/WRITING.md: title, what goes where, the buttons).
enum AIConsentCopy {
    static let title = "Allow AI?"
    static let jessName = "jess"
    static let jessSends = ["What you say, as text", "Sidekick summary"]
    static let jessDestination = "OpenRouter"
    static let editName = "Edit"
    static let editSends = ["Request", "Screenshot", "Sidekick data"]
    static let editDestination = "Anthropic"
    static let privacyPolicy = "Privacy Policy"
    static let allow = "Allow"
    static let notNow = "Not Now"
    static let settingsSwitch = "AI"

    /// The privacy page on the same server the app talks to (backend/src/public-pages.ts).
    static func privacyURL(platformOrigin: URL) -> URL {
        platformOrigin.appending(path: "privacy")
    }
}

/// One row: the feature's mark and name, what it sends, an arrow, where it goes.
private struct AIConsentRow<Mark: View>: View {
    let name: String
    let sends: [String]
    let destination: String
    let tokens: RepairTokens
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            mark()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink.color)
                AIConsentChips(sends: sends, destination: destination, tokens: tokens)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

/// The grey chips of what is sent, then "→" and the outlined destination.
private struct AIConsentChips: View {
    let sends: [String]
    let destination: String
    let tokens: RepairTokens

    var body: some View {
        AIConsentFlowLayout(spacing: 6) {
            ForEach(sends, id: \.self, content: sentChip)
            Text("→")
                .font(.system(size: 15))
                .foregroundStyle(tokens.ink2.color)
            Text(destination)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.ink.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(tokens.ink.color, lineWidth: 1.5))
        }
    }

    private func sentChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundStyle(tokens.ink.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tokens.paper2.color, in: Capsule())
    }
}

/// Lays chips left to right and wraps to the next line when the row is full.
private struct AIConsentFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = placements(width: width, subviews: subviews)
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for frame in frames {
            maxX = max(maxX, frame.maxX)
            maxY = max(maxY, frame.maxY)
        }
        return CGSize(width: min(maxX, width), height: maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = placements(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = frames[index]
            let origin = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subview.place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }

    // Each item goes after the last one on its line; one that would overflow starts a new line.
    private func placements(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}

/// "Allow AI?": full screen in onboarding, and the body of the sheet at use.
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
                .padding(.bottom, isSheet ? 18 : 28)
                .accessibilityAddTraits(.isHeader)
            hairline(tokens)
            AIConsentRow(name: AIConsentCopy.jessName, sends: AIConsentCopy.jessSends, destination: AIConsentCopy.jessDestination, tokens: tokens) {
                JessOrb(state: .idle)
            }
            hairline(tokens)
            AIConsentRow(name: AIConsentCopy.editName, sends: AIConsentCopy.editSends, destination: AIConsentCopy.editDestination, tokens: tokens) {
                AIConsentPenMark(tokens: tokens)
            }
            hairline(tokens)
            Button(AIConsentCopy.privacyPolicy, action: openPrivacyPolicy)
                .font(.system(size: 15))
                .underline()
                .foregroundStyle(tokens.ink.color)
                .padding(.top, 18)
            Spacer(minLength: 24)
            buttons(tokens)
        }
        .padding(.horizontal, 28)
        .padding(.top, isSheet ? 36 : 72)
        .padding(.bottom, isSheet ? 20 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tokens.paper.color.ignoresSafeArea())
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

    private func hairline(_ tokens: RepairTokens) -> some View {
        Rectangle()
            .fill(tokens.rule.color)
            .frame(height: 1)
    }

    private func openPrivacyPolicy() {
        openURL(AIConsentCopy.privacyURL(platformOrigin: PlatformConfig.platformOrigin))
    }
}

/// Edit's mark on the consent screen: a white pen on an ink rounded square.
private struct AIConsentPenMark: View {
    let tokens: RepairTokens

    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tokens.paper.color)
            .frame(width: 40, height: 40)
            .background(tokens.ink.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .sheet(isPresented: $center.isAskShown, onDismiss: center.askDismissed) {
                AIConsentView(isSheet: true, onAllow: center.allow, onNotNow: center.decline)
                    .presentationDetents([.height(620), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30)
            }
    }
}
