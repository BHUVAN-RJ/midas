import SwiftUI
import UIKit

// The repair flow's look (founder, 2026-10-23, docs/mockups/repair-feedback-2026-10-23.html
// section 1): black, white and Volt only. Tomato left Midas's colours that day. Every number here
// is the mockup's: V1 rim, the Repair tag, the B3 floating pill with the orb in its left slot.

/// Midas's shell tokens (docs/DESIGN.md 2.1 light, 2.4 dark) for the repair layer and the tag.
struct RepairTokens: Equatable, Sendable {
    let paper: JessOrbColor
    let ink: JessOrbColor
    let ink2: JessOrbColor
    let ink3: JessOrbColor
    let rule: JessOrbColor
    let paper2: JessOrbColor
    let shadow: JessOrbColor

    static let light = RepairTokens(
        paper: JessOrbColor(hex: 0xFFFFFF),
        ink: JessOrbColor(hex: 0x111111),
        ink2: JessOrbColor(hex: 0x6B6B6B),
        ink3: JessOrbColor(hex: 0xBDBDBD),
        rule: JessOrbColor(hex: 0x111111, alpha: 0.12),
        paper2: JessOrbColor(hex: 0xF3F2EF),
        shadow: JessOrbColor(hex: 0x000000, alpha: 0.14)
    )

    static let dark = RepairTokens(
        paper: JessOrbColor(hex: 0x111111),
        ink: JessOrbColor(hex: 0xFFFFFF),
        ink2: JessOrbColor(hex: 0xA3A3A3),
        ink3: JessOrbColor(hex: 0x5C5C5C),
        rule: JessOrbColor(hex: 0xFFFFFF, alpha: 0.14),
        paper2: JessOrbColor(hex: 0x1C1C1C),
        shadow: JessOrbColor(hex: 0x000000, alpha: 0.5)
    )

    static func forScheme(_ scheme: ColorScheme) -> RepairTokens {
        scheme == .dark ? .dark : .light
    }
}

enum RepairVolt {
    static let hex = "#CEFF00"
    static let color = JessOrbColor(hex: 0xCEFF00)
    /// The ink the tag's words are written in, and the line under Volt on white.
    static let ink = JessOrbColor(hex: 0x111111)
}

/// V1, Volt rim on an ink line: 3 pt Volt, 4 pt in, 12 pt Volt glow (70% light, 60% dark); on
/// white over a 6 pt ink line (Volt alone is 1.2:1 on white). Stays on from the swipe until Send or
/// Cancel; never ripples with the voice.
enum RepairRimSpec {
    /// The silent rim, G+1 (founder, 2026-10-23, docs/briefs/repair-ux-upgrade.md "Decided";
    /// replaces V1/L1's 3 pt over 6 pt): 4 pt Volt over an 8 pt ink line in light mode.
    /// `RepairRimVoice` grows it with the voice.
    static let lineWidth: CGFloat = 4
    static let inset: CGFloat = 4
    static let keylineWidth: CGFloat = 8
    /// A canvas blur of 18 pt is about a SwiftUI shadow radius of 9.
    static let glowRadius: CGFloat = 9
    static let glowOpacityLight = 0.85
    static let glowOpacityDark = 0.8
    /// While the pen is down the rim steps back.
    static let drawingOpacity = 0.45
    static let drawingIn = 0.15
    static let drawingOut = 0.30
    /// The fingers must have gone this share of the way before the rim shows, so a stray
    /// three-finger touch never flashes it.
    static let showFromProgress = 0.12
    /// Of the trace, the share the swipe draws; the lock closes the rest round the bottom.
    static let tracedShare = 0.85
    static let lockClose = 0.20
    static let liftEarly = 0.20
    static let drain = 0.36
    static let cancelFade = 0.20
    /// iPhone 16 Pro's screen corner, so the rim follows the glass.
    static let screenCornerRadius: CGFloat = 55

    static func glowOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? glowOpacityDark : glowOpacityLight
    }

    /// The ink line under the Volt: light mode only.
    static func hasKeyline(for scheme: ColorScheme) -> Bool {
        scheme != .dark
    }
}

/// The Repair tag under the island: 28 pt, radius 14, Volt, 13 pt semibold ink words, a 1 pt ink
/// edge on white, a 20 pt mini orb once a repair is on its way.
enum RepairTagSpec {
    static let height: CGFloat = 28
    static let cornerRadius: CGFloat = 14
    static let fontSize: CGFloat = 13
    static let orbSize: CGFloat = 20
    static let outlineWidth: CGFloat = 1
    /// From the safe area's top: 53 pt on iPhone 16 Pro, 5 pt under the island.
    static let topFromSafeArea: CGFloat = -9
    static let drop = 0.26
    static let rise = 0.20
    static let spinSeconds = 1.1
    /// A result shown on return, and Already There, leave after this long (fade 400 ms).
    static let leaveAfterSeconds = 2.4
    static let leaveFade = 0.40
    /// "Fixed" on return after a fix that landed while the user was away (founder, 2026-10-23).
    static let fixedAwayShowsSeconds = 1.0
    /// "Taking longer" after this long (founder default, 2026-10-23).
    static let takingLongerAfterSeconds: TimeInterval = 10 * 60
}

/// B3, the floating pill, and O4, the orb dropping into its left slot.
enum RepairPillSpec {
    static let height: CGFloat = 60
    static let cornerRadius: CGFloat = 30
    static let sideMargin: CGFloat = 12
    static let innerPadding: CGFloat = 7
    static let spacing: CGFloat = 10
    static let slotSize: CGFloat = 44
    static let sendSize: CGFloat = 44
    static let miniPillHeight: CGFloat = 36
    static let fontSize: CGFloat = 17
    static let focusRingWidth: CGFloat = 1.5
    /// The orb pops at the lift point: 0 → 106% in 240 ms, → 100% in 160 ms, 64 pt.
    static let popSize: CGFloat = 64
    static let popGrow = 0.24
    static let popSettle = 0.16
    /// Then drops into the slot as the pill lands: 420 ms ease-in-out.
    static let dock = 0.42
    /// The pill rises from below 160 → 480 ms, ease-out.
    static let riseDelay = 0.16
    static let rise = 0.32
    /// On Send the pill drops after 200 ms, 320 ms ease-in.
    static let dropDelay = 0.20
    static let drop = 0.32
}

extension JessOrbColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Undo and Clear (B+2, founder 2026-10-23): frosted pills like iOS controls (`.regularMaterial`),
/// a hairline edge, ink words in light and white in dark. On only once something is drawn; off,
/// the words dim but stay readable: 60% in light (about 4.9:1 on white), 50% in dark (about 5:1
/// on the dark frost). Build 14's off grey #5C5C5C on #111111 was 2.8:1.
enum RepairMiniPillStyle {
    static let usesMaterial = true
    static let offOpacityLight = 0.6
    static let offOpacityDark = 0.5

    static func isOn(strokeCount: Int) -> Bool {
        strokeCount > 0
    }

    static func wordOpacity(isOn: Bool, scheme: ColorScheme) -> Double {
        guard !isOn else {
            return 1
        }
        return scheme == .dark ? offOpacityDark : offOpacityLight
    }

    static func edge(for scheme: ColorScheme) -> JessOrbColor {
        scheme == .dark ? JessOrbColor(hex: 0xFFFFFF, alpha: 0.18) : JessOrbColor(hex: 0x111111, alpha: 0.12)
    }
}
