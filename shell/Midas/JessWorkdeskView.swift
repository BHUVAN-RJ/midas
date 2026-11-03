import SwiftUI

// jess's Workdesk (founder, 2026-10-22; approved mockup docs/mockups/jess-workdesk-2026-10-22.html,
// "W4 stack", scroll "A, carousel"): the jess screen shows every task jess has done as a stack at
// the top and the orb at the bottom. The newest task is one big card, the next two are slim cards,
// two more are tucked behind showing only their edges. A new task comes out of the orb (fast, a
// slight overshoot, a slow settle) while the stack moves down one slot like a carousel. The finger
// moves the stack one slot per card and it snaps to a card on release. No scroll bar, no dots.
// No status words except where the Sidekick is not known yet: the card's orb core says the status.
// A card swiped sideways shows Delete, as the Reminders Sidekick's rows do (founder, 2026-11-02,
// build 22 feedback, docs/mockups/build22-feedback-2026-11-02.html; was a fling away, 2026-10-31).
// Tap Delete or swipe all the way to delete; a task not finished is stopped (JessResults).

/// Swipe to show Delete on a Workdesk card: follows the finger, then rests open (Delete showing),
/// closes, or deletes when swiped most of the way across. Either direction, as in Reminders.
enum WorkdeskSwipeReveal {
    /// How wide Delete is when the card rests open.
    static let buttonWidth: Double = 84
    /// Swiped this share of the card's width, the card is deleted on release.
    static let fullSwipeShare: Double = 0.6
    static let settle = Animation.spring(response: 0.3, dampingFraction: 0.85)

    enum Settle: Equatable {
        case closed
        /// Rests with Delete showing; negative is open to the left (Delete on the right).
        case open(offset: Double)
        /// Off to the right (+1) or the left (-1).
        case delete(direction: Double)
    }

    /// Where the card is while the finger moves: from where it started (open or closed), never
    /// past the card's width.
    static func dragOffset(startOffset: Double, translation: Double, cardWidth: Double) -> Double {
        let raw = startOffset + translation
        return min(max(raw, -cardWidth), cardWidth)
    }

    /// Where the card goes when the finger lifts.
    static func settle(startOffset: Double, translation: Double, predicted: Double, cardWidth: Double) -> Settle {
        let finalOffset = startOffset + translation
        let predictedOffset = startOffset + predicted
        let direction: Double = finalOffset < 0 ? -1 : 1
        if abs(finalOffset) >= cardWidth * fullSwipeShare {
            return .delete(direction: direction)
        }
        // Thrown back towards closed, or not far enough to show Delete: closes
        let thrownShut = (predictedOffset < 0) != (finalOffset < 0) || abs(predictedOffset) < buttonWidth / 2
        if abs(finalOffset) < buttonWidth / 2 || thrownShut {
            return .closed
        }
        return .open(offset: direction * buttonWidth)
    }
}

/// Where a card sits for its position in the stack (0 is the big card; fractions while moving).
struct JessWorkdeskSlot: Equatable, Sendable {
    var top: Double
    var height: Double
    var scale: Double
    var opacity: Double
    var radius: Double
    /// 1 is the big card's look, 0 the slim card's.
    var big: Double
    /// 1 shows the words, 0 a tucked card's bare edge.
    var content: Double
    var z: Double
}

/// The stack's slots, from the mockup (402 pt wide phone).
enum JessWorkdeskLayout {
    static let slots: [JessWorkdeskSlot] = [
        JessWorkdeskSlot(top: 0, height: 156, scale: 1, opacity: 1, radius: 22, big: 1, content: 1, z: 10),
        JessWorkdeskSlot(top: 166, height: 64, scale: 1, opacity: 1, radius: 16, big: 0, content: 1, z: 9),
        JessWorkdeskSlot(top: 240, height: 64, scale: 1, opacity: 1, radius: 16, big: 0, content: 1, z: 8),
        JessWorkdeskSlot(top: 262, height: 64, scale: 0.95, opacity: 0.85, radius: 16, big: 0, content: 0, z: 7),
        JessWorkdeskSlot(top: 278, height: 64, scale: 0.9, opacity: 0.5, radius: 16, big: 0, content: 0, z: 6),
        JessWorkdeskSlot(top: 290, height: 64, scale: 0.85, opacity: 0, radius: 16, big: 0, content: 0, z: 5),
    ]
    /// A card scrolled past the top leaves upwards, behind the others.
    static let exit = JessWorkdeskSlot(top: -70, height: 156, scale: 0.92, opacity: 0, radius: 22, big: 1, content: 1, z: 0)
    static let stackHeight: Double = 354
    /// Finger travel that moves the stack by one card.
    static let dragPerCard: Double = 110
    /// Past either end the stack follows the finger at a third of the distance.
    static let rubberBand: Double = 1.0 / 3.0

    /// The slot for a position; between two slots the values are blended.
    static func slot(at position: Double) -> JessWorkdeskSlot {
        if position <= -1 {
            return exit
        }
        if position < 0 {
            return blend(from: exit, to: slots[0], amount: position + 1)
        }
        let lastIndex = slots.count - 1
        if position >= Double(lastIndex) {
            return slots[lastIndex]
        }
        let lower = Int(position.rounded(.down))
        return blend(from: slots[lower], to: slots[lower + 1], amount: position - Double(lower))
    }

    /// How much of the big look shows: none until the card is halfway grown, then quickly all, so
    /// the big and slim words never overlap.
    static func bigLookOpacity(_ slot: JessWorkdeskSlot) -> Double {
        clamp((slot.big - 0.5) / 0.35)
    }

    static func slimLookOpacity(_ slot: JessWorkdeskSlot) -> Double {
        clamp((0.5 - slot.big) / 0.35)
    }

    /// The scroll while the finger drags: past the newest or the oldest card it moves less.
    static func draggedScroll(startScroll: Double, translation: Double, cardCount: Int) -> Double {
        let raw = startScroll - translation / dragPerCard
        let lastCard = Double(max(cardCount - 1, 0))
        if raw < 0 {
            return raw * rubberBand
        }
        if raw > lastCard {
            return lastCard + (raw - lastCard) * rubberBand
        }
        return raw
    }

    /// Where the stack settles on release: the card the flick carries it to.
    static func settledScroll(startScroll: Double, predictedTranslation: Double, cardCount: Int) -> Double {
        let predicted = startScroll - predictedTranslation / dragPerCard
        let lastCard = Double(max(cardCount - 1, 0))
        return min(max(predicted.rounded(), 0), lastCard)
    }

    /// The card under a finger at `y` (from the stack's top): the front-most one showing its words.
    /// Tucked cards and the empty space below the stack are none.
    static func cardIndex(atY y: Double, scroll: Double, cardCount: Int) -> Int? {
        var found: Int?
        var foundZ = -Double.infinity
        for index in 0..<cardCount {
            let slot = slot(at: Double(index) - scroll)
            // Scaled from its top, so its bottom is its top plus the scaled height
            let bottom = slot.top + slot.height * slot.scale
            let showsWords = slot.content > 0.5 && slot.opacity > 0.5
            if showsWords && y >= slot.top && y <= bottom && slot.z > foundZ {
                found = index
                foundZ = slot.z
            }
        }
        return found
    }

    /// A tap opens a card's Sidekick only for a done card with a change, big or slim, not tucked.
    static func tapOpens(_ card: JessResultCard, slot: JessWorkdeskSlot) -> Bool {
        card.opensChange && slot.content > 0.5 && slot.opacity > 0.5
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func blend(from start: JessWorkdeskSlot, to end: JessWorkdeskSlot, amount: Double) -> JessWorkdeskSlot {
        func mix(_ startValue: Double, _ endValue: Double) -> Double {
            startValue + (endValue - startValue) * amount
        }
        return JessWorkdeskSlot(
            top: mix(start.top, end.top),
            height: mix(start.height, end.height),
            scale: mix(start.scale, end.scale),
            opacity: mix(start.opacity, end.opacity),
            radius: mix(start.radius, end.radius),
            big: mix(start.big, end.big),
            content: mix(start.content, end.content),
            z: mix(start.z, end.z)
        )
    }
}

/// The mockup's timings.
enum JessWorkdeskMotion {
    /// The card out of the orb: fast, past full size, then a slow settle (820 ms).
    static let arrival = Animation.interpolatingSpring(duration: 0.82, bounce: 0.22)
    /// The stack moving one slot, a little after the card starts (700 ms, 80 ms later).
    static let stackMove = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.7).delay(0.08)
    /// Settling on a card after the finger lets go.
    static let snap = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)
    /// A card's words when its result changes.
    static let wordsChange = Animation.easeOut(duration: 0.42)
    /// A card counts as just said, and comes out of the orb, for this long.
    static let arrivalWindow: TimeInterval = 2
}

extension JessResultCard {
    /// The Workdesk card's orb: a request sent to repair waits grey until the repair is live.
    var workdeskOrbState: JessOrbState {
        if case .sentToRepair(_, let link) = kind, link != nil {
            return .idle
        }
        return orbState
    }
}

/// Grows the new card out of the orb: from the orb's place, small and clear, to its slot.
private struct JessOrbArrivalEffect: ViewModifier {
    let rise: Double
    let scale: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .center)
            .offset(y: rise)
            .opacity(opacity)
    }
}

/// One card of the stack, with both looks; the slot says which shows.
struct JessWorkdeskCardView: View {
    let card: JessResultCard
    let slot: JessWorkdeskSlot
    let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: slot.radius, style: .continuous)
        ZStack {
            shape.fill(fill)
            shape.stroke(stroke, lineWidth: 1)
            ZStack {
                bigLook
                    .opacity(JessWorkdeskLayout.bigLookOpacity(slot))
                slimLook
                    .opacity(JessWorkdeskLayout.slimLookOpacity(slot))
            }
            .opacity(slot.content)
            .animation(JessWorkdeskMotion.wordsChange, value: card.kind)
        }
        .frame(height: slot.height)
        .accessibilityElement(children: .combine)
    }

    private var bigLook: some View {
        HStack(alignment: .center, spacing: 12) {
            JessOrb(state: card.workdeskOrbState)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(VoiceReminderCopy.workdeskLine(card))
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(3)
                let meta = VoiceReminderCopy.workdeskMeta(card)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 14))
                        .opacity(0.6)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            retryButton(fontSize: 14)
        }
        .padding(.horizontal, 16)
    }

    private var slimLook: some View {
        HStack(alignment: .center, spacing: 10) {
            JessOrb(state: card.workdeskOrbState)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(VoiceReminderCopy.workdeskLine(card))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                let meta = VoiceReminderCopy.workdeskMeta(card)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 12))
                        .opacity(0.6)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            retryButton(fontSize: 12)
        }
        .padding(.horizontal, 12)
    }

    /// Try Again, always on the right of a Not Done card.
    @ViewBuilder
    private func retryButton(fontSize: CGFloat) -> some View {
        if let actionTitle = VoiceReminderCopy.cardActionTitle(card) {
            Button(actionTitle, action: onRetry)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(Capsule().fill(colorScheme == .dark ? Color.white : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)))
        }
    }

    private var fill: Color {
        colorScheme == .dark ? Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255) : Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
    }

    private var stroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.08)
    }
}

/// The stack of tasks at the top of the Workdesk.
struct JessWorkdeskStack: View {
    let cards: [JessResultCard]
    /// How far below the big card's centre the orb is, for the card coming out of it.
    let riseFromOrb: Double
    let onRetry: (UUID) -> Void
    /// A card swiped sideways: it leaves the log.
    var onDelete: (UUID) -> Void = JessWorkdeskStack.keepCard
    /// A done card tapped: its Sidekick opens at the change (founder, 2026-10-31).
    var onOpen: (UUID) -> Void = JessWorkdeskStack.keepCard

    @State private var scroll: Double = 0
    @State private var dragStartScroll: Double?
    /// One drag moves the stack up and down or one card sideways, decided by how it starts.
    @State private var dragAxis: DragAxis = .undecided
    /// The card under the finger or resting open with Delete showing, and how far it is moved.
    @State private var swipedCardId: UUID?
    @State private var swipeOffset: Double = 0
    /// Where the swiped card was when this drag began (0 closed, ±buttonWidth open).
    @State private var swipeStartOffset: Double = 0
    @State private var stackWidth: Double = 370

    enum DragAxis {
        case undecided
        case vertical
        case sideways
    }

    nonisolated static func keepCard(_ cardId: UUID) {}

    /// One card with its place in the log.
    private struct Entry: Identifiable {
        let index: Int
        let card: JessResultCard
        var id: UUID { card.id }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(visibleEntries) { entry in
                let slot = JessWorkdeskLayout.slot(at: Double(entry.index) - scroll)
                let offset = entry.card.id == swipedCardId ? swipeOffset : 0
                ZStack {
                    if offset != 0 {
                        deleteButton(for: entry.card, slot: slot, offset: offset)
                    }
                    JessWorkdeskCardView(card: entry.card, slot: slot, onRetry: retryAction(for: entry.card))
                        .offset(x: offset)
                        .onTapGesture(perform: openAction(for: entry.card, slot: slot))
                }
                    .accessibilityAddTraits(entry.card.opensChange ? .isLink : [])
                    .accessibilityAction(named: Text(CardSwipeDeleteCopy.delete), deleteAction(for: entry.card))
                    .scaleEffect(slot.scale, anchor: .top)
                    .offset(y: slot.top)
                    .opacity(slot.opacity)
                    .zIndex(slot.z)
                    .transition(transition(for: entry))
            }
        }
        .frame(maxWidth: .infinity, minHeight: JessWorkdeskLayout.stackHeight, maxHeight: JessWorkdeskLayout.stackHeight, alignment: .top)
        .onGeometryChange(for: Double.self, of: Self.widthOf, action: rememberWidth)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 5).onChanged(followFinger).onEnded(settleOnCard))
        .animation(JessWorkdeskMotion.stackMove, value: cardIds)
        .onChange(of: cards.first?.id, backToNewest)
        .onChange(of: cards.count, keepScrollOnACard)
    }

    private var cardIds: [UUID] {
        var ids: [UUID] = []
        for card in cards {
            ids.append(card.id)
        }
        return ids
    }

    /// Only the cards near the slots are drawn: one above for the one leaving, six below.
    private var visibleEntries: [Entry] {
        let first = max(Int(scroll.rounded(.down)) - 1, 0)
        let last = min(Int(scroll.rounded(.up)) + JessWorkdeskLayout.slots.count, cards.count - 1)
        var entries: [Entry] = []
        if first > last {
            return entries
        }
        for index in first...last {
            entries.append(Entry(index: index, card: cards[index]))
        }
        return entries
    }

    /// The task just said comes out of the orb; any other card only fades.
    private func transition(for entry: Entry) -> AnyTransition {
        let justSaid = entry.index == 0 && entry.card.kind == .working && Date().timeIntervalSince(entry.card.createdAt) < JessWorkdeskMotion.arrivalWindow
        guard justSaid else {
            return .opacity
        }
        let fromOrb = JessOrbArrivalEffect(rise: riseFromOrb, scale: 0.12, opacity: 0)
        let inSlot = JessOrbArrivalEffect(rise: 0, scale: 1, opacity: 1)
        let arrival = AnyTransition.modifier(active: fromOrb, identity: inSlot).animation(JessWorkdeskMotion.arrival)
        return .asymmetric(insertion: arrival, removal: .opacity)
    }

    private func retryAction(for card: JessResultCard) -> () -> Void {
        let cardId = card.id
        let retry = onRetry
        func retryCard() {
            retry(cardId)
        }
        return retryCard
    }

    /// Only a done card with a change opens, and only while its words show (not a tucked edge).
    private func openAction(for card: JessResultCard, slot: JessWorkdeskSlot) -> () -> Void {
        let cardId = card.id
        let open = onOpen
        let opens = JessWorkdeskLayout.tapOpens(card, slot: slot)
        func openCard() {
            // A card showing Delete closes instead of opening
            if swipedCardId != nil {
                closeSwipe()
                return
            }
            if opens {
                open(cardId)
            }
        }
        return openCard
    }

    nonisolated private static func widthOf(_ proxy: GeometryProxy) -> Double {
        proxy.size.width
    }

    private func rememberWidth(_ width: Double) {
        stackWidth = width
    }

    /// Red Delete behind the card, on the side the card moved away from; it grows with the swipe.
    private func deleteButton(for card: JessResultCard, slot: JessWorkdeskSlot, offset: Double) -> some View {
        let width = max(abs(offset) - 6, 0)
        let alignment: Alignment = offset < 0 ? .trailing : .leading
        return Button(action: deleteAction(for: card)) {
            Text(CardSwipeDeleteCopy.delete)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: width, height: slot.height)
                .background(Color(uiColor: .systemRed), in: RoundedRectangle(cornerRadius: slot.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: alignment)
        .opacity(slot.content)
    }

    private func closeSwipe() {
        withAnimation(WorkdeskSwipeReveal.settle) {
            swipeOffset = 0
        }
        swipedCardId = nil
        swipeStartOffset = 0
    }

    private func deleteAction(for card: JessResultCard) -> () -> Void {
        let cardId = card.id
        let delete = onDelete
        func deleteCard() {
            if swipedCardId == cardId {
                swipedCardId = nil
                swipeOffset = 0
                swipeStartOffset = 0
            }
            delete(cardId)
        }
        return deleteCard
    }

    private func followFinger(_ value: DragGesture.Value) {
        if dragAxis == .undecided {
            startDrag(value)
        }
        switch dragAxis {
        case .sideways:
            swipeOffset = WorkdeskSwipeReveal.dragOffset(startOffset: swipeStartOffset, translation: value.translation.width, cardWidth: stackWidth)
        case .vertical, .undecided:
            let startScroll = dragStartScroll ?? scroll
            dragStartScroll = startScroll
            scroll = JessWorkdeskLayout.draggedScroll(startScroll: startScroll, translation: value.translation.height, cardCount: cards.count)
        }
    }

    /// Sideways on a card swipes that card; anything else moves the stack.
    private func startDrag(_ value: DragGesture.Value) {
        let isSideways = CardSwipeDelete.isSideways(value.translation)
        let index = JessWorkdeskLayout.cardIndex(atY: value.startLocation.y, scroll: scroll, cardCount: cards.count)
        if isSideways, let index {
            dragAxis = .sideways
            let cardId = cards[index].id
            // The same card again starts from where it rests; another card closes the open one
            swipeStartOffset = cardId == swipedCardId ? swipeOffset : 0
            swipedCardId = cardId
            swipeOffset = swipeStartOffset
            return
        }
        dragAxis = .vertical
        if swipedCardId != nil {
            closeSwipe()
        }
    }

    private func settleOnCard(_ value: DragGesture.Value) {
        let axis = dragAxis
        dragAxis = .undecided
        if axis == .sideways {
            finishSwipe(value)
            return
        }
        let startScroll = dragStartScroll ?? scroll
        dragStartScroll = nil
        let target = JessWorkdeskLayout.settledScroll(startScroll: startScroll, predictedTranslation: value.predictedEndTranslation.height, cardCount: cards.count)
        withAnimation(JessWorkdeskMotion.snap) {
            scroll = target
        }
    }

    /// Rests open with Delete showing, closes, or (swiped most of the way) slides off and leaves
    /// the log.
    private func finishSwipe(_ value: DragGesture.Value) {
        guard let cardId = swipedCardId else {
            return
        }
        let settle = WorkdeskSwipeReveal.settle(startOffset: swipeStartOffset, translation: value.translation.width, predicted: value.predictedEndTranslation.width, cardWidth: stackWidth)
        switch settle {
        case .delete(let direction):
            withAnimation(CardSwipeDelete.slideOut) {
                swipeOffset = direction * CardSwipeDelete.offscreen
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.22))
                onDelete(cardId)
                swipedCardId = nil
                swipeOffset = 0
                swipeStartOffset = 0
            }
        case .open(let offset):
            withAnimation(WorkdeskSwipeReveal.settle) {
                swipeOffset = offset
            }
            swipeStartOffset = offset
        case .closed:
            closeSwipe()
        }
    }

    /// After a delete the stack stays on a card that is still there.
    private func keepScrollOnACard(_ oldCount: Int, _ newCount: Int) {
        let lastCard = Double(max(cards.count - 1, 0))
        guard scroll > lastCard else {
            return
        }
        withAnimation(JessWorkdeskMotion.snap) {
            scroll = lastCard
        }
    }

    /// A new task brings the stack back to the newest.
    private func backToNewest(_ oldId: UUID?, _ newId: UUID?) {
        guard scroll != 0 else {
            return
        }
        withAnimation(JessWorkdeskMotion.snap) {
            scroll = 0
        }
    }
}
