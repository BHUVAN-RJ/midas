import Foundation
import SwiftUI

// The hint after Send (founder, 2026-10-31, docs/mockups/repair-words-make-welcome-2026-10-31.html,
// "Final"): "Close anytime. Edits finish on their own." comes out of the Edit tag like a speech
// cloud (F3 "Frosted bubble", founder 2026-10-31; was F1), sits under the tag, appears right after Send while the person is
// still on the screen and fades 3 s later. Only the first 5 sends, then never again.

enum RepairSendHintCopy {
    static let text = "Close anytime. Edits finish on their own."
}

/// The cloud's timings and shape, from the mockup's Final section.
enum RepairSendHintSpec {
    /// Sends that show the hint.
    static let shownOnSends = 5
    /// The cloud grows out of the tag once the tag's new words have landed: 0.15 s after them.
    static let afterLabel = 0.15
    /// On screen for 3 s in all, the last 0.4 s fading.
    static let seconds = 3.0
    static let fade = 0.4
    static let fadeIn = 0.12
    /// Grows from 12% and 16 pt up, a critically damped spring of 0.38 s.
    static let startScale = 0.12
    static let startRise: CGFloat = -16
    static let growResponse = 0.38
    /// Under the tag: 8 pt gap to the tail's tip.
    static let gap: CGFloat = 8
    static let fontSize: CGFloat = 13
    static let lineHeight: CGFloat = 17
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 9
    static let cornerRadius: CGFloat = 18
    static let tailWidth: CGFloat = 18
    static let tailHeight: CGFloat = 10
}

/// How the cloud looks a moment after it started; nil when it is not on screen.
struct RepairSendHintLook: Equatable {
    let opacity: Double
    let scale: Double
    let rise: CGFloat

    static func at(_ seconds: Double, reduceMotion: Bool) -> RepairSendHintLook? {
        guard seconds >= 0, seconds <= RepairSendHintSpec.seconds else {
            return nil
        }
        let fadeIn = clamp01(seconds / RepairSendHintSpec.fadeIn)
        let fadeOut = clamp01((seconds - (RepairSendHintSpec.seconds - RepairSendHintSpec.fade)) / RepairSendHintSpec.fade)
        let opacity = fadeIn * (1 - fadeOut)
        if reduceMotion {
            return RepairSendHintLook(opacity: opacity, scale: 1, rise: 0)
        }
        let grow = clamp01(RepairSendMotion.spring(seconds, response: RepairSendHintSpec.growResponse, damping: 1))
        let scale = RepairSendHintSpec.startScale + (1 - RepairSendHintSpec.startScale) * grow
        let rise = RepairSendHintSpec.startRise * CGFloat(1 - grow)
        return RepairSendHintLook(opacity: opacity, scale: scale, rise: rise)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

/// Counts sends on this phone, so the hint shows on the first five only.
struct RepairSendHintCounter {
    static let defaultsKey = "midas.repair.sendHintSends"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// One more send: true while it is one of the first `shownOnSends`.
    func countSend() -> Bool {
        let sendsBefore = defaults.integer(forKey: Self.defaultsKey)
        let sendsNow = sendsBefore + 1
        defaults.set(sendsNow, forKey: Self.defaultsKey)
        return sendsNow <= RepairSendHintSpec.shownOnSends
    }
}

/// The tail on the cloud's top edge, pointing up at the tag.
struct RepairSendHintTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// F3 "Frosted bubble": the system's frosted material over a light tint (80% white; dark 78%
/// #2C2C2E), a hairline edge and a soft shadow, the tail up at the tag.
struct RepairSendHintCloud: View {
    let look: RepairSendHintLook

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        let tint = RepairSendHintFrost.tint(for: colorScheme)
        let bubble = RoundedRectangle(cornerRadius: RepairSendHintSpec.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            RepairSendHintTail()
                .fill(.ultraThinMaterial)
                .overlay(RepairSendHintTail().fill(tint))
                .frame(width: RepairSendHintSpec.tailWidth, height: RepairSendHintSpec.tailHeight)
                .padding(.bottom, -1)
            Text(RepairSendHintCopy.text)
                .font(.system(size: RepairSendHintSpec.fontSize, weight: .medium))
                .foregroundStyle(tokens.ink.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, RepairSendHintSpec.horizontalPadding)
                .padding(.vertical, RepairSendHintSpec.verticalPadding)
                .background {
                    bubble.fill(.ultraThinMaterial)
                    bubble.fill(tint)
                    bubble.strokeBorder(RepairSendHintFrost.edge(for: colorScheme), lineWidth: 1)
                }
        }
        .shadow(color: tokens.shadow.color, radius: 7, y: 4)
        .scaleEffect(look.scale, anchor: .top)
        .offset(y: look.rise)
        .opacity(look.opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RepairSendHintCopy.text)
    }
}

/// F3's frost, the mockup's --frost and --frost-edge.
enum RepairSendHintFrost {
    static func tint(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255).opacity(0.78)
        }
        return Color.white.opacity(0.8)
    }

    static func edge(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.18)
        }
        return Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.12)
    }
}
