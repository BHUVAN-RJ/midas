import SwiftUI
import UIKit

// The pieces every teaching demo is drawn from, ported from
// docs/mockups/onboarding-teach-2026-10-31.html (founder-approved 2026-10-31): the tokens, the
// easing, the touch, jess's small orb, the phone's own status bar, the home grid, the Water page
// and the pill. Every demo screen is a real Midas screen at 402 x 874 pt (iPhone 16 Pro), drawn
// from the time alone and scaled into its card, as the Add Widget demo does.

// MARK: Tokens

/// The mockup's `.theme-light` and `.theme-dark` tokens (docs/DESIGN.md 2.1, 2.2, 2.4).
struct OnboardingTeachInk {
    let colorScheme: ColorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private static func hex(_ packed: UInt32) -> Color {
        HomeScreenDemoInk.hex(packed)
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255).opacity(alpha)
    }

    var paper: Color { isDark ? Self.hex(0x111111) : Self.hex(0xFFFFFF) }
    var ink: Color { isDark ? Self.hex(0xFFFFFF) : Self.hex(0x111111) }
    var ink2: Color { isDark ? Self.hex(0xA3A3A3) : Self.hex(0x6B6B6B) }
    var ink3: Color { isDark ? Self.hex(0x5C5C5C) : Self.hex(0xBDBDBD) }
    var rule: Color { isDark ? Color.white.opacity(0.14) : Self.hex(0x111111).opacity(0.12) }
    var paper2: Color { isDark ? Self.hex(0x1C1C1C) : Self.hex(0xF3F2EF) }
    var shadow: Color { isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.14) }
    var wall: Color { isDark ? Self.hex(0x1C1C1C) : Self.hex(0xE9E6DF) }
    var frost: Color { isDark ? Self.rgb(44, 44, 46, 0.78) : Color.white.opacity(0.8) }
    var frostEdge: Color { isDark ? Color.white.opacity(0.18) : Self.hex(0x111111).opacity(0.12) }
    var sheet: Color { isDark ? Self.hex(0x1C1C1C) : Self.hex(0xFFFFFF) }
    var dim: Color { isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.32) }
    var red: Color { isDark ? Self.hex(0xFF453A) : Self.hex(0xFF3B30) }
    var fingerBody: Color { isDark ? Self.hex(0x111111).opacity(0.45) : Color.white.opacity(0.55) }
    var fingerEdge: Color { isDark ? Self.hex(0xFFFFFF) : Self.hex(0x111111) }
    var badge: Color { isDark ? Self.rgb(72, 72, 74, 0.95) : Self.rgb(214, 214, 214, 0.95) }
    var badgeMark: Color { isDark ? Self.hex(0xFFFFFF) : Self.hex(0x111111) }
    var listen: Color { isDark ? Self.hex(0xE7FF85) : Self.hex(0xCEFF00) }
    var orbBody: Color { isDark ? Self.hex(0x000000) : Self.hex(0xFFFFFF) }
    var orbRing: Color { isDark ? Self.hex(0x2A2A2A) : Self.hex(0x111111) }
    var orbCore: Color { isDark ? Self.hex(0xFFFFFF) : Self.hex(0x111111) }
    var orbGlow: Color { isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.18) }
    /// The initial's circle on the home grid (`.theme-dark .h-initial` is #262626).
    var initialFill: Color { isDark ? Self.hex(0x262626) : paper2 }
    /// The pill's fill (`.theme-dark .pillbar` is paper-2).
    var pillFill: Color { isDark ? paper2 : paper }
    /// Undo and Clear are quieter in dark mode.
    var miniPillOpacity: Double { isDark ? 0.5 : 0.6 }
    var hasInkUnderRim: Bool { !isDark }
    var volt: Color { Self.hex(0xCEFF00) }
    /// Words on Volt and the tag's orb: always ink.
    var onVolt: Color { Self.hex(0x111111) }
}

// MARK: Easing and time

/// The mockup's small helpers: smoothstep, linear, within, mix. Times are in seconds.
enum OnboardingTeachTiming {
    /// 0 before `start`, 1 after `end`, smoothstep between (the Add Widget demo's easing).
    static func eased(_ time: Double, from start: Double, to end: Double) -> Double {
        HomeScreenDemoEasing.progress(time, from: start, to: end)
    }

    static func linear(_ time: Double, from start: Double, to end: Double) -> Double {
        let raw = (time - start) / (end - start)
        return min(1, max(0, raw))
    }

    static func within(_ time: Double, from start: Double, to end: Double) -> Bool {
        time >= start && time < end
    }

    static func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        from + (to - from) * amount
    }

    /// The words heard so far, one word at a time, between `start` and `end`.
    static func heardWords(_ sentence: String, time: Double, from start: Double, to end: Double) -> String {
        let allWords = sentence.split(separator: " ")
        let shownShare = linear(time, from: start, to: end)
        // The tiny nudge keeps a share of exactly 1 from rounding down a word
        let shownCount = Int(floor(shownShare * Double(allWords.count) + 0.0001))
        let shownWords = allWords.prefix(shownCount)
        return shownWords.joined(separator: " ")
    }
}

/// The demo screen: an iPhone 16 Pro in points.
enum OnboardingTeachScreen {
    static let width: CGFloat = 402
    static let height: CGFloat = 874
    static let cornerRadius: CGFloat = 56
    /// The pill's orb and Send centres, where the finger taps.
    static let orbPoint = CGPoint(x: 12 + 7 + 22, y: 802)
    static let sendPoint = CGPoint(x: 402 - 12 - 7 - 22, y: 802)
    static let pillOrigin = CGPoint(x: 12, y: 772)
}

// MARK: The touch

/// Where the finger is: visible fades it, pressed shrinks it to 82%.
struct OnboardingTeachTouch {
    var point: CGPoint
    var visible: Double
    var isPressed: Bool

    static let hidden = OnboardingTeachTouch(point: .zero, visible: 0, isPressed: false)

    /// A tap at `tapAt`: in over 0.2 s from half a second before, pressed for the last 0.15 s,
    /// out over 0.2 s from 0.2 s after (the mockup's placeFingerTap).
    static func tap(at point: CGPoint, tapAt: Double, time: Double) -> OnboardingTeachTouch {
        let fadeIn = OnboardingTeachTiming.eased(time, from: tapAt - 0.5, to: tapAt - 0.3)
        let fadeOut = OnboardingTeachTiming.eased(time, from: tapAt + 0.2, to: tapAt + 0.4)
        let isPressed = OnboardingTeachTiming.within(time, from: tapAt - 0.15, to: tapAt)
        return OnboardingTeachTouch(point: point, visible: fadeIn * (1 - fadeOut), isPressed: isPressed)
    }
}

/// The touch as the Add Widget demo draws it: a 54 pt ring at 402 pt wide (34 pt once scaled).
struct OnboardingTeachFinger: View {
    let touch: OnboardingTeachTouch
    let ink: OnboardingTeachInk

    var body: some View {
        Circle()
            .fill(ink.fingerBody)
            .overlay(Circle().strokeBorder(ink.fingerEdge, lineWidth: 2.4))
            .shadow(color: ink.shadow, radius: 3, y: 3)
            .frame(width: 54, height: 54)
            .scaleEffect(touch.isPressed ? 0.82 : 1)
            .opacity(touch.visible)
            .position(touch.point)
    }
}

// MARK: jess's orb, small

/// The orb's colours: the pill's follow the theme; the tag's is always ink on white over Volt.
struct OnboardingTeachOrbColors {
    let body: Color
    let ring: Color
    let core: Color
    let listen: Color
    let glow: Color

    static func pill(_ ink: OnboardingTeachInk) -> OnboardingTeachOrbColors {
        OnboardingTeachOrbColors(body: ink.orbBody, ring: ink.orbRing, core: ink.orbCore, listen: ink.listen, glow: ink.orbGlow)
    }

    static func tag(_ ink: OnboardingTeachInk) -> OnboardingTeachOrbColors {
        OnboardingTeachOrbColors(body: Color.white, ring: ink.onVolt, core: ink.onVolt, listen: ink.listen, glow: Color.clear)
    }
}

/// jess's orb, small (docs/DESIGN.md 5a): idle; listening turns the core Volt and ripples the
/// outline with the voice; thinking sweeps an arc round it.
struct OnboardingTeachOrb: View {
    let size: CGFloat
    let isListening: Bool
    let isThinking: Bool
    let time: Double
    let colors: OnboardingTeachOrbColors

    /// 0 to 1 and back, about 1.4 times a second, while listening.
    private var wave: Double {
        isListening ? 0.5 + 0.5 * sin(time * 9) : 0
    }

    private var coreShare: CGFloat {
        isListening ? CGFloat(34 + wave * 6) / 100 : 0.30
    }

    var body: some View {
        ZStack {
            ripple
            Circle()
                .fill(colors.body)
                .overlay(Circle().strokeBorder(colors.ring, lineWidth: 1.5))
                .shadow(color: colors.glow, radius: 3)
            Circle()
                .fill(isListening ? colors.listen : colors.core)
                .frame(width: size * coreShare, height: size * coreShare)
            thinkingArc
        }
        .frame(width: size, height: size)
    }

    private var ripple: some View {
        Circle()
            .stroke(colors.ring, lineWidth: 1.5)
            .frame(width: size + 1.5, height: size + 1.5)
            .scaleEffect(1 + wave * 0.22)
            .opacity(isListening ? 0.5 * (1 - wave) : 0)
    }

    // The mockup's arc: r 8.6 of a 20 box, 1.8 wide, dashed 13.5 on and 60 off, a turn per 1.1 s
    private var thinkingArc: some View {
        let unit = size / 20
        let arcStyle = StrokeStyle(lineWidth: 1.8 * unit, lineCap: .round, dash: [13.5 * unit, 60 * unit])
        let turns = time / 1.1
        return Circle()
            .stroke(HomeScreenDemoInk.hex(0x111111), style: arcStyle)
            .frame(width: 17.2 * unit, height: 17.2 * unit)
            .rotationEffect(.degrees(turns * 360))
            .opacity(isThinking ? 1 : 0)
    }
}

// MARK: The phone's own bar

/// The demo screen's status bar, Dynamic Island and home bar (the mockup's addChrome).
struct OnboardingTeachStatusChrome: View {
    let ink: OnboardingTeachInk

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(OnboardingTeachCopy.statusTime)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.ink)
                .offset(x: 50, y: 17)
            HStack(spacing: 6) {
                OnboardingTeachSignalShape()
                    .fill(ink.ink)
                    .frame(width: 18, height: 12)
                battery
            }
            .offset(x: OnboardingTeachScreen.width - 34 - 50, y: 21)
            Capsule()
                .fill(Color.black)
                .frame(width: 126, height: 37)
                .offset(x: (OnboardingTeachScreen.width - 126) / 2, y: 11)
            Capsule()
                .fill(ink.ink)
                .frame(width: 134, height: 5)
                .offset(x: (OnboardingTeachScreen.width - 134) / 2, y: OnboardingTeachScreen.height - 8 - 5)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var battery: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ink.ink, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(ink.ink)
                .frame(width: 26 - 1.5 - 5, height: 12 - 3)
                .offset(x: 1.5, y: 1.5)
        }
        .frame(width: 26, height: 12)
        .opacity(0.9)
    }
}

/// The signal bars as the mockup draws them: a right triangle, high on the right.
struct OnboardingTeachSignalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Tiles and the home grid

/// The Sidekicks on the demo grids.
enum OnboardingTeachSidekick: Int, CaseIterable, Identifiable {
    case jess
    case make
    case reminders
    case water
    case plants

    var id: Int {
        rawValue
    }

    var name: String {
        switch self {
        case .jess: OnboardingTeachCopy.jessName
        case .make: OnboardingTeachCopy.makeName
        case .reminders: OnboardingTeachCopy.remindersName
        case .water: OnboardingTeachCopy.waterName
        case .plants: OnboardingTeachCopy.plantsName
        }
    }

    /// jess and Make cannot be deleted: no minus badge.
    var isBuiltIn: Bool {
        self == .jess || self == .make
    }

    var tileHex: String {
        switch self {
        case .jess, .make: ""
        case .reminders: "#C9F24D"
        case .water: "#30D5C8"
        case .plants: "#9CAF88"
        }
    }

    var symbolName: String {
        switch self {
        case .jess, .make: ""
        case .reminders: "checkmark"
        case .water: "drop"
        case .plants: "leaf"
        }
    }
}

/// A tile: jess and Make are their written word on paper (the app's own assets), the rest a
/// palette colour and a glyph in ink.
struct OnboardingTeachTile: View {
    let sidekick: OnboardingTeachSidekick
    let size: CGFloat

    var body: some View {
        switch sidekick {
        case .jess:
            JessTileIcon(size: size)
        case .make:
            MakeTileIcon(size: size)
        default:
            colouredTile
        }
    }

    private var colouredTile: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        let glyph = Image(systemName: sidekick.symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(HomeScreenDemoInk.hex(0x111111))
        return shape
            .fill(SidekickColor.color(fromHex: sidekick.tileHex))
            .frame(width: size, height: size)
            .overlay(glyph)
    }
}

/// Where each cell sits on the home grid (SidekickHomeGrid: 4 columns, 60 pt tiles).
enum OnboardingTeachHomeGrid {
    static let top: CGFloat = 104
    static let columnWidth: CGFloat = (402 - 40 - 24) / 4
    static let rowStep: CGFloat = 60 + 6 + 15 + 22
    static let cellWidth: CGFloat = 84

    static func cellOrigin(_ index: Int) -> CGPoint {
        let column = CGFloat(index % 4)
        let row = CGFloat(index / 4)
        let left = 20 + column * (columnWidth + 8) + (columnWidth - cellWidth) / 2
        return CGPoint(x: left, y: top + row * rowStep)
    }

    /// The tile's centre, where the finger presses.
    static func tileCentre(_ index: Int) -> CGPoint {
        let origin = cellOrigin(index)
        return CGPoint(x: origin.x + cellWidth / 2, y: origin.y + 30)
    }
}

/// How one cell is drawn at a moment: the jiggle, the lift, the minus badge, fading out.
struct OnboardingTeachCellLook {
    var angle: Double = 0
    var scale: Double = 1
    var opacity: Double = 1
    var badgeScale: Double = 0
    var tileOpacity: Double = 1
    var labelOpacity: Double = 1

    static let resting = OnboardingTeachCellLook()
}

/// The home grid: "Midas" at the top, the initial top right, the tiles with their names.
struct OnboardingTeachHomeScreen: View {
    let sidekicks: [OnboardingTeachSidekick]
    let looks: [OnboardingTeachCellLook]
    let ink: OnboardingTeachInk

    var body: some View {
        ZStack(alignment: .topLeading) {
            ink.paper
            Text(OnboardingTeachCopy.homeTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink.ink2)
                .frame(width: OnboardingTeachScreen.width)
                .offset(y: 62)
            Text(OnboardingTeachCopy.initial)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink.ink2)
                .frame(width: 32, height: 32)
                .background(Circle().fill(ink.initialFill))
                .offset(x: OnboardingTeachScreen.width - 20 - 32, y: 56)
            ForEach(Array(sidekicks.enumerated()), id: \.element.id) { index, sidekick in
                cell(sidekick: sidekick, index: index)
            }
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
    }

    private func cell(sidekick: OnboardingTeachSidekick, index: Int) -> some View {
        let look = index < looks.count ? looks[index] : OnboardingTeachCellLook.resting
        let origin = OnboardingTeachHomeGrid.cellOrigin(index)
        let badge = OnboardingTeachMinusBadge(ink: ink)
            .scaleEffect(look.badgeScale)
            .offset(x: -7, y: -7)
        let tile = OnboardingTeachTile(sidekick: sidekick, size: 60)
            .overlay(badge, alignment: .topLeading)
            .opacity(look.tileOpacity)
        return VStack(spacing: 6) {
            tile
            Text(sidekick.name)
                .font(.system(size: 12))
                .foregroundStyle(ink.ink)
                .lineLimit(1)
                .opacity(look.labelOpacity)
        }
        .frame(width: OnboardingTeachHomeGrid.cellWidth)
        .rotationEffect(.degrees(look.angle))
        .scaleEffect(look.scale)
        .opacity(look.opacity)
        .offset(x: origin.x, y: origin.y)
    }
}

/// The minus badge on a jiggling tile: a 22 pt grey circle with a short line.
struct OnboardingTeachMinusBadge: View {
    let ink: OnboardingTeachInk

    var body: some View {
        Circle()
            .fill(ink.badge)
            .frame(width: 22, height: 22)
            .overlay(Capsule().fill(ink.badgeMark).frame(width: 10, height: 2))
    }
}

// MARK: The Water page

/// A Sidekick page, Water: the amount, the bar, two buttons and today's drinks.
struct OnboardingTeachWaterPage: View {
    let ink: OnboardingTeachInk
    /// The soft shadow left of the page while it is pulled back.
    var edgeShadowOpacity: Double = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ink.paper
            Text(OnboardingTeachCopy.waterName)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.5)
                .offset(x: 20, y: 122)
            Text(OnboardingTeachCopy.waterHelp)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink.ink2)
                .frame(width: 30, height: 30)
                .background(Circle().fill(ink.paper2))
                .offset(x: OnboardingTeachScreen.width - 20 - 30, y: 128)
            Text(OnboardingTeachCopy.waterAmount)
                .font(.system(size: 72, weight: .bold))
                .tracking(-1.5)
                .frame(width: OnboardingTeachScreen.width)
                .offset(y: 230)
            Text(OnboardingTeachCopy.waterGoal)
                .font(.system(size: 17))
                .foregroundStyle(ink.ink2)
                .frame(width: OnboardingTeachScreen.width)
                .offset(y: 320)
            progressBar
                .offset(x: 40, y: 370)
            buttons
                .offset(x: 40, y: 430)
            log
                .offset(x: 20, y: 530)
            edgeShadow
        }
        .foregroundStyle(ink.ink)
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
    }

    private var progressBar: some View {
        let barWidth = OnboardingTeachScreen.width - 80
        let fill = RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(SidekickColor.color(fromHex: OnboardingTeachSidekick.water.tileHex))
            .frame(width: barWidth * 0.62, height: 12)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(ink.paper2)
            .frame(width: barWidth, height: 12)
            .overlay(fill, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Text(OnboardingTeachCopy.waterAddSmall)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.paper)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
                .background(Capsule().fill(ink.ink))
            Text(OnboardingTeachCopy.waterAddLarge)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.ink)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
                .background(Capsule().fill(ink.paper))
                .overlay(Capsule().strokeBorder(ink.rule, lineWidth: 1))
        }
        .frame(width: OnboardingTeachScreen.width - 80)
    }

    private var log: some View {
        VStack(spacing: 0) {
            ForEach(OnboardingTeachCopy.waterLog, id: \.time) { entry in
                logRow(entry)
            }
        }
        .frame(width: OnboardingTeachScreen.width - 40)
    }

    private func logRow(_ entry: OnboardingTeachLogEntry) -> some View {
        let rowRule = Rectangle()
            .fill(ink.rule)
            .frame(height: 1)
        return HStack {
            Text(entry.amount)
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Text(entry.time)
                .font(.system(size: 15))
                .foregroundStyle(ink.ink2)
        }
        .padding(.vertical, 12)
        .overlay(rowRule, alignment: .bottom)
    }

    private var edgeShadow: some View {
        LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
            .frame(width: 24, height: OnboardingTeachScreen.height)
            .offset(x: -24)
            .opacity(edgeShadowOpacity)
    }
}

// MARK: The pill

/// PillBar: the orb, the words (or the placeholder), Send.
struct OnboardingTeachPill: View {
    let placeholder: String
    let words: String
    let isListening: Bool
    let time: Double
    let ink: OnboardingTeachInk

    private var hasWords: Bool {
        !words.isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            OnboardingTeachOrb(size: 44, isListening: isListening, isThinking: false, time: time, colors: .pill(ink))
            Text(hasWords ? words : placeholder)
                .font(.system(size: 17))
                .foregroundStyle(hasWords ? ink.ink : ink.ink3)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(ink.paper)
                .frame(width: 44, height: 44)
                .background(Circle().fill(hasWords ? ink.ink : ink.ink3))
        }
        .padding(.horizontal, 7)
        .frame(width: OnboardingTeachScreen.width - 24, height: 60)
        .background(Capsule().fill(ink.pillFill))
        .overlay(Capsule().strokeBorder(ink.rule, lineWidth: 1))
        .shadow(color: ink.shadow, radius: 9, y: 6)
    }
}

/// The width of a word in a system font, for the tag's width as its word changes.
enum OnboardingTeachTextWidth {
    static func width(of text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        return ceil(measured.width)
    }
}
