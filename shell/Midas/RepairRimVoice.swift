import SwiftUI

/// L1 (founder, 2026-10-23, docs/mockups/repair-feedback-2026-10-23.html section 1c): the V1 rim
/// also shows jess is listening. While the user speaks the rim's line and glow follow the
/// microphone's level, the same level the pill's orb reads; silent it is plain V1. The orb takes
/// the level raw (it ripples per syllable); the rim takes it smoothed (it swells per phrase).
enum RepairRimVoice {
    /// The look of the rim at a level 0...1.
    struct Look: Equatable {
        let lineWidth: CGFloat
        let keylineWidth: CGFloat
        let glowOpacity: Double
        let glowRadius: CGFloat
    }

    /// At full voice: 5.5 pt Volt, glow 100% (dark 95%), canvas blur 26 pt (shadow radius 13).
    static let loudLineWidth: CGFloat = 5.5
    static let loudGlowLight = 1.0
    static let loudGlowDark = 0.95
    static let loudGlowRadius: CGFloat = 13
    /// Smoothing: up in 60 ms, down in 260 ms (exponential time constants).
    static let attack: TimeInterval = 0.06
    static let release: TimeInterval = 0.26
    /// Reduce Motion: the glow crossfades in 200 ms between silent and speaking.
    static let reduceMotionFade: TimeInterval = 0.2
    /// Louder than this counts as speaking for the Reduce Motion crossfade.
    static let speakingLevel = 0.15

    static func look(level: Double, scheme: ColorScheme, reduceMotion: Bool) -> Look {
        let amount = min(1, max(0, level))
        let quietGlow = RepairRimSpec.glowOpacity(for: scheme)
        let loudGlow = scheme == .dark ? loudGlowDark : loudGlowLight
        let glow = quietGlow + (loudGlow - quietGlow) * amount
        // Reduce Motion: nothing changes size; only the glow brightens
        guard !reduceMotion else {
            return Look(lineWidth: RepairRimSpec.lineWidth, keylineWidth: RepairRimSpec.keylineWidth, glowOpacity: glow, glowRadius: RepairRimSpec.glowRadius)
        }
        let width = RepairRimSpec.lineWidth + (loudLineWidth - RepairRimSpec.lineWidth) * CGFloat(amount)
        // The ink line under the Volt keeps its 3 pt margin as the Volt grows
        let keylineMargin = RepairRimSpec.keylineWidth - RepairRimSpec.lineWidth
        let radius = RepairRimSpec.glowRadius + (loudGlowRadius - RepairRimSpec.glowRadius) * CGFloat(amount)
        return Look(lineWidth: width, keylineWidth: width + keylineMargin, glowOpacity: glow, glowRadius: radius)
    }
}

/// Smooths the level frame by frame for the rim. With Reduce Motion it is instead the 0...1 mix
/// of the silent and speaking glow, moving linearly over 200 ms.
@MainActor
final class RepairRimVoiceFollower {
    private(set) var level = 0.0
    private var lastFrame: Date?

    func step(target: Double, elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        let elapsed = max(0, elapsed)
        if reduceMotion {
            let goal = target > RepairRimVoice.speakingLevel ? 1.0 : 0.0
            let change = elapsed / RepairRimVoice.reduceMotionFade
            level = goal > level ? min(goal, level + change) : max(goal, level - change)
            return level
        }
        let timeConstant = target > level ? RepairRimVoice.attack : RepairRimVoice.release
        let share = 1 - exp(-elapsed / timeConstant)
        level += (target - level) * share
        return level
    }

    /// One display frame: the time since the last frame (at most 0.1 s, after a pause).
    func step(target: Double, at date: Date, reduceMotion: Bool) -> Double {
        let elapsed = lastFrame.map(date.timeIntervalSince) ?? 0
        lastFrame = date
        return step(target: target, elapsed: min(elapsed, 0.1), reduceMotion: reduceMotion)
    }
}
