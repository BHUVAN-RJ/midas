import Observation
import SwiftUI

// App built (founder, 2026-10-23, docs/mockups/make-2026-10-23.html, Confirmed):
// - R2: on opening Make, a Built request not yet shown on this phone plays the Built screen over
//   the home grid (the new tile, its name, the plan; no Open), then the tile moves and locks into
//   its slot on the grid: hold 1800 ms, move 760 ms, scale 2 to 1 dipping to 94% as it lands.
// - R3: the Built card in the thread opens the Sidekick, with a small "already built" animation
//   the first time it is seen.

/// R2's timing and path, pure so the tests read every frame.
enum MakeBuiltMotion {
    static let hold = 1.8
    static let move = 0.76
    /// The label under the new tile fades in after the lock.
    static let labelFade = 0.3
    static let tail = 0.5
    /// The tile on the Built screen: 120 pt (twice the grid's 60), its top 230 pt down.
    static let startScale: CGFloat = 2
    static let startTop: CGFloat = 230
    static let dipScale: CGFloat = 0.94
    /// Reduce Motion: the Built screen fades out in place instead.
    static let reducedFade = 0.4

    static var total: Double {
        hold + move + tail
    }

    static func easeInOut(_ amount: Double) -> Double {
        amount < 0.5 ? 4 * amount * amount * amount : 1 - pow(-2 * amount + 2, 3) / 2
    }

    /// 2 → 1 while moving, dipping to 94% as it lands, then back to 100%: the lock.
    static func lockScale(_ progress: Double) -> CGFloat {
        if progress < 0.82 {
            return CGFloat(2 - easeInOut(progress / 0.82) * 1.06)
        }
        let settle = (progress - 0.82) / 0.18
        return dipScale + (1 - dipScale) * CGFloat(sin(settle * .pi / 2))
    }

    struct Frame: Equatable {
        /// The tile's centre, in window points.
        let center: CGPoint
        let scale: CGFloat
        /// The Built screen's paper, name and plan.
        let layerOpacity: Double
        /// The new tile's own label on the grid.
        let labelOpacity: Double
    }

    /// Where everything is `seconds` in. `start` is the Built screen's tile centre, `end` the
    /// grid slot's centre (nil when the grid has no slot for it: the tile fades with the layer).
    static func frame(at seconds: Double, start: CGPoint, end: CGPoint?) -> Frame {
        let moveProgress = max(0, min(1, (seconds - hold) / move))
        let layerOpacity = 1 - min(1, moveProgress / 0.4)
        let labelOpacity = max(0, min(1, (seconds - hold - move) / labelFade))
        guard let end else {
            return Frame(center: start, scale: startScale, layerOpacity: layerOpacity, labelOpacity: labelOpacity)
        }
        let moved = easeInOut(min(1, moveProgress / 0.82))
        let center = CGPoint(x: start.x + (end.x - start.x) * moved, y: start.y + (end.y - start.y) * moved)
        return Frame(center: center, scale: lockScale(moveProgress), layerOpacity: layerOpacity, labelOpacity: labelOpacity)
    }

    static func startCenter(screenWidth: CGFloat, tileSize: CGFloat = SidekickHomeLayout.iconSize) -> CGPoint {
        CGPoint(x: screenWidth / 2, y: startTop + tileSize * startScale / 2)
    }
}

/// What R2 is playing now, and where each home tile sits (the grid reports its frames).
@MainActor
@Observable
final class MakeBuiltStage {
    struct Showing: Equatable {
        let entry: SidekickEntry
        let plan: String
        let startedAt: Date
    }

    private(set) var showing: Showing?
    /// Each tile's frame on the home grid, in window points.
    @ObservationIgnored var slotFrames: [String: CGRect] = [:]

    static func placeholderEntry(sidekickId: String) -> SidekickEntry {
        SidekickEntry(id: sidekickId, name: sidekickId, symbolName: "app", backgroundHex: "#2E2E2E", version: "")
    }

    func play(entry: SidekickEntry, plan: String, now: Date = Date(), reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        let started = now
        showing = Showing(entry: entry, plan: plan, startedAt: started)
        let duration = reduceMotion ? MakeBuiltMotion.hold + MakeBuiltMotion.reducedFade : MakeBuiltMotion.total
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.finish(startedAt: started)
        }
    }

    func finish(startedAt: Date) {
        guard showing?.startedAt == startedAt else {
            return
        }
        showing = nil
    }

    /// The grid keeps the new tile's own slot empty until the moving tile has locked in.
    func hidesTile(_ sidekickId: String, at date: Date = Date()) -> Bool {
        guard let showing, showing.entry.id == sidekickId else {
            return false
        }
        return date.timeIntervalSince(showing.startedAt) < MakeBuiltMotion.hold + MakeBuiltMotion.move
    }

    func recordSlot(_ sidekickId: String, frame: CGRect) {
        slotFrames[sidekickId] = frame
    }
}

/// R2 over the home grid, while the stage plays.
struct MakeBuiltOverlay: View {
    let stage: MakeBuiltStage

    var body: some View {
        if let showing = stage.showing {
            GeometryReader { proxy in
                TimelineView(.animation) { timeline in
                    MakeBuiltScreen(showing: showing, seconds: timeline.date.timeIntervalSince(showing.startedAt), screenWidth: proxy.size.width, slot: stage.slotFrames[showing.entry.id], origin: proxy.frame(in: .global).origin)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }
}

/// One frame of R2.
struct MakeBuiltScreen: View {
    let showing: MakeBuiltStage.Showing
    let seconds: Double
    let screenWidth: CGFloat
    let slot: CGRect?
    /// The overlay's own top-left in window points, to place the tile against the slot.
    let origin: CGPoint

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        let start = MakeBuiltMotion.startCenter(screenWidth: screenWidth)
        let end = slot.map(localCenter)
        let frame = reduceMotion ? reducedFrame(start: start) : MakeBuiltMotion.frame(at: seconds, start: start, end: end)
        let tileOpacity = end == nil || reduceMotion ? frame.layerOpacity : 1
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text(showing.entry.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(tokens.ink.color)
                    .padding(.top, MakeBuiltMotion.startTop + SidekickHomeLayout.iconSize * MakeBuiltMotion.startScale + 16)
                if !showing.plan.isEmpty {
                    Text(showing.plan)
                        .font(.system(size: 17))
                        .foregroundStyle(tokens.ink2.color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 16)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.paper.color)
            .opacity(frame.layerOpacity)
            SidekickIconView(content: SidekickIconContent.content(for: showing.entry), size: SidekickHomeLayout.iconSize)
                .scaleEffect(frame.scale)
                .shadow(color: tokens.shadow.color, radius: 14, y: 12)
                .position(frame.center)
                .opacity(tileOpacity)
        }
        .allowsHitTesting(frame.layerOpacity > 0.5)
        .accessibilityElement(children: .combine)
    }

    private func localCenter(_ slot: CGRect) -> CGPoint {
        CGPoint(x: slot.midX - origin.x, y: slot.midY - origin.y)
    }

    /// Reduce Motion: the Built screen holds, then fades; nothing moves.
    private func reducedFrame(start: CGPoint) -> MakeBuiltMotion.Frame {
        let fade = max(0, min(1, (seconds - MakeBuiltMotion.hold) / MakeBuiltMotion.reducedFade))
        return MakeBuiltMotion.Frame(center: start, scale: MakeBuiltMotion.startScale, layerOpacity: 1 - fade, labelOpacity: fade)
    }
}

/// R3: the Built card in the thread. Opens the Sidekick; the first time it is seen on this phone
/// the tile pops and the check lands (900 ms) and the card's edge flashes (1200 ms).
struct MakeBuiltCard: View {
    let request: MakeRequest
    let center: MakeCenter
    var directory: SidekickDirectory = ShellServices.shared.directory
    let onOpen: () -> Void

    /// When "already built" started playing; nil when it is not playing.
    @State private var seenStartedAt: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        let entry = request.sidekickId.flatMap(directory.entry(withId:)) ?? MakeBuiltStage.placeholderEntry(sidekickId: request.sidekickId ?? "")
        Button(action: onOpen) {
            TimelineView(.animation(paused: seenStartedAt == nil)) { timeline in
                card(entry: entry, tokens: tokens, amount: seenAmount(at: timeline.date))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name)
        .onAppear(perform: firstSeen)
    }

    private func seenAmount(at date: Date) -> CGFloat {
        guard let seenStartedAt else {
            return 1
        }
        return MakeBuiltCardMotion.amount(seconds: date.timeIntervalSince(seenStartedAt))
    }

    private func card(entry: SidekickEntry, tokens: RepairTokens, amount seenAmount: CGFloat) -> some View {
            HStack(spacing: 12) {
                SidekickIconView(content: SidekickIconContent.content(for: entry), size: 56)
                    .scaleEffect(MakeBuiltCardMotion.tileScale(seenAmount))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(tokens.paper.color)
                            .frame(width: 22, height: 22)
                            .background(tokens.ink.color, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(tokens.paper.color, lineWidth: 2)
                            }
                            .scaleEffect(MakeBuiltCardMotion.checkScale(seenAmount))
                            .offset(x: 6, y: -6)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(tokens.ink.color)
                    Text(MakeCopy.builtCardLine)
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.ink2.color)
                }
            }
            .padding(.vertical, 12)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .background(tokens.paper.color, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(tokens.rule.color, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(tokens.ink.color, lineWidth: 2)
                    .opacity(MakeBuiltCardMotion.edgeOpacity(seenAmount))
            }
    }

    /// Plays once per Built card on this phone.
    private func firstSeen() {
        guard !center.threadCardsSeen.contains(request.reqId) else {
            return
        }
        center.threadCardsSeen.insert(request.reqId)
        guard !reduceMotion else {
            return
        }
        let started = Date()
        seenStartedAt = started
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(MakeBuiltCardMotion.edgeDuration))
            if seenStartedAt == started {
                seenStartedAt = nil
            }
        }
    }
}

/// R3's "already built": the tile 86% → 106% → 100%, the check 0 → 120% → 100%, the edge on and off.
enum MakeBuiltCardMotion {
    static let duration = 0.9
    static let edgeDuration = 1.2

    /// How far through, 0...1, eased out like the mockup's cubic-bezier(0.22, 1, 0.36, 1).
    static func amount(seconds: Double) -> CGFloat {
        let linear = max(0, min(1, seconds / duration))
        return CGFloat(1 - pow(1 - linear, 3))
    }

    static func tileScale(_ amount: CGFloat) -> CGFloat {
        if amount < 0.45 {
            return 0.86 + (1.06 - 0.86) * amount / 0.45
        }
        return 1.06 - 0.06 * (amount - 0.45) / 0.55
    }

    static func checkScale(_ amount: CGFloat) -> CGFloat {
        if amount < 0.35 {
            return 0
        }
        if amount < 0.6 {
            return 1.2 * (amount - 0.35) / 0.25
        }
        return 1.2 - 0.2 * (amount - 0.6) / 0.4
    }

    static func edgeOpacity(_ amount: CGFloat) -> Double {
        if amount >= 1 {
            return 0
        }
        if amount < 0.3 {
            return Double(amount / 0.3)
        }
        return Double(1 - (amount - 0.3) / 0.7)
    }
}
