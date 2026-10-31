import CoreGraphics
import Foundation
import UIKit

// Send, T1c "Quick and quiet" (founder, 2026-10-23, docs/mockups/repair-feedback-2026-10-23.html
// section 1b on main): the Repair tag stays in place, solid, never replaced. The screenshot shrinks
// (phone corners while big, rounding to a small capsule about 18 × 39 pt) and travels straight up,
// aiming 27 pt above the tag's centre; once narrower than the tag it is clipped at the tag's lower
// edge, so it slips in under it and is never drawn over it. On contact the tag swells; once the
// shot is fully inside, the tag cross-fades "Edit" → "On it" + spinning orb and widens (words
// founder, 2026-10-31).
// Reduce Motion: the shot fades in place in 200 ms, the label cross-fades, no swell.
// The mockup's own functions, in points and seconds, pure so tests can step them.

enum RepairSendMotion {
    /// Travel: spring response 0.6 s, damping 1.0 (critically damped, no overshoot).
    static let travelResponse = 0.6
    static let travelDamping = 1.0
    /// The shrink runs ahead of the travel: its response is 0.6 × the travel's.
    static let shrinkLead = 0.6
    static let endScale = 0.045
    static let phoneCornerRadius: CGFloat = 56
    /// The path aims this far above the tag's centre, so the capsule keeps moving as it slips in.
    static let aimAboveTagCentre: CGFloat = 27
    /// On contact: 1 → 1.08 wide, 1 → 1.05 tall, spring response 0.3 s, damping 0.65.
    static let swellX = 0.08
    static let swellY = 0.05
    static let swellResponse = 0.3
    static let swellDamping = 0.65
    static let labelCrossFade = 0.14
    /// The tag's width for "Edit" alone, and for "On it" with its orb, as the plain tag lays them
    /// out (the mockup's tagWidthFor: 12 + words + 12; 4 + orb + gap + words + 12).
    static let tagStartWidth: CGFloat = tagWidth(for: RepairTagCopy.repairMode, withOrb: false)
    static let tagEndWidth: CGFloat = tagWidth(for: RepairTagCopy.onIt, withOrb: true)

    static func tagWidth(for words: String, withOrb: Bool) -> CGFloat {
        let font = UIFont.systemFont(ofSize: RepairTagSpec.fontSize, weight: .semibold)
        let measured = (words as NSString).size(withAttributes: [.font: font])
        let wordsWidth = measured.width.rounded(.up)
        if withOrb {
            return 4 + RepairTagSpec.orbSize + 7 + wordsWidth + 12
        }
        return 12 + wordsWidth + 12
    }
    static let duration = 0.9
    static let reduceMotionFade = 0.2

    /// Where the screenshot is: its centre, its scale of the page, its corner radius in page
    /// points (before the scale), and its top and bottom on screen.
    struct Box: Equatable {
        let center: CGPoint
        let scale: CGFloat
        let cornerRadius: CGFloat
        let top: CGFloat
        let bottom: CGFloat
    }

    /// The page's frame and the tag's frame, in window points.
    struct Stage: Equatable {
        let page: CGRect
        let tag: CGRect
    }

    // MARK: Springs (the mockup's spring, springSafe and kick)

    static func spring(_ seconds: Double, response: Double, damping: Double) -> Double {
        guard seconds > 0 else {
            return 0
        }
        let safeDamping = min(damping, 0.999)
        let omega = 2 * Double.pi / response
        let decay = exp(-safeDamping * omega * seconds)
        let omegaDamped = omega * sqrt(1 - safeDamping * safeDamping)
        return 1 - decay * (cos(omegaDamped * seconds) + (safeDamping * omega / omegaDamped) * sin(omegaDamped * seconds))
    }

    /// A spring kicked once: rises, falls back through 0, peak normalised to 1.
    static func kick(_ seconds: Double, response: Double, damping: Double) -> Double {
        guard seconds > 0 else {
            return 0
        }
        let safeDamping = min(damping, 0.999)
        let omega = 2 * Double.pi / response
        let omegaDamped = omega * sqrt(1 - safeDamping * safeDamping)
        let value = exp(-safeDamping * omega * seconds) * sin(omegaDamped * seconds)
        let peakTime = atan(omegaDamped / (safeDamping * omega)) / omegaDamped
        let peak = exp(-safeDamping * omega * peakTime) * sin(omegaDamped * peakTime)
        return value / peak
    }

    static func easeInOut(_ progress: Double) -> Double {
        let clamped = min(1, max(0, progress))
        if clamped < 0.5 {
            return 4 * clamped * clamped * clamped
        }
        let flipped = -2 * clamped + 2
        return 1 - flipped * flipped * flipped / 2
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ amount: Double) -> CGFloat {
        from + (to - from) * CGFloat(amount)
    }

    // MARK: The screenshot

    static func box(at seconds: Double, stage: Stage) -> Box {
        let travel = clamp01(spring(seconds, response: travelResponse, damping: travelDamping))
        let shrink = clamp01(spring(seconds, response: travelResponse * shrinkLead, damping: travelDamping))
        let scale = lerp(1, endScale, shrink)
        let start = CGPoint(x: stage.page.midX, y: stage.page.midY)
        let aim = CGPoint(x: stage.tag.midX, y: stage.tag.midY - aimAboveTagCentre)
        // Straight up (T1c has no bow): a quadratic with its control on the line is a line
        let center = CGPoint(x: lerp(start.x, aim.x, travel), y: lerp(start.y, aim.y, travel))
        let height = stage.page.height * scale
        // Phone corners while big, a capsule once small
        let radius = lerp(phoneCornerRadius, stage.page.width / 2, pow(shrink, 3))
        return Box(center: center, scale: scale, cornerRadius: min(radius, stage.page.width / 2), top: center.y - height / 2, bottom: center.y + height / 2)
    }

    /// Narrow enough to slip into the tag.
    static func fitsInTag(_ box: Box, stage: Stage) -> Bool {
        stage.page.width * box.scale <= stage.tag.width
    }

    /// Where the screenshot is cut off: the tag's lower edge, once it fits; nil before.
    static func clipTop(_ box: Box, stage: Stage) -> CGFloat? {
        fitsInTag(box, stage: stage) ? stage.tag.maxY : nil
    }

    /// When the shot first touches the tag's lower edge.
    static func contactSeconds(stage: Stage) -> Double {
        firstTime(stage: stage, where: isTouching)
    }

    /// When its lower end has passed the tag's lower edge: fully inside.
    static func goneSeconds(stage: Stage) -> Double {
        firstTime(stage: stage, where: isInside)
    }

    private static func isTouching(_ box: Box, _ stage: Stage) -> Bool {
        box.top <= stage.tag.maxY && fitsInTag(box, stage: stage)
    }

    private static func isInside(_ box: Box, _ stage: Stage) -> Bool {
        box.bottom <= stage.tag.maxY && fitsInTag(box, stage: stage)
    }

    private static func firstTime(stage: Stage, where condition: (Box, Stage) -> Bool) -> Double {
        var seconds = 0.0
        while seconds <= duration * 2 {
            if condition(box(at: seconds, stage: stage), stage) {
                return seconds
            }
            seconds += 0.004
        }
        return travelResponse
    }

    // MARK: The tag

    struct TagLook: Equatable {
        /// 0: "Edit"; 1: the new words.
        let labelMix: Double
        let width: CGFloat
        let swellX: CGFloat
        let swellY: CGFloat
    }

    static func tagLook(at seconds: Double, contact: Double, gone: Double, reduceMotion: Bool) -> TagLook {
        if reduceMotion {
            let mix = easeInOut(seconds / reduceMotionFade)
            return TagLook(labelMix: mix, width: lerp(tagStartWidth, tagEndWidth, mix), swellX: 1, swellY: 1)
        }
        let swell = kick(seconds - contact, response: swellResponse, damping: swellDamping)
        let labelMix = easeInOut((seconds - gone) / labelCrossFade)
        let widthMix = spring(seconds - gone, response: swellResponse, damping: max(0.7, swellDamping))
        return TagLook(labelMix: labelMix, width: lerp(tagStartWidth, tagEndWidth, widthMix), swellX: 1 + CGFloat(swellX * swell), swellY: 1 + CGFloat(swellY * swell))
    }

    /// Reduce Motion: the shot's opacity as it fades in place.
    static func reducedShotOpacity(at seconds: Double) -> Double {
        1 - easeInOut(seconds / reduceMotionFade)
    }
}
