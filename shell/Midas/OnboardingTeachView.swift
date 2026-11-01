import SwiftUI

// The teaching cards, right after the first sign-in on this phone (founder, 2026-10-31;
// docs/mockups/onboarding-teach-2026-10-31.html, picks K4 and T2; docs/briefs/onboarding-build.md
// "Order on a new install", step 3). Four cards the person swipes across, each a looping demo in
// the Add Widget demo's style on the Add Widget card: Edit Any Sidekick, Go Back, Make a Sidekick,
// Delete a Sidekick. No Skip; "Next" between cards, "Continue" on the last. With Reduce Motion
// each demo holds one still frame.

/// Every word on the teaching cards, as the mockup has them (docs/WRITING.md).
enum OnboardingTeachCopy {
    // The cards
    static let editTitle = "Edit Any Sidekick"
    static let editLine = "Swipe down with three fingers."
    static let backTitle = "Go Back"
    static let backLine = "Swipe from the left edge."
    static let makeTitle = "Make a Sidekick"
    static let makeLine = "Say the problem in your words."
    static let deleteTitle = "Delete a Sidekick"
    static let deleteLine = "Press and hold its tile."
    static let nextButton = "Next"
    static let continueButton = "Continue"

    // The demo phone
    static let statusTime = "9:41"
    static let homeTitle = "Midas"
    static let initial = "B"
    static let jessName = "Jess"
    static let makeName = "Make"
    static let remindersName = "Reminders"
    static let waterName = "Water"
    static let plantsName = "Plants"

    // Water's page
    static let waterHelp = "?"
    static let waterAmount = "1.25 L"
    static let waterGoal = "of 2 L"
    static let waterAddSmall = "+250 ml"
    static let waterAddLarge = "+500 ml"
    static let waterLog = [
        OnboardingTeachLogEntry(amount: "250 ml", time: "8:10"),
        OnboardingTeachLogEntry(amount: "500 ml", time: "8:42"),
        OnboardingTeachLogEntry(amount: "500 ml", time: "9:20"),
    ]

    // The Edit layer
    static let tagEdit = "Edit"
    static let tagOnIt = "On it"
    static let tagEditing = "Editing"
    static let undo = "Undo"
    static let clear = "Clear"
    static let editPlaceholder = "What to fix"
    static let editAsk = "Make the glass bigger"

    // Make
    static let noRequests = "No Requests"
    static let makePlaceholder = "New Request"
    static let makeAsk = "I forget to water my plants"
    static let statusSent = "Sent"
    static let statusBuilding = "Building"
    static let statusBuilt = "Built"

    // Delete
    static let deleteQuestion = "Delete Water?"
    static let deleteMessage = "Its data goes too."
    static let deleteButton = "Delete"
    static let cancelButton = "Cancel"
}

/// One drink on Water's page.
struct OnboardingTeachLogEntry: Sendable {
    let amount: String
    let time: String
}

/// The four cards (K4), in order.
enum OnboardingTeachCard: Int, CaseIterable, Identifiable {
    case edit
    case back
    case make
    case delete

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .edit: OnboardingTeachCopy.editTitle
        case .back: OnboardingTeachCopy.backTitle
        case .make: OnboardingTeachCopy.makeTitle
        case .delete: OnboardingTeachCopy.deleteTitle
        }
    }

    var line: String {
        switch self {
        case .edit: OnboardingTeachCopy.editLine
        case .back: OnboardingTeachCopy.backLine
        case .make: OnboardingTeachCopy.makeLine
        case .delete: OnboardingTeachCopy.deleteLine
        }
    }

    /// One loop of the demo, in seconds.
    var length: Double {
        switch self {
        case .edit: OnboardingTeachEditTimes.length
        case .back: OnboardingTeachBackTimes.length
        case .make: OnboardingTeachMakeTimes.length
        case .delete: OnboardingTeachDeleteTimes.length
        }
    }

    /// The frame held with Reduce Motion.
    var stillTime: Double {
        switch self {
        case .edit: OnboardingTeachEditTimes.still
        case .back: OnboardingTeachBackTimes.still
        case .make: OnboardingTeachMakeTimes.still
        case .delete: OnboardingTeachDeleteTimes.still
        }
    }
}

/// Where everything sits on the 402 x 874 pt screen, layout T2 (the Add Widget card).
enum OnboardingTeachSpec {
    static let screenSize = CGSize(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height)
    /// The wall-coloured card behind the demo.
    static let wallFrame = CGRect(x: 20, y: 66, width: 362, height: 570)
    static let wallCorner: CGFloat = 30
    /// The demo screen, scaled from 402 pt wide to 242.
    static let holderFrame = CGRect(x: 80, y: 88, width: 242, height: 526)
    static let holderCorner: CGFloat = 34
    static let demoScale: CGFloat = 242 / 402
    static let titleTop: CGFloat = 658
    static let lineTop: CGFloat = 688
    static let dotsTop: CGFloat = 740
    static let sideInset: CGFloat = 24
    static let buttonHeight: CGFloat = 52
    static let buttonBottom: CGFloat = 34
    /// The page turns on a drag past a sixth of the screen, or a fling faster than this.
    static let flingSpeed: CGFloat = 500
    /// Past the first and last card the track follows the finger at this share.
    static let rubberBand: CGFloat = 0.35
    static let settleSeconds = 0.32

    /// The whole screen scaled to fit the phone (1 on an iPhone 16 Pro).
    static func fitScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / screenSize.width
        let heightScale = size.height / screenSize.height
        return min(widthScale, heightScale)
    }
}

/// Shown full screen right after sign-in; `onContinue` runs on "Continue" on the last card.
struct OnboardingTeachView: View {
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = OnboardingTeachInk(colorScheme: colorScheme)
        GeometryReader { proxy in
            OnboardingTeachPager(scale: OnboardingTeachSpec.fitScale(for: proxy.size), onContinue: onContinue)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(ink.paper)
        .ignoresSafeArea()
    }
}

/// The swipe-over: the track of cards, the dots and the button, at 402 x 874 pt scaled to fit.
struct OnboardingTeachPager: View {
    let scale: CGFloat
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    /// How far the finger has moved the track from the current card, in screen points.
    @State private var dragOffset: CGFloat = 0
    /// When each card's demo started its loop; a card starts again from 0 when it settles.
    @State private var demoStarts: [Date] = Array(repeating: Date(), count: OnboardingTeachCard.allCases.count)

    private static let cards = OnboardingTeachCard.allCases
    private static let screenWidth = OnboardingTeachScreen.width

    private var ink: OnboardingTeachInk {
        OnboardingTeachInk(colorScheme: colorScheme)
    }

    private var lastIndex: Int {
        Self.cards.count - 1
    }

    private var trackOffset: CGFloat {
        -CGFloat(index) * Self.screenWidth + dragOffset
    }

    /// Where the track is, in cards (0 to the last), for the dots and the button.
    private var trackPosition: Double {
        let raw = Double(-trackOffset / Self.screenWidth)
        return min(Double(lastIndex), max(0, raw))
    }

    /// 1 on the last card, fading to 0 a card away: how much the button says Continue.
    private var continueShare: Double {
        let distance = abs(trackPosition - Double(lastIndex))
        return min(1, max(0, 1 - distance))
    }

    private var settleAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: OnboardingTeachSpec.settleSeconds)
    }

    var body: some View {
        canvas
            .frame(width: OnboardingTeachSpec.screenSize.width, height: OnboardingTeachSpec.screenSize.height)
            .scaleEffect(scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(pageDrag)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(paused: reduceMotion)) { context in
                track(at: context.date)
            }
            dots
                .frame(width: Self.screenWidth)
                .offset(y: OnboardingTeachSpec.dotsTop)
            finishButton
                .offset(x: OnboardingTeachSpec.sideInset,
                        y: OnboardingTeachSpec.screenSize.height - OnboardingTeachSpec.buttonBottom - OnboardingTeachSpec.buttonHeight)
        }
        .frame(width: OnboardingTeachSpec.screenSize.width, height: OnboardingTeachSpec.screenSize.height, alignment: .topLeading)
        .clipped()
    }

    // Every card draws, so a card half in view during a swipe still moves
    private func track(at date: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.cards) { card in
                OnboardingTeachCardView(card: card, time: demoTime(of: card, at: date), ink: ink)
            }
        }
        .frame(width: Self.screenWidth * CGFloat(Self.cards.count), alignment: .leading)
        .offset(x: trackOffset)
    }

    /// Seconds into the card's loop; with Reduce Motion its still frame.
    private func demoTime(of card: OnboardingTeachCard, at date: Date) -> Double {
        if reduceMotion {
            return card.stillTime
        }
        let elapsed = date.timeIntervalSince(demoStarts[card.rawValue])
        return max(0, elapsed).truncatingRemainder(dividingBy: card.length)
    }

    private var dots: some View {
        let nearest = Int(trackPosition.rounded())
        return HStack(spacing: 7) {
            ForEach(Self.cards) { card in
                Circle()
                    .fill(card.rawValue == nearest ? ink.ink : ink.ink3)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    // "Next" on every card but the last, "Continue" on the last; the words crossfade with the swipe
    private var finishButton: some View {
        let isLast = index == lastIndex
        let label = ZStack {
            Text(OnboardingTeachCopy.nextButton)
                .opacity(1 - continueShare)
            Text(OnboardingTeachCopy.continueButton)
                .opacity(continueShare)
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(ink.paper)
        .frame(width: Self.screenWidth - OnboardingTeachSpec.sideInset * 2, height: OnboardingTeachSpec.buttonHeight)
        .background(Capsule().fill(ink.ink))
        return Button(action: finishTapped) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLast ? OnboardingTeachCopy.continueButton : OnboardingTeachCopy.nextButton)
    }

    private func finishTapped() {
        if index < lastIndex {
            settle(to: index + 1)
            return
        }
        onContinue()
    }

    // MARK: Swipe

    private var pageDrag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged(followDrag)
            .onEnded(finishDrag)
    }

    /// The track follows the finger; past the first and last card it gives way at a third.
    private func followDrag(_ value: DragGesture.Value) {
        let moved = value.translation.width / max(scale, 0.01)
        let restingOffset = -CGFloat(index) * Self.screenWidth
        let lastOffset = -CGFloat(lastIndex) * Self.screenWidth
        var offset = restingOffset + moved
        if offset > 0 {
            offset *= OnboardingTeachSpec.rubberBand
        } else if offset < lastOffset {
            offset = lastOffset + (offset - lastOffset) * OnboardingTeachSpec.rubberBand
        }
        dragOffset = offset - restingOffset
    }

    // A fling or a drag past a sixth of the screen turns the page
    private func finishDrag(_ value: DragGesture.Value) {
        let speed = value.velocity.width / max(scale, 0.01)
        let threshold = Self.screenWidth / 6
        var target = index
        if dragOffset < -threshold || speed < -OnboardingTeachSpec.flingSpeed {
            target = index + 1
        } else if dragOffset > threshold || speed > OnboardingTeachSpec.flingSpeed {
            target = index - 1
        }
        settle(to: target)
    }

    private func settle(to requested: Int) {
        let target = min(lastIndex, max(0, requested))
        if target != index {
            demoStarts[target] = Date()
        }
        withAnimation(settleAnimation) {
            index = target
            dragOffset = 0
        }
    }
}

/// One card, layout T2: the demo on the wall-coloured card, the title and the line under it.
struct OnboardingTeachCardView: View {
    let card: OnboardingTeachCard
    let time: Double
    let ink: OnboardingTeachInk

    var body: some View {
        let wallShape = RoundedRectangle(cornerRadius: OnboardingTeachSpec.wallCorner, style: .continuous)
        let wall = OnboardingTeachSpec.wallFrame
        let holder = OnboardingTeachSpec.holderFrame
        let textWidth = OnboardingTeachScreen.width - OnboardingTeachSpec.sideInset * 2
        return ZStack(alignment: .topLeading) {
            wallShape
                .fill(ink.wall)
                .overlay(wallShape.strokeBorder(ink.rule, lineWidth: 1))
                .frame(width: wall.width, height: wall.height)
                .offset(x: wall.minX, y: wall.minY)
            scaledDemo
                .offset(x: holder.minX, y: holder.minY)
            Text(card.title)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.19)
                .foregroundStyle(ink.ink)
                .multilineTextAlignment(.center)
                .frame(width: textWidth)
                .offset(x: OnboardingTeachSpec.sideInset, y: OnboardingTeachSpec.titleTop)
            Text(card.line)
                .font(.system(size: 15))
                .lineSpacing(2)
                .foregroundStyle(ink.ink2)
                .multilineTextAlignment(.center)
                .frame(width: textWidth)
                .offset(x: OnboardingTeachSpec.sideInset, y: OnboardingTeachSpec.lineTop)
        }
        .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // The real 402 x 874 screen, scaled whole into the holder so it looks exactly as on the phone
    private var scaledDemo: some View {
        let holder = OnboardingTeachSpec.holderFrame
        let holderShape = RoundedRectangle(cornerRadius: OnboardingTeachSpec.holderCorner, style: .continuous)
        return demo
            .frame(width: OnboardingTeachScreen.width, height: OnboardingTeachScreen.height, alignment: .topLeading)
            .background(ink.paper)
            .scaleEffect(OnboardingTeachSpec.demoScale, anchor: .topLeading)
            .frame(width: holder.width, height: holder.height, alignment: .topLeading)
            .clipShape(holderShape)
            .overlay(holderShape.strokeBorder(ink.rule, lineWidth: 1))
            .background(holderShape.fill(ink.paper).shadow(color: ink.shadow, radius: 15, y: 12))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var demo: some View {
        switch card {
        case .edit:
            OnboardingTeachEditDemo(time: time, ink: ink)
        case .back:
            OnboardingTeachBackDemo(time: time, ink: ink)
        case .make:
            OnboardingTeachMakeDemo(time: time, ink: ink)
        case .delete:
            OnboardingTeachDeleteDemo(time: time, ink: ink)
        }
    }
}

#Preview("Light") {
    OnboardingTeachView(onContinue: OnboardingTeachPreview.continueTapped)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingTeachView(onContinue: OnboardingTeachPreview.continueTapped)
        .preferredColorScheme(.dark)
}

/// What the previews do on Continue: nothing.
enum OnboardingTeachPreview {
    static func continueTapped() {}
}
