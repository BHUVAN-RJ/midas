import Observation
import SwiftUI
import UIKit

// What frames a repair on a Sidekick's screen (founder, 2026-10-23, mockup section 1): the V1
// Volt rim, on from the three-finger swipe until Send or Cancel; the Repair tag under the island,
// which stays after Send on that Sidekick only; and the Send animation into the tag. Drawn over
// the whole screen, never into the screenshot (the snapshot is the web view alone).

/// The rim's and the Send animation's state for one Sidekick screen.
@MainActor
@Observable
final class RepairChrome {
    enum RimPhase: Equatable {
        case hidden
        /// Following the fingers.
        case tracing
        /// Locked: on for the whole repair.
        case on
        /// Send: draining down both sides.
        case draining
        /// Cancel, or a swipe that let go early.
        case fading
    }

    private(set) var rimPhase: RimPhase = .hidden
    /// How far round the screen the rim has been drawn, 0...1 (trim end).
    private(set) var traceEnd: Double = 0
    /// Where the rim starts, 0...1 (trim start): grows to 1 as it drains on Send.
    private(set) var drainStart: Double = 0
    private(set) var rimOpacity: Double = 0
    /// The swipe locked or a repair layer is up: the tag says "Repair".
    private(set) var repairModeOn = false
    /// True from Cancel until the tag has gone back into the island.
    private(set) var tagRisesOnLeave = false

    /// The circled screenshot on its way into the tag, and when it set off (T1c).
    private(set) var flyingShot: UIImage?
    private(set) var sendStartedAt: Date?
    private(set) var sendStage: RepairSendMotion.Stage?
    private(set) var sendContact = 0.0
    private(set) var sendGone = 0.0
    private(set) var sendReducesMotion = false
    /// Where the tag and the page are, in window points; measured by the overlay.
    var tagFrame: CGRect = .zero
    var pageFrame: CGRect = .zero

    @ObservationIgnored var reduceMotion: @MainActor () -> Bool = RepairChrome.systemReduceMotion

    static func systemReduceMotion() -> Bool {
        UIAccessibility.isReduceMotionEnabled
    }
    @ObservationIgnored var lockHaptic: @MainActor () -> Void = RepairHaptics.lock
    @ObservationIgnored var sendHaptic: @MainActor () -> Void = RepairHaptics.send

    // MARK: The swipe

    func swipeProgressed(_ progress: Double) {
        if progress >= 1 {
            swipeLocked()
            return
        }
        guard rimPhase == .hidden || rimPhase == .tracing || rimPhase == .fading else {
            return
        }
        if progress <= 0 {
            swipeLetGo()
            return
        }
        guard progress >= RepairRimSpec.showFromProgress || rimPhase == .tracing else {
            return
        }
        rimPhase = .tracing
        drainStart = 0
        if reduceMotion() {
            traceEnd = 1
            withAnimation(.easeOut(duration: RepairRimSpec.lockClose)) {
                rimOpacity = progress
            }
        } else {
            rimOpacity = 1
            traceEnd = progress * RepairRimSpec.tracedShare
        }
    }

    /// The swipe fired: the rim closes round the bottom, the tag drops out of the island, a tap
    /// of the phone says it locked.
    func swipeLocked() {
        guard rimPhase != .on else {
            return
        }
        lockHaptic()
        rimPhase = .on
        drainStart = 0
        withAnimation(.easeOut(duration: RepairRimSpec.lockClose)) {
            traceEnd = 1
            rimOpacity = 1
        }
        tagRisesOnLeave = false
        withAnimation(reduceMotion() ? .easeOut(duration: RepairTagSpec.drop) : .easeOut(duration: RepairTagSpec.drop)) {
            repairModeOn = true
        }
    }

    /// Fingers lifted before the swipe was complete, or the page could not be frozen.
    func swipeLetGo() {
        guard rimPhase == .tracing || rimPhase == .on else {
            return
        }
        rimPhase = .fading
        withAnimation(.easeIn(duration: RepairRimSpec.liftEarly)) {
            if reduceMotion() {
                rimOpacity = 0
            } else {
                traceEnd = 0
            }
        }
        tagRisesOnLeave = true
        withAnimation(.easeIn(duration: RepairTagSpec.rise)) {
            repairModeOn = false
        }
        hideRimAfter(RepairRimSpec.liftEarly)
    }

    // MARK: The repair layer

    /// Send or Cancel. Send drains the rim down both sides (360 ms ease-in), Cancel fades it
    /// (200 ms) and sends the tag back into the island.
    func sessionEnded(_ finish: RepairFinish?) {
        if finish == .sent {
            rimPhase = .draining
            tagRisesOnLeave = false
            withAnimation(.easeIn(duration: RepairRimSpec.drain)) {
                if reduceMotion() {
                    rimOpacity = 0
                } else {
                    drainStart = 1
                }
            }
            repairModeOn = false
            hideRimAfter(RepairRimSpec.drain)
            return
        }
        rimPhase = .fading
        withAnimation(.easeIn(duration: RepairRimSpec.cancelFade)) {
            rimOpacity = 0
        }
        tagRisesOnLeave = true
        withAnimation(.easeIn(duration: RepairTagSpec.rise)) {
            repairModeOn = false
        }
        hideRimAfter(RepairRimSpec.cancelFade)
    }

    private func hideRimAfter(_ seconds: Double) {
        let endingPhase = rimPhase
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.rimPhase == endingPhase else {
                return
            }
            self.rimPhase = .hidden
            self.traceEnd = 0
            self.drainStart = 0
            self.rimOpacity = 0
        }
    }

    var isRimShown: Bool {
        rimPhase != .hidden
    }

    // MARK: Send

    /// The Send animation: every Send plays through here (founder's pick, 2026-10-23: T1c
    /// "Quick and quiet", `RepairSendMotion`). The tag stays put; the screenshot shrinks up into
    /// it under its lower edge; the tag swells, then reads "Repairing". The overlay draws each
    /// frame from `sendStartedAt`.
    func playSendAnimation(shot: UIImage, now: Date = Date()) {
        sendHaptic()
        let stage = RepairSendMotion.Stage(page: pageFrame, tag: tagFrame)
        flyingShot = shot
        sendStage = stage
        sendReducesMotion = reduceMotion()
        sendContact = RepairSendMotion.contactSeconds(stage: stage)
        sendGone = RepairSendMotion.goneSeconds(stage: stage)
        sendStartedAt = now
        let duration = sendReducesMotion ? RepairSendMotion.reduceMotionFade : RepairSendMotion.duration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.finishSend(startedAt: now)
        }
    }

    /// The animation is over: the tag is the plain tag again.
    func finishSend(startedAt: Date) {
        guard sendStartedAt == startedAt else {
            return
        }
        flyingShot = nil
        sendStartedAt = nil
        sendStage = nil
    }

    /// How the tag looks at a moment of the Send animation; nil when none is playing.
    func sendTagLook(at date: Date) -> RepairSendMotion.TagLook? {
        guard let sendStartedAt else {
            return nil
        }
        let seconds = date.timeIntervalSince(sendStartedAt)
        return RepairSendMotion.tagLook(at: seconds, contact: sendContact, gone: sendGone, reduceMotion: sendReducesMotion)
    }
}

/// Taps of the phone: on the swipe's lock and on Send (founder defaults, 2026-10-23).
@MainActor
enum RepairHaptics {
    static func lock() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func send() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - The rim

/// One side of the rim: from the top centre, under the island, round the top corner, down the
/// side and round the bottom corner to the bottom centre. Two of them meet at the bottom.
struct RepairRimHalf: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side
    var cornerRadius: CGFloat = RepairRimSpec.screenCornerRadius - RepairRimSpec.inset

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let edgeX = side == .right ? rect.maxX : rect.minX
        let inward: CGFloat = side == .right ? -1 : 1
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: edgeX + inward * radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: edgeX, y: rect.minY + radius), control: CGPoint(x: edgeX, y: rect.minY))
        path.addLine(to: CGPoint(x: edgeX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: edgeX + inward * radius, y: rect.maxY), control: CGPoint(x: edgeX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// V1: 3 pt Volt with its glow; on white over a 6 pt ink line.
struct RepairRimView: View {
    let chrome: RepairChrome
    let isDrawing: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            side(.right)
            side(.left)
        }
        .padding(RepairRimSpec.inset + RepairRimSpec.keylineWidth / 2)
        .opacity(chrome.rimOpacity * (isDrawing ? RepairRimSpec.drawingOpacity : 1))
        .animation(.easeOut(duration: isDrawing ? RepairRimSpec.drawingIn : RepairRimSpec.drawingOut), value: isDrawing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func side(_ side: RepairRimHalf.Side) -> some View {
        let half = RepairRimHalf(side: side).trim(from: chrome.drainStart, to: max(chrome.drainStart, chrome.traceEnd))
        let style = StrokeStyle(lineWidth: RepairRimSpec.lineWidth, lineCap: .round, lineJoin: .round)
        let keylineStyle = StrokeStyle(lineWidth: RepairRimSpec.keylineWidth, lineCap: .round, lineJoin: .round)
        let volt = RepairVolt.color.color
        return ZStack {
            if RepairRimSpec.hasKeyline(for: colorScheme) {
                half.stroke(RepairVolt.ink.color, style: keylineStyle)
            }
            half.stroke(volt, style: style)
                .shadow(color: volt.opacity(RepairRimSpec.glowOpacity(for: colorScheme)), radius: RepairRimSpec.glowRadius)
        }
    }
}

// MARK: - The tag

/// The 20 pt orb in the tag: jess's orb drawn small, with the thinking arc while repairing.
struct RepairMiniOrb: View {
    let spinning: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = JessOrbPalette.forScheme(colorScheme)
        let ring = colorScheme == .dark ? JessOrbColor(hex: 0x3A3A3A) : palette.ring
        TimelineView(.animation(paused: !spinning || reduceMotion)) { timeline in
            ZStack {
                Circle()
                    .fill(palette.body.color)
                Circle()
                    .strokeBorder(ring.color, lineWidth: 1.5)
                Circle()
                    .fill(palette.core.color)
                    .frame(width: RepairTagSpec.orbSize * 0.3, height: RepairTagSpec.orbSize * 0.3)
                if spinning {
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(palette.arc.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(-3)
                        .rotationEffect(.degrees(Self.spinAngle(at: timeline.date, reduceMotion: reduceMotion)))
                }
            }
        }
        .frame(width: RepairTagSpec.orbSize, height: RepairTagSpec.orbSize)
        .accessibilityHidden(true)
    }

    /// One turn every 1.1 s; still with Reduce Motion.
    static func spinAngle(at date: Date, reduceMotion: Bool) -> Double {
        guard !reduceMotion else {
            return 0
        }
        let turns = date.timeIntervalSinceReferenceDate / RepairTagSpec.spinSeconds
        return (turns - turns.rounded(.down)) * 360
    }
}

/// The Volt pill under the island.
struct RepairTagView: View {
    let display: RepairTagDisplay
    var pressed = false
    /// While Send plays: the cross-fade from "Repair", the width and the swell (T1c).
    var sendLook: RepairSendMotion.TagLook?
    let onTap: () -> Void
    let onTryAgain: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let sendLook {
            taking(sendLook)
        } else {
            plain
        }
    }

    /// The tag taking the screenshot in: the same Volt pill, "Repair" fading into the new words.
    private func taking(_ look: RepairSendMotion.TagLook) -> some View {
        ZStack {
            Text(RepairTagCopy.repairMode)
                .opacity(1 - look.labelMix)
            HStack(spacing: 7) {
                RepairMiniOrb(spinning: true)
                Text(display.words)
            }
            .opacity(look.labelMix)
        }
        .font(.system(size: RepairTagSpec.fontSize, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(RepairVolt.ink.color)
        .frame(width: look.width, height: RepairTagSpec.height)
        .background(RepairVolt.color.color, in: Capsule())
        .overlay {
            if colorScheme != .dark {
                Capsule()
                    .strokeBorder(RepairVolt.ink.color, lineWidth: RepairTagSpec.outlineWidth)
            }
        }
        .scaleEffect(x: look.swellX, y: look.swellY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.words)
    }

    private var plain: some View {
        HStack(spacing: 7) {
            if showsOrb {
                RepairMiniOrb(spinning: isRepairing)
            }
            Text(display.words)
                .font(.system(size: RepairTagSpec.fontSize, weight: .semibold))
                .lineLimit(1)
            if display == .couldntFix {
                Button(action: onTryAgain) {
                    Text(RepairTagCopy.tryAgain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RepairVolt.color.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(RepairVolt.ink.color, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(RepairTagCopy.close)
            }
        }
        .foregroundStyle(RepairVolt.ink.color)
        .padding(.leading, showsOrb ? 4 : 12)
        .padding(.trailing, display == .couldntFix ? 6 : 12)
        .frame(minWidth: display == .repairMode ? 74 : nil)
        .frame(height: RepairTagSpec.height)
        .background(RepairVolt.color.color, in: Capsule())
        .overlay {
            if colorScheme != .dark {
                Capsule()
                    .strokeBorder(RepairVolt.ink.color, lineWidth: RepairTagSpec.outlineWidth)
            }
        }
        .scaleEffect(pressed ? SidekickPageUpdateSpec.tagPressScale : 1)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var showsOrb: Bool {
        display != .repairMode
    }

    private var isRepairing: Bool {
        if case .repairing = display {
            return true
        }
        return false
    }
}

/// What a tap on the tag shows: what was sent, or the one-line summary.
struct RepairTagDetail: View {
    let drawing: UIImage?
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        HStack(alignment: .top, spacing: 12) {
            if let drawing {
                Image(uiImage: drawing)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(tokens.ink.color)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(tokens.paper.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(tokens.rule.color, lineWidth: 1)
        }
        .shadow(color: tokens.shadow.color, radius: 15, y: 10)
    }
}

// MARK: - The overlay

/// The rim, the tag and the Send animation over one Sidekick's screen.
struct RepairChromeOverlay: View {
    let chrome: RepairChrome
    let center: RepairCenter
    let sidekickId: String
    let session: RepairSession?
    /// "Repair done. Tap to update" was tapped: the page updates out of the tag.
    let onUpdatePage: (CGPoint) -> Void

    @State private var expanded = false
    @State private var pressed = false
    @State private var lastDisplay: RepairTagDisplay?

    var body: some View {
        ZStack {
            if chrome.isRimShown {
                RepairRimView(chrome: chrome, isDrawing: session?.isDrawing ?? false)
                    .ignoresSafeArea()
            }
            // Under the tag: the screenshot slips in below its lower edge
            if chrome.sendStartedAt != nil {
                TimelineView(.animation) { timeline in
                    flyingShot(at: timeline.date)
                }
                .ignoresSafeArea()
                TimelineView(.animation) { timeline in
                    tagColumn(at: timeline.date)
                }
            } else {
                // Read again every 30 s, so "Taking longer" shows on time
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    tagColumn(at: timeline.date)
                }
            }
        }
    }

    private var display: RepairTagDisplay? {
        center.display(for: sidekickId, repairModeOn: chrome.repairModeOn)
    }

    private func tagColumn(at frameDate: Date) -> some View {
        VStack(spacing: 8) {
            if let display {
                RepairTagView(display: display, pressed: pressed, sendLook: chrome.sendTagLook(at: frameDate), onTap: tapTag, onTryAgain: tryAgain, onClose: close)
                    .onGeometryChange(for: CGRect.self, of: Self.globalFrame, action: recordTagFrame)
                    .transition(tagTransition)
                    .task(id: display, leaveOnItsOwn)
                if expanded, let detail = detailText(for: display) {
                    RepairTagDetail(drawing: detailDrawing(for: display), text: detail)
                        .transition(.opacity)
                        .onTapGesture(perform: collapse)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, RepairTagSpec.topFromSafeArea)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: RepairTagSpec.drop), value: display)
        .onChange(of: display, collapseWhenChanged)
    }

    /// Drops out of the island; leaves back into it on Cancel, fades in place otherwise.
    private var tagTransition: AnyTransition {
        let underTheIsland = AnyTransition.offset(y: -34).combined(with: .scale(scale: 0.6, anchor: .top)).combined(with: .opacity)
        let removal = chrome.tagRisesOnLeave ? underTheIsland : .opacity
        if UIAccessibility.isReduceMotionEnabled {
            return .opacity
        }
        return .asymmetric(insertion: underTheIsland, removal: removal)
    }

    /// T1c: the screenshot shrinking up into the tag, cut off at the tag's lower edge once it
    /// fits, so it is never drawn over the tag. Reduce Motion: it fades where it is.
    @ViewBuilder
    private func flyingShot(at date: Date) -> some View {
        if let shot = chrome.flyingShot, let stage = chrome.sendStage, let startedAt = chrome.sendStartedAt, stage.page.width > 0 {
            let seconds = date.timeIntervalSince(startedAt)
            if chrome.sendReducesMotion {
                Image(uiImage: shot)
                    .resizable()
                    .frame(width: stage.page.width, height: stage.page.height)
                    .position(x: stage.page.midX, y: stage.page.midY)
                    .opacity(RepairSendMotion.reducedShotOpacity(at: seconds))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if seconds < chrome.sendGone {
                let box = RepairSendMotion.box(at: seconds, stage: stage)
                let clipTop = RepairSendMotion.clipTop(box, stage: stage) ?? 0
                Image(uiImage: shot)
                    .resizable()
                    .frame(width: stage.page.width, height: stage.page.height)
                    .clipShape(RoundedRectangle(cornerRadius: box.cornerRadius))
                    .shadow(color: box.scale > 0.2 ? Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.3) : .clear, radius: 15, y: 10)
                    .scaleEffect(box.scale)
                    .position(box.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(alignment: .top) {
                        Rectangle()
                            .padding(.top, clipTop)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    nonisolated private static func globalFrame(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .global)
    }

    private func recordTagFrame(_ frame: CGRect) {
        chrome.tagFrame = frame
    }

    private func detailText(for display: RepairTagDisplay) -> String? {
        if case .repairing = display {
            return center.latestPending(for: sidekickId)?.transcript
        }
        return display.summary
    }

    private func detailDrawing(for display: RepairTagDisplay) -> UIImage? {
        guard case .repairing = display, let pending = center.latestPending(for: sidekickId) else {
            return nil
        }
        return center.sentDrawing(clientReportId: pending.clientReportId)
    }

    private func tapTag() {
        guard let display else {
            return
        }
        if case .fixed(let onPage, _) = display, onPage {
            pressAndUpdate()
            return
        }
        guard detailText(for: display) != nil else {
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            expanded.toggle()
        }
    }

    private func collapse() {
        withAnimation(.easeIn(duration: 0.2)) {
            expanded = false
        }
    }

    private func collapseWhenChanged(_ oldDisplay: RepairTagDisplay?, _ newDisplay: RepairTagDisplay?) {
        expanded = false
    }

    /// U4: the tag presses to 94% for 120 ms, then the page grows out of it and the tag goes away.
    private func pressAndUpdate() {
        let tagCenter = CGPoint(x: chrome.tagFrame.midX, y: chrome.tagFrame.midY)
        withAnimation(.easeOut(duration: SidekickPageUpdateSpec.tagPress)) {
            pressed = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(SidekickPageUpdateSpec.tagPress))
            onUpdatePage(tagCenter)
            withAnimation(.easeIn(duration: 0.2)) {
                putAwayShownOutcome()
            }
            pressed = false
        }
    }

    private func tryAgain() {
        guard let outcome = center.shownOutcome(for: sidekickId) else {
            return
        }
        Task { @MainActor in
            await center.tryAgain(clientReportId: outcome.clientReportId)
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: RepairTagSpec.leaveFade)) {
            putAwayShownOutcome()
        }
    }

    private func putAwayShownOutcome() {
        guard let outcome = center.shownOutcome(for: sidekickId) else {
            return
        }
        center.putAway(clientReportId: outcome.clientReportId)
    }

    /// Already There leaves 2.4 s after it shows, "Fixed" (landed while away) after 1 s (fade
    /// 400 ms in place), unless the user opened the summary.
    private func leaveOnItsOwn() async {
        guard let display, let seconds = display.leavesAfterSeconds else {
            return
        }
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled, !expanded, self.display == display else {
            return
        }
        withAnimation(.easeIn(duration: RepairTagSpec.leaveFade)) {
            putAwayShownOutcome()
        }
    }
}
