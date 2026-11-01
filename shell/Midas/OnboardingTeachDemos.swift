import SwiftUI

// The four looping demos of docs/mockups/onboarding-teach-2026-10-31.html, each drawn from its
// time alone (seconds into its loop) at 402 x 874 pt, exactly as the mockup's render functions.

// MARK: Card 1: Edit Any Sidekick

/// When each part of the Edit demo happens, in seconds (the mockup's EDIT).
enum OnboardingTeachEditTimes {
    static let down = 0.7
    static let open = 1.45
    static let listen = 2.4
    static let heard = 3.9
    static let send = 4.7
    static let onIt = 4.8
    static let editing = 5.9
    static let leave = 6.9
    static let length = 7.6
    /// With Reduce Motion: the Edit layer open, the change said, the finger on Send.
    static let still = 4.5
}

/// Three fingers pull down on Water, the Edit layer opens, the change is said, Send.
struct OnboardingTeachEditDemo: View {
    let time: Double
    let ink: OnboardingTeachInk

    private typealias Times = OnboardingTeachEditTimes

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingTeachWaterPage(ink: ink)
            OnboardingTeachRim(ink: ink)
                .opacity(rimShown)
            closeButton
                .opacity(controlsShown)
                .offset(x: 16, y: 70)
            miniPills
                .opacity(controlsShown)
                .frame(width: OnboardingTeachScreen.width - 12, alignment: .trailing)
                .offset(y: 728)
            pill
            tag
            OnboardingTeachStatusChrome(ink: ink)
            threeFingers
            OnboardingTeachFinger(touch: oneFingerTouch, ink: ink)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
    }

    // The rim traces in with the pull and drains after Send
    private var rimShown: Double {
        let traced = OnboardingTeachTiming.eased(time, from: Times.down + 0.1, to: Times.open)
        let drained = OnboardingTeachTiming.eased(time, from: Times.send, to: Times.send + 0.3)
        return traced * (1 - drained)
    }

    private var controlsIn: Double {
        OnboardingTeachTiming.eased(time, from: Times.open, to: Times.open + 0.4)
    }

    // Close, Undo and Clear come in after the pull and leave at Send
    private var controlsShown: Double {
        let leaving = OnboardingTeachTiming.eased(time, from: Times.send, to: Times.send + 0.2)
        return controlsIn * (1 - leaving)
    }

    private var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ink.ink)
            .frame(width: 40, height: 40)
            .background(Circle().fill(ink.paper))
            .overlay(Circle().strokeBorder(ink.rule, lineWidth: 1))
            .shadow(color: ink.shadow, radius: 2.5, y: 2)
    }

    private var miniPills: some View {
        HStack(spacing: 8) {
            OnboardingTeachMiniPill(text: OnboardingTeachCopy.undo, ink: ink)
            OnboardingTeachMiniPill(text: OnboardingTeachCopy.clear, ink: ink)
        }
    }

    // The pill rises with the controls and sinks away after Send
    private var pill: some View {
        let sinking = OnboardingTeachTiming.eased(time, from: Times.send + 0.2, to: Times.send + 0.52)
        let fading = OnboardingTeachTiming.eased(time, from: Times.send + 0.3, to: Times.send + 0.52)
        let lift = (1 - controlsIn) * 110 + sinking * 110
        let isListening = OnboardingTeachTiming.within(time, from: Times.listen, to: Times.heard + 0.3)
        let words = OnboardingTeachTiming.heardWords(OnboardingTeachCopy.editAsk, time: time, from: Times.listen + 0.2, to: Times.heard)
        return OnboardingTeachPill(placeholder: OnboardingTeachCopy.editPlaceholder, words: words, isListening: isListening, time: time, ink: ink)
            .opacity(controlsIn * (1 - fading))
            .offset(x: OnboardingTeachScreen.pillOrigin.x, y: OnboardingTeachScreen.pillOrigin.y + lift)
    }

    /// The tag's word: Edit, then "On it" at Send, then "Editing"; each change crossfades.
    private var tagWord: (from: String, to: String, amount: Double) {
        if time < Times.onIt {
            return (OnboardingTeachCopy.tagEdit, OnboardingTeachCopy.tagEdit, 1)
        }
        if time < Times.editing {
            return (OnboardingTeachCopy.tagEdit, OnboardingTeachCopy.tagOnIt, OnboardingTeachTiming.eased(time, from: Times.onIt, to: Times.onIt + 0.2))
        }
        return (OnboardingTeachCopy.tagOnIt, OnboardingTeachCopy.tagEditing, OnboardingTeachTiming.eased(time, from: Times.editing, to: Times.editing + 0.2))
    }

    // Tag width: 4 + 20 + 6 on the left with the orb, 12 on the right of the word
    private static func tagWidth(for word: String) -> CGFloat {
        30 + OnboardingTeachTextWidth.width(of: word, size: 13, weight: .semibold) + 12
    }

    private var tag: some View {
        let word = tagWord
        let fromWidth = Self.tagWidth(for: word.from)
        let toWidth = Self.tagWidth(for: word.to)
        let width = CGFloat(OnboardingTeachTiming.mix(Double(fromWidth), Double(toWidth), word.amount))
        let dropIn = OnboardingTeachTiming.eased(time, from: Times.open, to: Times.open + 0.26)
        let leaving = OnboardingTeachTiming.eased(time, from: Times.leave, to: Times.leave + 0.4)
        let isThinking = time > Times.send + 0.1
        return OnboardingTeachEditTag(word: word, width: width, isThinking: isThinking, time: time, ink: ink)
            .opacity(dropIn * (1 - leaving))
            .offset(x: OnboardingTeachScreen.width / 2 - width / 2, y: 53 + (1 - dropIn) * -36)
    }

    // Three fingers press near the top and pull down
    private var threeFingers: some View {
        let fadeIn = OnboardingTeachTiming.eased(time, from: 0.3, to: 0.5)
        let fadeOut = OnboardingTeachTiming.eased(time, from: Times.open, to: Times.open + 0.2)
        let pull = OnboardingTeachTiming.eased(time, from: Times.down, to: Times.open)
        let isPressed = OnboardingTeachTiming.within(time, from: 0.55, to: Times.open)
        return ForEach(0..<3, id: \.self) { fingerIndex in
            // The middle finger sits a little higher, as a real hand does
            let raise: CGFloat = fingerIndex == 1 ? -12 : 0
            let point = CGPoint(x: 136 + CGFloat(fingerIndex) * 65, y: 260 + CGFloat(pull) * 200 + raise)
            let touch = OnboardingTeachTouch(point: point, visible: fadeIn * (1 - fadeOut), isPressed: isPressed)
            OnboardingTeachFinger(touch: touch, ink: ink)
        }
    }

    // One finger: the orb, then Send
    private var oneFingerTouch: OnboardingTeachTouch {
        if time < Times.listen + 0.4 {
            let fadeIn = OnboardingTeachTiming.eased(time, from: Times.listen - 0.5, to: Times.listen - 0.3)
            let fadeOut = OnboardingTeachTiming.eased(time, from: Times.listen + 0.2, to: Times.listen + 0.4)
            let isPressed = OnboardingTeachTiming.within(time, from: Times.listen - 0.15, to: Times.listen)
            return OnboardingTeachTouch(point: OnboardingTeachScreen.orbPoint, visible: fadeIn * (1 - fadeOut), isPressed: isPressed)
        }
        let fadeIn = OnboardingTeachTiming.eased(time, from: Times.heard + 0.2, to: Times.heard + 0.4)
        let fadeOut = OnboardingTeachTiming.eased(time, from: Times.send + 0.1, to: Times.send + 0.3)
        let isPressed = OnboardingTeachTiming.within(time, from: Times.send - 0.15, to: Times.send)
        return OnboardingTeachTouch(point: OnboardingTeachScreen.sendPoint, visible: fadeIn * (1 - fadeOut), isPressed: isPressed)
    }
}

/// The Edit layer's rim (RepairTheme V1, G+1): 4 pt Volt over an 8 pt ink line in light mode, a
/// Volt glow inside it; Volt and glow only in dark mode.
struct OnboardingTeachRim: View {
    let ink: OnboardingTeachInk

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingTeachScreen.cornerRadius, style: .continuous)
        let glowOpacity = ink.hasInkUnderRim ? 0.85 : 0.8
        let glowWidth: CGFloat = ink.hasInkUnderRim ? 18 : 14
        let inkLine = shape.strokeBorder(ink.onVolt, lineWidth: 8)
            .opacity(ink.hasInkUnderRim ? 1 : 0)
        return ZStack {
            // The inner glow: a wide Volt band blurred, kept inside the screen
            shape.strokeBorder(ink.volt.opacity(glowOpacity), lineWidth: glowWidth)
                .blur(radius: 9)
            inkLine
            shape.strokeBorder(ink.volt, lineWidth: 4)
        }
        .clipShape(shape)
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height)
        .allowsHitTesting(false)
    }
}

/// The tag at the top of the Edit layer: the orb and its word on Volt.
struct OnboardingTeachEditTag: View {
    let word: (from: String, to: String, amount: Double)
    let width: CGFloat
    let isThinking: Bool
    let time: Double
    let ink: OnboardingTeachInk

    private static let words = [OnboardingTeachCopy.tagEdit, OnboardingTeachCopy.tagOnIt, OnboardingTeachCopy.tagEditing]

    var body: some View {
        let outline = Capsule().strokeBorder(ink.onVolt, lineWidth: 1)
            .opacity(ink.hasInkUnderRim ? 1 : 0)
        return ZStack(alignment: .topLeading) {
            Capsule().fill(ink.volt)
            outline
            ForEach(Self.words, id: \.self) { tagWord in
                Text(tagWord)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.onVolt)
                    .fixedSize()
                    .frame(height: 28)
                    .offset(x: 30)
                    .opacity(shownShare(of: tagWord))
            }
            OnboardingTeachOrb(size: 20, isListening: false, isThinking: isThinking, time: time, colors: .tag(ink))
                .offset(x: 4, y: 4)
        }
        .frame(width: width, height: 28, alignment: .topLeading)
        .clipShape(Capsule())
    }

    private func shownShare(of tagWord: String) -> Double {
        if tagWord == word.to {
            return word.amount
        }
        if tagWord == word.from {
            return 1 - word.amount
        }
        return 0
    }
}

/// Undo or Clear: a quiet frosted pill.
struct OnboardingTeachMiniPill: View {
    let text: String
    let ink: OnboardingTeachInk

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ink.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(ink.frost))
            .overlay(Capsule().strokeBorder(ink.frostEdge, lineWidth: 1))
            .shadow(color: ink.shadow, radius: 7, y: 4)
            .opacity(ink.miniPillOpacity)
    }
}

// MARK: Card 2: Go Back

/// When each part of the Go Back demo happens, in seconds (the mockup's BACK).
enum OnboardingTeachBackTimes {
    static let touch = 0.8
    static let release = 1.9
    static let gone = 2.25
    static let tap = 3.6
    static let pushed = 4.05
    static let length = 4.8
    /// With Reduce Motion: the page pulled most of the way from the edge.
    static let still = 1.5
}

/// A finger pulls Water away from the left edge back to the grid, then taps Water again.
struct OnboardingTeachBackDemo: View {
    let time: Double
    let ink: OnboardingTeachInk

    private typealias Times = OnboardingTeachBackTimes

    private static let homeSidekicks: [OnboardingTeachSidekick] = [.jess, .make, .reminders, .water]

    var body: some View {
        let offset = pageOffset
        let share = Double(offset / OnboardingTeachScreen.width)
        let isMoving = share > 0 && share < 1
        return ZStack(alignment: .topLeading) {
            OnboardingTeachHomeScreen(sidekicks: Self.homeSidekicks, looks: [], ink: ink)
                .offset(x: CGFloat(-120 * (1 - share)))
            Color.black
                .opacity(0.1 * (1 - share))
            OnboardingTeachWaterPage(ink: ink, edgeShadowOpacity: isMoving ? 1 : 0)
                .offset(x: offset)
            OnboardingTeachStatusChrome(ink: ink)
            OnboardingTeachFinger(touch: fingerTouch, ink: ink)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
    }

    private var pageOffset: CGFloat {
        if time < Times.touch {
            return 0
        }
        if time < Times.release {
            // The page follows the finger from the edge
            return CGFloat(OnboardingTeachTiming.eased(time, from: Times.touch + 0.05, to: Times.release) * 300)
        }
        if time < Times.tap {
            return CGFloat(OnboardingTeachTiming.mix(300, 402, OnboardingTeachTiming.eased(time, from: Times.release, to: Times.gone)))
        }
        // Tapping Water pushes the page back in
        return CGFloat(402 * (1 - OnboardingTeachTiming.eased(time, from: Times.tap + 0.05, to: Times.pushed)))
    }

    private var fingerTouch: OnboardingTeachTouch {
        if time < Times.gone + 0.3 {
            let dragX = 10 + OnboardingTeachTiming.eased(time, from: Times.touch + 0.05, to: Times.release) * 300
            let fadeIn = OnboardingTeachTiming.eased(time, from: Times.touch - 0.4, to: Times.touch - 0.2)
            let fadeOut = OnboardingTeachTiming.eased(time, from: Times.release, to: Times.release + 0.2)
            let isPressed = OnboardingTeachTiming.within(time, from: Times.touch - 0.1, to: Times.release)
            return OnboardingTeachTouch(point: CGPoint(x: dragX, y: 430), visible: fadeIn * (1 - fadeOut), isPressed: isPressed)
        }
        let waterIndex = Self.homeSidekicks.firstIndex(of: .water) ?? 0
        let waterCentre = OnboardingTeachHomeGrid.tileCentre(waterIndex)
        return OnboardingTeachTouch.tap(at: waterCentre, tapAt: Times.tap, time: time)
    }
}

// MARK: Card 3: Make a Sidekick

/// When each part of the Make demo happens, in seconds (the mockup's MAKE).
enum OnboardingTeachMakeTimes {
    static let tapMake = 0.7
    static let pushed = 1.15
    static let listen = 1.8
    static let heard = 3.6
    static let send = 4.3
    static let building = 5.1
    static let built = 5.9
    static let builtScreen = 6.5
    static let move = 8.2
    static let landed = 8.96
    static let length = 10.4
    /// With Reduce Motion: the Built screen with the new tile.
    static let still = 7.0
}

/// Make opens, the problem is said, the request builds, and the new tile moves into its slot.
struct OnboardingTeachMakeDemo: View {
    let time: Double
    let ink: OnboardingTeachInk

    private typealias Times = OnboardingTeachMakeTimes

    private static let homeSidekicks: [OnboardingTeachSidekick] = [.jess, .make, .reminders, .water, .plants]

    private var plantsIndex: Int {
        Self.homeSidekicks.firstIndex(of: .plants) ?? 0
    }

    private var hasLanded: Bool {
        time >= Times.landed
    }

    private var push: Double {
        OnboardingTeachTiming.eased(time, from: Times.tapMake + 0.05, to: Times.pushed)
    }

    // Make gives way to the Built screen and is gone behind it
    private var isMakeGone: Bool {
        time >= Times.builtScreen + 0.4
    }

    private var builtIn: Double {
        OnboardingTeachTiming.eased(time, from: Times.builtScreen, to: Times.builtScreen + 0.3)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingTeachHomeScreen(sidekicks: Self.homeSidekicks, looks: homeLooks, ink: ink)
                .offset(x: isMakeGone ? 0 : CGFloat(-120 * push))
            Color.black
                .opacity(isMakeGone ? 0 : 0.1 * push)
            makeScreen
                .offset(x: CGFloat(402 * (1 - push)))
                .opacity(isMakeGone ? 0 : 1)
            OnboardingTeachStatusChrome(ink: ink)
            builtScreen
            flyer
            OnboardingTeachFinger(touch: fingerTouch, ink: ink)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
    }

    // Plants is not on the grid until it lands; its name fades in after
    private var homeLooks: [OnboardingTeachCellLook] {
        var looks = Array(repeating: OnboardingTeachCellLook.resting, count: Self.homeSidekicks.count)
        looks[plantsIndex].tileOpacity = hasLanded ? 1 : 0
        looks[plantsIndex].labelOpacity = OnboardingTeachTiming.eased(time, from: Times.landed + 0.1, to: Times.landed + 0.4)
        return looks
    }

    private var makeScreen: some View {
        let isListening = OnboardingTeachTiming.within(time, from: Times.listen, to: Times.heard + 0.3)
        let isSent = time >= Times.send + 0.05
        let heard = OnboardingTeachTiming.heardWords(OnboardingTeachCopy.makeAsk, time: time, from: Times.listen + 0.2, to: Times.heard)
        let pillWords = isSent ? "" : heard
        let emptyShown = 1 - OnboardingTeachTiming.eased(time, from: Times.send, to: Times.send + 0.2)
        let rowIn = OnboardingTeachTiming.eased(time, from: Times.send + 0.05, to: Times.send + 0.35)
        return ZStack(alignment: .topLeading) {
            ink.paper
            Text(OnboardingTeachCopy.makeName)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(ink.ink)
                .offset(x: 20, y: 60)
            Text(OnboardingTeachCopy.noRequests)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.ink2)
                .frame(width: OnboardingTeachScreen.width)
                .offset(y: 400)
                .opacity(emptyShown)
            requestRow
                .opacity(rowIn)
                .offset(y: 115 + CGFloat(1 - rowIn) * 12)
            OnboardingTeachPill(placeholder: OnboardingTeachCopy.makePlaceholder, words: pillWords, isListening: isListening, time: time, ink: ink)
                .offset(x: OnboardingTeachScreen.pillOrigin.x, y: OnboardingTeachScreen.pillOrigin.y)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
    }

    /// Sent (grey), then Building with three of four steps, then Built with four.
    private var requestStatus: (word: String, steps: Int, isGrey: Bool) {
        if time >= Times.built {
            return (OnboardingTeachCopy.statusBuilt, 4, false)
        }
        if time >= Times.building {
            return (OnboardingTeachCopy.statusBuilding, 3, false)
        }
        return (OnboardingTeachCopy.statusSent, 0, true)
    }

    private var requestRow: some View {
        let status = requestStatus
        let rowRule = Rectangle()
            .fill(ink.rule)
            .frame(height: 1)
            .padding(.leading, 20)
        return HStack(spacing: 12) {
            Text(OnboardingTeachCopy.makeAsk)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(status.word)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status.isGrey ? ink.ink2 : ink.ink)
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { stepIndex in
                        Circle()
                            .fill(stepIndex < status.steps ? ink.ink : ink.ink3)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(width: OnboardingTeachScreen.width, height: 66)
        .overlay(rowRule, alignment: .bottom)
    }

    // The Built screen (MakeBuiltView R2): the name under the new tile; it sits above the bar
    private var builtScreen: some View {
        let builtOut = OnboardingTeachTiming.eased(time, from: Times.move - 0.1, to: Times.move + 0.3)
        return ZStack(alignment: .topLeading) {
            ink.paper
            Text(OnboardingTeachCopy.plantsName)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(ink.ink)
                .frame(width: OnboardingTeachScreen.width)
                .offset(y: 372)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
        .opacity(builtIn * (1 - builtOut))
    }

    // The tile path: Built screen centre to the grid slot, 2x to 1x, dipping to 94% as it lands
    private var flyerFrame: (centre: CGPoint, scale: Double) {
        let slot = OnboardingTeachHomeGrid.tileCentre(plantsIndex)
        let move = OnboardingTeachTiming.eased(time, from: Times.move, to: Times.landed)
        var scale = OnboardingTeachTiming.mix(2, 1, move)
        let settle = OnboardingTeachTiming.linear(time, from: Times.landed - 0.12, to: Times.landed + 0.25)
        if settle > 0 && settle < 1 {
            scale = 1 - 0.06 * sin(settle * Double.pi)
        }
        let centreX = OnboardingTeachTiming.mix(201, Double(slot.x), move)
        let centreY = OnboardingTeachTiming.mix(290, Double(slot.y), move)
        return (CGPoint(x: centreX, y: centreY), scale)
    }

    private var flyer: some View {
        let frame = flyerFrame
        let isFlying = time >= Times.builtScreen && !hasLanded
        return OnboardingTeachTile(sidekick: .plants, size: 60)
            .scaleEffect(frame.scale)
            .opacity(isFlying ? builtIn : 0)
            .position(frame.centre)
    }

    // The finger: Make's tile, the orb, Send
    private var fingerTouch: OnboardingTeachTouch {
        if time < Times.pushed + 0.2 {
            let makeIndex = Self.homeSidekicks.firstIndex(of: .make) ?? 0
            return OnboardingTeachTouch.tap(at: OnboardingTeachHomeGrid.tileCentre(makeIndex), tapAt: Times.tapMake, time: time)
        }
        if time < Times.heard {
            return OnboardingTeachTouch.tap(at: OnboardingTeachScreen.orbPoint, tapAt: Times.listen, time: time)
        }
        return OnboardingTeachTouch.tap(at: OnboardingTeachScreen.sendPoint, tapAt: Times.send, time: time)
    }
}

// MARK: Card 4: Delete a Sidekick

/// When each part of the Delete demo happens, in seconds (the mockup's DELETE).
enum OnboardingTeachDeleteTimes {
    static let hold = 0.6
    static let jiggle = 1.4
    static let lift = 1.7
    static let minus = 2.5
    static let sheet = 2.6
    static let tapDelete = 3.9
    static let gone = 4.1
    static let done = 5.6
    static let length = 7.0
    /// With Reduce Motion: the tiles jiggling, the minus badges, the sheet up.
    static let still = 3.2
}

/// Press and hold Water, the tiles jiggle, tap the minus, Delete on the sheet, tap to finish.
struct OnboardingTeachDeleteDemo: View {
    let time: Double
    let ink: OnboardingTeachInk

    private typealias Times = OnboardingTeachDeleteTimes

    private static let homeSidekicks: [OnboardingTeachSidekick] = [.jess, .make, .reminders, .water]
    /// Taller than the sheet, so it starts and ends fully below the screen.
    private static let sheetTravel: CGFloat = 340

    private var waterCentre: CGPoint {
        let waterIndex = Self.homeSidekicks.firstIndex(of: .water) ?? 0
        return OnboardingTeachHomeGrid.tileCentre(waterIndex)
    }

    private var sheetIn: Double {
        let rising = OnboardingTeachTiming.eased(time, from: Times.sheet, to: Times.sheet + 0.35)
        let falling = OnboardingTeachTiming.eased(time, from: Times.gone, to: Times.gone + 0.3)
        return rising * (1 - falling)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingTeachHomeScreen(sidekicks: Self.homeSidekicks, looks: homeLooks, ink: ink)
            ink.dim
                .opacity(sheetIn)
            OnboardingTeachDeleteSheet(ink: ink)
                .offset(y: CGFloat(1 - sheetIn) * 1.1 * Self.sheetTravel)
                .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .bottom)
            OnboardingTeachStatusChrome(ink: ink)
            OnboardingTeachFinger(touch: fingerTouch, ink: ink)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
    }

    private var homeLooks: [OnboardingTeachCellLook] {
        let isJiggling = OnboardingTeachTiming.within(time, from: Times.jiggle, to: Times.done)
        let badgeIn = OnboardingTeachTiming.eased(time, from: Times.jiggle, to: Times.jiggle + 0.25)
            * (1 - OnboardingTeachTiming.eased(time, from: Times.done, to: Times.done + 0.2))
        var looks: [OnboardingTeachCellLook] = []
        for (index, sidekick) in Self.homeSidekicks.enumerated() {
            var look = OnboardingTeachCellLook.resting
            // The iOS jiggle: 2 degrees each way, every tile a little out of step
            look.angle = isJiggling ? sin(time * 1000 / 70 + Double(index)) * 2 : 0
            if sidekick == .water {
                look.scale = waterScale
                let gone = OnboardingTeachTiming.eased(time, from: Times.gone + 0.15, to: Times.gone + 0.45)
                look.scale *= 1 - gone
                look.opacity = 1 - gone
            }
            look.badgeScale = sidekick.isBuiltIn ? 0 : badgeIn
            looks.append(look)
        }
        return looks
    }

    // The held tile lifts a little before the jiggle
    private var waterScale: Double {
        guard OnboardingTeachTiming.within(time, from: Times.hold, to: Times.jiggle + 0.2) else {
            return 1
        }
        let lifting = OnboardingTeachTiming.eased(time, from: Times.hold, to: Times.jiggle)
        let settling = OnboardingTeachTiming.eased(time, from: Times.jiggle, to: Times.jiggle + 0.2)
        return 1 + 0.08 * lifting * (1 - settling)
    }

    private var fingerTouch: OnboardingTeachTouch {
        if time < Times.lift + 0.3 {
            let fadeIn = OnboardingTeachTiming.eased(time, from: Times.hold - 0.4, to: Times.hold - 0.2)
            let fadeOut = OnboardingTeachTiming.eased(time, from: Times.lift, to: Times.lift + 0.2)
            let isPressed = OnboardingTeachTiming.within(time, from: Times.hold - 0.1, to: Times.lift)
            return OnboardingTeachTouch(point: waterCentre, visible: fadeIn * (1 - fadeOut), isPressed: isPressed)
        }
        if time < Times.sheet + 0.4 {
            let minusPoint = CGPoint(x: waterCentre.x - 30, y: waterCentre.y - 30)
            return OnboardingTeachTouch.tap(at: minusPoint, tapAt: Times.minus, time: time)
        }
        if time < Times.gone + 0.4 {
            return OnboardingTeachTouch.tap(at: OnboardingTeachDeleteSheet.deleteButtonCentre, tapAt: Times.tapDelete, time: time)
        }
        // A tap on empty space ends the jiggle
        return OnboardingTeachTouch.tap(at: CGPoint(x: 280, y: 520), tapAt: Times.done, time: time)
    }
}

/// The Midas sheet (C3): the tile, "Delete Water?", the line, Delete in red, Cancel.
struct OnboardingTeachDeleteSheet: View {
    let ink: OnboardingTeachInk

    /// Delete's centre: under it 10 pt gap, Cancel 44 pt and 46 pt of padding; it is 52 pt tall.
    static let deleteButtonCentre = CGPoint(x: 201, y: 874 - 46 - 44 - 10 - 26)

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        let grabber = Capsule()
            .fill(ink.ink3)
            .frame(width: 36, height: 5)
            .padding(.top, 7)
        return VStack(spacing: 10) {
            OnboardingTeachTile(sidekick: .water, size: 60)
            Text(OnboardingTeachCopy.deleteQuestion)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(ink.ink)
                .padding(.top, 4)
            Text(OnboardingTeachCopy.deleteMessage)
                .font(.system(size: 15))
                .foregroundStyle(ink.ink2)
            Text(OnboardingTeachCopy.deleteButton)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
                .background(Capsule().fill(ink.red))
                .padding(.top, 8)
            Text(OnboardingTeachCopy.cancelButton)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ink.ink)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        }
        .padding(.top, 26)
        .padding(.horizontal, 24)
        .padding(.bottom, 46)
        .frame(width: OnboardingTeachScreen.width)
        .background(shape.fill(ink.sheet).shadow(color: ink.shadow, radius: 15, y: -8))
        .overlay(grabber, alignment: .top)
    }
}
