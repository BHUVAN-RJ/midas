import SwiftUI
import UIKit

/// The repair layer over a frozen Sidekick (founder layout 2026-10-13, restyled 2026-10-23 with O4
/// and B3, docs/mockups/repair-feedback-2026-10-23.html):
///
///   ✕                              ← Cancel, top left
///   frozen Sidekick, strokes in Volt (ink line under them in light mode)
///                     [Undo] [Clear]  ← small pills
///   ( ◉  What to fix             ↑ )  ← the floating pill: jess's orb, the words (spoken live,
///                                        then typed), Send
///
/// The V1 rim and the Repair tag are drawn over the whole screen by `RepairChromeOverlay`, not
/// here: they stay after this layer is gone.
///
/// Two layers, attached separately by `repairLayer` (first phone test, 2026-10-14: one stack
/// sized by the safe area overflowed, slid under the status bar and hid under the keyboard):
/// - `RepairFrozenView` takes the web view's own frame, so the frozen Sidekick sits pixel-exact on
///   the web view it replaced and never moves;
/// - `RepairControlsView` takes the safe frame, which the home indicator and the keyboard shrink,
///   so Cancel stays visible and the pill floats over the bottom edge and rises with the keyboard.
/// Colours come from `RepairTokens` per mode; nothing here assumes light mode.
struct RepairFrozenView: View {
    let session: RepairSession
    /// Measured frames, for tests; nil in the app.
    var onLayout: ((RepairLayerPart, CGRect) -> Void)?

    var body: some View {
        ZStack {
            Image(uiImage: session.snapshot)
                .resizable()
            RepairStrokesCanvas(strokes: session.allStrokes)
                .gesture(drawGesture)
        }
        .frame(width: session.viewSize.width, height: session.viewSize.height)
        .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordSnapshot)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func recordSnapshot(_ frame: CGRect) {
        onLayout?(.snapshot, frame)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        // Drawing puts the keyboard away; the text box lives in the other layer
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        session.extendStroke(to: value.location)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        session.endStroke()
    }
}

/// Cancel, the floating pill and its small pills. Lets touches through everywhere else to the
/// frozen Sidekick below, where the user draws.
struct RepairControlsView: View {
    @Bindable var session: RepairSession
    var onLayout: ((RepairLayerPart, CGRect) -> Void)?
    /// The pill's frame in window points, for tests; nil in the app.
    var onPillLayout: ((CGRect) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The keyboard is up for the pill's text area (`RepairPillTextView` keeps the two in step).
    @State private var isTyping = false
    @State private var entrance = RepairEntrance.Phase.docked
    @State private var slotCenter: CGPoint = .zero
    @State private var controlsOrigin: CGPoint = .zero

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                cancelButton
                    .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordCancel)
                Spacer()
            }
            Spacer()
            bottomBar
                .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordBar)
                .offset(y: entrance == .popping ? RepairEntrance.riseDistance : 0)
                .opacity(reduceMotion && entrance == .popping ? 0 : 1)
        }
        .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordControls)
        .overlay(alignment: .topLeading) {
            floatingOrb
        }
        .task {
            await session.startListening()
        }
        .task {
            await playEntrance()
        }
    }

    private func recordCancel(_ frame: CGRect) {
        onLayout?(.cancel, frame)
    }

    private func recordBar(_ frame: CGRect) {
        onLayout?(.bottomBar, frame)
    }

    private func recordSend(_ frame: CGRect) {
        onLayout?(.send, frame)
    }

    private func recordControls(_ frame: CGRect) {
        controlsOrigin = frame.origin
    }

    private func recordSlot(_ frame: CGRect) {
        slotCenter = CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: O4: the orb pops where the fingers lifted and drops into the pill

    /// Only a layer opened by the swipe knows where the fingers lifted; any other opens with the
    /// orb already in the pill.
    private func playEntrance() async {
        guard session.liftPoint != nil else {
            return
        }
        entrance = .popping
        if reduceMotion {
            withAnimation(.easeOut(duration: RepairPillSpec.rise)) {
                entrance = .docked
            }
            return
        }
        withAnimation(.easeOut(duration: RepairPillSpec.rise).delay(RepairPillSpec.riseDelay)) {
            entrance = .rising
        }
        try? await Task.sleep(for: .seconds(RepairPillSpec.popGrow + RepairPillSpec.popSettle))
        withAnimation(.easeInOut(duration: RepairPillSpec.dock)) {
            entrance = .moving
        }
        try? await Task.sleep(for: .seconds(RepairPillSpec.dock))
        // Handed over: the pill's own orb takes its place
        entrance = .docked
    }

    @ViewBuilder
    private var floatingOrb: some View {
        if let liftPoint = session.liftPoint, !RepairEntrance.isSettled(entrance) {
            let target = entrance == .moving ? slotCenter : liftPoint
            let size = entrance == .moving ? RepairPillSpec.slotSize : RepairPillSpec.popSize
            JessOrb(state: orbState, level: session.orbLevel)
                .frame(width: size, height: size)
                .modifier(RepairOrbPop(popping: entrance == .popping))
                .position(x: target.x - controlsOrigin.x, y: target.y - controlsOrigin.y)
                .allowsHitTesting(false)
        }
    }

    /// Listening: Volt core with the voice; typing or no microphone: still ink core.
    private var orbState: JessOrbState {
        session.isListening && !isTyping ? .listening : .idle
    }

    // MARK: Parts

    private var cancelButton: some View {
        Button(action: session.cancel) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.ink.color)
                .frame(width: 40, height: 40)
                .background(tokens.paper.color, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(tokens.rule.color, lineWidth: 1)
                }
                .shadow(color: tokens.shadow.color, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RepairCopy.cancelLabel)
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    /// B3: small Undo and Clear pills above the right end, then the pill. The top padding keeps
    /// the small pills' shadow inside the bar.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Spacer()
                miniPill(RepairCopy.undoButton, action: session.undo)
                miniPill(RepairCopy.clearButton, action: session.clear)
            }
            pill
        }
        .padding(.horizontal, RepairPillSpec.sideMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func miniPill(_ title: String, action: @escaping () -> Void) -> some View {
        let isOff = session.strokes.isEmpty
        return Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOff ? tokens.ink3.color : tokens.ink.color)
                .padding(.horizontal, 14)
                .frame(height: RepairPillSpec.miniPillHeight)
                .background(tokens.paper.color, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(tokens.rule.color, lineWidth: 1)
                }
                .shadow(color: tokens.shadow.color, radius: 7, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isOff)
    }

    /// The orb on the left, the words centred on the orb's line, the round send arrow on the
    /// right: 8 pt from the pill's edge to the orb and to the arrow, 10 pt to the words.
    private var pill: some View {
        HStack(spacing: RepairPillSpec.spacing) {
            orbSlot
            words
            sendButton
                .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordSend)
        }
        .padding(RepairPillSpec.innerPadding)
        .frame(minHeight: RepairPillSpec.height)
        .background(tokens.paper.color, in: RoundedRectangle(cornerRadius: RepairPillSpec.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RepairPillSpec.cornerRadius)
                .strokeBorder(isTyping ? tokens.ink.color : tokens.rule.color, lineWidth: isTyping ? RepairPillSpec.focusRingWidth : 1)
        }
        .shadow(color: tokens.shadow.color, radius: 15, y: 10)
        .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordPill)
    }

    private func recordPill(_ frame: CGRect) {
        onPillLayout?(frame)
    }

    /// One text area (`RepairPillTextView`): the spoken words, live, and the typed words carrying
    /// on after them. Centred on the orb's line while there is one line; grows to three. "What to
    /// fix" only when there is neither (`RepairPillText`).
    private var words: some View {
        let text = session.pillText(isTyping: isTyping)
        return RepairPillTextView(
            spoken: spokenWords(text),
            typed: $session.typedText,
            isTyping: $isTyping,
            font: UIFont.systemFont(ofSize: RepairPillSpec.fontSize),
            ink: tokens.ink.uiColor,
            maxLines: RepairPillText.maxSpokenLines
        )
        .overlay(alignment: .leading) {
            placeholder(text)
        }
        .frame(maxWidth: .infinity, minHeight: RepairPillSpec.slotSize, alignment: .leading)
    }

    @ViewBuilder
    private func placeholder(_ text: RepairPillText) -> some View {
        if !text.placeholder.isEmpty && session.typedText.isEmpty {
            Text(text.placeholder)
                .font(.system(size: RepairPillSpec.fontSize))
                .foregroundStyle(tokens.ink3.color)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Settled words in ink, the newest word grey while jess may still change it.
    private func spokenWords(_ text: RepairPillText) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: RepairPillSpec.fontSize)
        let spoken = NSMutableAttributedString(string: text.settled, attributes: [.font: font, .foregroundColor: tokens.ink.uiColor])
        guard !text.pending.isEmpty else {
            return spoken
        }
        let separator = text.settled.isEmpty ? "" : " "
        let pending = NSAttributedString(string: separator + text.pending, attributes: [.font: font, .foregroundColor: tokens.ink2.uiColor])
        spoken.append(pending)
        return spoken
    }

    private var orbSlot: some View {
        ZStack {
            if RepairEntrance.isSettled(entrance) || session.liftPoint == nil {
                JessOrb(state: orbState, level: session.orbLevel)
                    .transition(.opacity)
            }
        }
        .frame(width: RepairPillSpec.slotSize, height: RepairPillSpec.slotSize)
        .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordSlot)
    }

    /// A round up arrow: ink with a paper arrow, greyed until there is a word. No recording dot:
    /// the orb shows that jess is listening.
    private var sendButton: some View {
        let isOn = session.canSend
        return Button(action: session.send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isOn ? tokens.paper.color : tokens.ink3.color)
                .frame(width: RepairPillSpec.sendSize, height: RepairPillSpec.sendSize)
                .background(isOn ? tokens.ink.color : tokens.paper2.color, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn)
        .accessibilityLabel(RepairCopy.sendButton)
    }
}

/// O4's steps.
enum RepairEntrance {
    enum Phase: Equatable {
        /// The orb grows at the lift point; the pill is still below the screen.
        case popping
        /// The pill rises; the orb is full size at the lift point.
        case rising
        /// The orb drops into the pill's slot.
        case moving
        /// The pill's own orb sits in the slot.
        case docked
    }

    static let riseDistance: CGFloat = 140

    static func isSettled(_ phase: Phase) -> Bool {
        phase == .docked
    }
}

/// The pop: 0 → 106% in 240 ms ease-out, then → 100% in 160 ms.
private struct RepairOrbPop: ViewModifier {
    let popping: Bool
    @State private var scale: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .task {
                withAnimation(.easeOut(duration: RepairPillSpec.popGrow)) {
                    scale = 1.06
                }
                try? await Task.sleep(for: .seconds(RepairPillSpec.popGrow))
                withAnimation(.easeOut(duration: RepairPillSpec.popSettle)) {
                    scale = 1
                }
            }
    }
}

/// The parts of the repair layer a test measures.
enum RepairLayerPart: Equatable, Sendable {
    case snapshot
    case cancel
    case bottomBar
    case send

    /// In window coordinates, so a test can compare them with the web view's frame.
    nonisolated static func frameInWindow(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .global)
    }
}

extension View {
    /// A Sidekick's web view, full screen to the bottom edge, with the repair layer over it while a
    /// repair is open. Overlays, not a cover, so the freeze is instant. The frozen layer goes inside
    /// `ignoresSafeArea` to take the web view's own frame; the controls go outside it to take the
    /// safe frame, which the keyboard shrinks.
    func repairLayer(_ session: RepairSession?, onLayout: ((RepairLayerPart, CGRect) -> Void)? = nil, onPillLayout: ((CGRect) -> Void)? = nil) -> some View {
        overlay {
            if let session {
                // The live page is back at once on Send or Cancel; the shot flies from the overlay
                RepairFrozenView(session: session, onLayout: onLayout)
                    .transition(.identity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay {
            if let session {
                // On Send the pill drops (the host animates the removal)
                RepairControlsView(session: session, onLayout: onLayout, onPillLayout: onPillLayout)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

/// The strokes, drawn live; nothing else, so the frozen Sidekick shows through. Volt, over an
/// 8 pt ink line in light mode (V1).
struct RepairStrokesCanvas: View {
    let strokes: [RepairStroke]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(rendersAsynchronously: false, renderer: drawStrokes)
    }

    private func drawStrokes(context: inout GraphicsContext, size: CGSize) {
        let paths = strokes.map(path(for:))
        if RepairRimSpec.hasKeyline(for: colorScheme) {
            let keylineStyle = StrokeStyle(lineWidth: RepairPen.keylineWidth, lineCap: .round, lineJoin: .round)
            for strokePath in paths {
                context.stroke(strokePath, with: .color(RepairPen.keylineColor), style: keylineStyle)
            }
        }
        let style = StrokeStyle(lineWidth: RepairPen.lineWidth, lineCap: .round, lineJoin: .round)
        for strokePath in paths {
            context.stroke(strokePath, with: .color(RepairPen.color), style: style)
        }
    }

    private func path(for stroke: RepairStroke) -> Path {
        var path = Path()
        let points = stroke.points.filter(hasCoordinates).map(cgPoint)
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
        }
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func hasCoordinates(_ array: [Double]) -> Bool {
        array.count >= 2
    }

    private func cgPoint(_ array: [Double]) -> CGPoint {
        CGPoint(x: array[0], y: array[1])
    }
}
