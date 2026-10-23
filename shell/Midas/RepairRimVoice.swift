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
        /// G+1's halo: a wider, softer Volt stroke round the rim while the user speaks.
        var haloWidth: CGFloat = 0
        var haloOpacity: Double = 0
        var haloRadius: CGFloat = 0
    }

    // G+1 "Thick rim + bloom" (founder, 2026-10-23, after build 14 on the phone: L1 did not show).
    /// Silent: 4 pt Volt, canvas blur 18 pt (shadow radius 9), glow 85% light / 80% dark.
    static let silentLineWidth: CGFloat = 4
    static let silentGlowRadius: CGFloat = 9
    static let silentGlowLight = 0.85
    static let silentGlowDark = 0.8
    /// Full voice: 8 pt, blur 40 pt (radius 20), glow 100%.
    static let loudLineWidth: CGFloat = 8
    static let loudGlowRadius: CGFloat = 20
    static let loudGlow = 1.0
    /// The ink line under the Volt in light mode is 4 pt wider (8 → 12 pt).
    static let keylineMargin: CGFloat = 4
    /// The halo: 2.6 × the line, 60% at full voice, 1.2 × the glow's blur.
    static let haloWidthScale: CGFloat = 2.6
    static let loudHaloOpacity = 0.6
    static let haloRadiusScale: CGFloat = 1.2
    /// Smoothing: up in 60 ms, down in 260 ms (exponential time constants), as L1.
    static let attack: TimeInterval = 0.06
    static let release: TimeInterval = 0.26
    /// Reduce Motion: the glow crossfades in 200 ms between silent and speaking.
    static let reduceMotionFade: TimeInterval = 0.2
    /// Louder than this counts as speaking for the Reduce Motion crossfade.
    static let speakingLevel = 0.15
    /// The meter's level that counts as full voice for the rim. The meter maps −50…−10 dB RMS
    /// onto 0…1, so normal speech near the phone (about −32 to −25 dB) reads only 0.45–0.63; over
    /// 0.7 (−22 dB) it reads 0.64–0.9 and the rim shows it. The orb keeps the meter's own level.
    static let fullVoiceLevel = 0.7

    /// The microphone level as the rim uses it.
    static func drive(_ level: Double) -> Double {
        min(1, max(0, level / fullVoiceLevel))
    }

    static func look(level: Double, scheme: ColorScheme, reduceMotion: Bool) -> Look {
        let amount = min(1, max(0, level))
        let quietGlow = scheme == .dark ? silentGlowDark : silentGlowLight
        let glow = quietGlow + (loudGlow - quietGlow) * amount
        // Reduce Motion: nothing changes size and there is no halo; only the glow brightens
        guard !reduceMotion else {
            return Look(lineWidth: silentLineWidth, keylineWidth: silentLineWidth + keylineMargin, glowOpacity: glow, glowRadius: silentGlowRadius, haloWidth: silentLineWidth * haloWidthScale, haloOpacity: 0, haloRadius: silentGlowRadius * haloRadiusScale)
        }
        let share = CGFloat(amount)
        let width = silentLineWidth + (loudLineWidth - silentLineWidth) * share
        let radius = silentGlowRadius + (loudGlowRadius - silentGlowRadius) * share
        return Look(lineWidth: width, keylineWidth: width + keylineMargin, glowOpacity: glow, glowRadius: radius, haloWidth: width * haloWidthScale, haloOpacity: loudHaloOpacity * amount, haloRadius: radius * haloRadiusScale)
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
