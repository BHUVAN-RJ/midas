import Observation
import SwiftUI
import UIKit

/// B3, the floating pill (founder, 2026-10-23, docs/mockups/repair-feedback-2026-10-23.html),
/// shared by repair and Make (contract section 8): jess's orb in the left slot, one text area for
/// the spoken words then the typed words (`RepairPillTextView`), the round send arrow on the right.
/// 8 pt from the pill's edge to the orb and the arrow, 10 pt to the words; 60 pt tall for one line,
/// growing to three. Every number is `RepairPillSpec`'s, so repair keeps its look exactly.
struct PillBar<Orb: View>: View {
    /// The spoken words, already coloured: settled words in ink, the newest word grey while jess
    /// may still change it (`PillBarWords.spokenWords`). Nil: coloured here from `settled` and
    /// `pending`.
    let spoken: NSAttributedString?
    var settled = ""
    var pending = ""
    @Binding var typed: String
    @Binding var isTyping: Bool
    /// Shown when there are no words, spoken or typed.
    let placeholder: String
    /// False while repair's orb is still on its way into the slot (O4).
    var showsOrb = true
    /// A tap on the orb (Make: listen or stop listening); nil when the orb is not a button.
    var onOrbTap: (() -> Void)?
    let canSend: Bool
    var sendLabel: String = RepairCopy.sendButton
    let onSend: () -> Void
    /// Measured frames in window points, for O4's orb drop and for tests.
    var onSlotLayout: ((CGRect) -> Void)?
    var onSendLayout: ((CGRect) -> Void)?
    var onPillLayout: ((CGRect) -> Void)?
    /// jess's orb, as the caller drives it (repair: the session's; Make: the composer's).
    let orb: () -> Orb

    /// Repair's pill: its own coloured words and its own orb.
    init(spoken: NSAttributedString, typed: Binding<String>, isTyping: Binding<Bool>, placeholder: String, showsOrb: Bool = true, onOrbTap: (() -> Void)? = nil, canSend: Bool, sendLabel: String = RepairCopy.sendButton, onSend: @escaping () -> Void, onSlotLayout: ((CGRect) -> Void)? = nil, onSendLayout: ((CGRect) -> Void)? = nil, onPillLayout: ((CGRect) -> Void)? = nil, @ViewBuilder orb: @escaping () -> Orb) {
        self.spoken = spoken
        self._typed = typed
        self._isTyping = isTyping
        self.placeholder = placeholder
        self.showsOrb = showsOrb
        self.onOrbTap = onOrbTap
        self.canSend = canSend
        self.sendLabel = sendLabel
        self.onSend = onSend
        self.onSlotLayout = onSlotLayout
        self.onSendLayout = onSendLayout
        self.onPillLayout = onPillLayout
        self.orb = orb
    }

    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        HStack(spacing: RepairPillSpec.spacing) {
            orbSlot
            words
            sendButton
                .onGeometryChange(for: CGRect.self, of: Self.frameInWindow, action: reportSend)
        }
        .padding(RepairPillSpec.innerPadding)
        .frame(minHeight: RepairPillSpec.height)
        .background(tokens.paper.color, in: RoundedRectangle(cornerRadius: RepairPillSpec.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RepairPillSpec.cornerRadius)
                .strokeBorder(isTyping ? tokens.ink.color : tokens.rule.color, lineWidth: isTyping ? RepairPillSpec.focusRingWidth : 1)
        }
        .shadow(color: tokens.shadow.color, radius: 15, y: 10)
        .onGeometryChange(for: CGRect.self, of: Self.frameInWindow, action: reportPill)
    }

    nonisolated static func frameInWindow(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .global)
    }

    private func reportSend(_ frame: CGRect) {
        onSendLayout?(frame)
    }

    private func reportPill(_ frame: CGRect) {
        onPillLayout?(frame)
    }

    private func reportSlot(_ frame: CGRect) {
        onSlotLayout?(frame)
    }

    // MARK: Parts

    private var orbSlot: some View {
        ZStack {
            if showsOrb {
                orbButton
                    .transition(.opacity)
            }
        }
        .frame(width: RepairPillSpec.slotSize, height: RepairPillSpec.slotSize)
        .onGeometryChange(for: CGRect.self, of: Self.frameInWindow, action: reportSlot)
    }

    @ViewBuilder
    private var orbButton: some View {
        if let onOrbTap {
            Button(action: onOrbTap) {
                orb()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PillBarCopy.talkLabel)
        } else {
            orb()
        }
    }

    /// Centred on the orb's line while there is one line; grows to three, then scrolls.
    private var words: some View {
        RepairPillTextView(
            spoken: spokenText,
            typed: $typed,
            isTyping: $isTyping,
            font: UIFont.systemFont(ofSize: RepairPillSpec.fontSize),
            ink: tokens.ink.uiColor,
            maxLines: RepairPillText.maxSpokenLines
        )
        .overlay(alignment: .leading) {
            placeholderText
        }
        .frame(maxWidth: .infinity, minHeight: RepairPillSpec.slotSize, alignment: .leading)
    }

    @ViewBuilder
    private var placeholderText: some View {
        if spokenText.length == 0 && typed.isEmpty && !placeholder.isEmpty {
            Text(placeholder)
                .font(.system(size: RepairPillSpec.fontSize))
                .foregroundStyle(tokens.ink3.color)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var spokenText: NSAttributedString {
        spoken ?? PillBarWords.spokenWords(settled: settled, pending: pending, ink: tokens.ink.uiColor, pendingInk: tokens.ink2.uiColor)
    }

    /// A round up arrow: ink with a paper arrow, greyed until there is a word. No recording dot:
    /// the orb shows that jess is listening.
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(canSend ? tokens.paper.color : tokens.ink3.color)
                .frame(width: RepairPillSpec.sendSize, height: RepairPillSpec.sendSize)
                .background(canSend ? tokens.ink.color : tokens.paper2.color, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel(sendLabel)
    }
}

extension PillBar where Orb == JessOrb {
    /// Make's pill: the words as settled and pending, jess's orb in the given state; a tap on the
    /// orb listens or stops.
    init(settled: String, pending: String, typed: Binding<String>, isTyping: Binding<Bool>, placeholder: String, orbState: JessOrbState, orbLevel: @escaping @Sendable () -> Double = JessOrb.silence, onOrbTap: (() -> Void)? = nil, canSend: Bool, sendLabel: String = RepairCopy.sendButton, onSend: @escaping () -> Void, onPillLayout: ((CGRect) -> Void)? = nil) {
        func jessOrb() -> JessOrb {
            JessOrb(state: orbState, level: orbLevel)
        }
        self.spoken = nil
        self.settled = settled
        self.pending = pending
        self._typed = typed
        self._isTyping = isTyping
        self.placeholder = placeholder
        self.onOrbTap = onOrbTap
        self.canSend = canSend
        self.sendLabel = sendLabel
        self.onSend = onSend
        self.onPillLayout = onPillLayout
        self.orb = jessOrb
    }
}

enum PillBarCopy {
    static let talkLabel = "Talk"
}

/// The pill's spoken words coloured as repair colours them.
enum PillBarWords {
    /// Settled words in ink, the newest word grey while jess may still change it.
    static func spokenWords(settled: String, pending: String, ink: UIColor, pendingInk: UIColor) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: RepairPillSpec.fontSize)
        let spoken = NSMutableAttributedString(string: settled, attributes: [.font: font, .foregroundColor: ink])
        guard !pending.isEmpty else {
            return spoken
        }
        let separator = settled.isEmpty ? "" : " "
        let pendingText = NSAttributedString(string: separator + pending, attributes: [.font: font, .foregroundColor: pendingInk])
        spoken.append(pendingText)
        return spoken
    }
}

/// The words behind a Make pill (contract section 8): jess listens (the thread starts listening on
/// open), the words show live, tapping the words to type stops listening, and Send takes the words
/// and empties the pill. Speech is turned into text on the phone; no audio is kept (founder,
/// 2026-10-23).
@MainActor
@Observable
final class PillVoiceComposer {
    var typed = ""
    /// The keyboard is up. Setting it stops listening (tap to type stops listening).
    var isTyping = false {
        didSet {
            if isTyping && !oldValue {
                stopListening()
            }
        }
    }
    private(set) var isListening = false
    private(set) var transcript: RepairTranscript = .empty
    /// Words of listens that already ended; a new listen's words follow them.
    private var earlierTranscript: RepairTranscript = .empty
    /// Bumped by every listen, so words or an end from an older listen are dropped.
    private var listenGeneration = 0
    private var startedAt = Date()
    @ObservationIgnored private let makeTranscriber: @MainActor () -> RepairTranscribing
    @ObservationIgnored private var transcriber: RepairTranscribing?

    init(makeTranscriber: @escaping @MainActor () -> RepairTranscribing = PillVoiceComposer.onDeviceTranscriber) {
        self.makeTranscriber = makeTranscriber
    }

    static func onDeviceTranscriber() -> RepairTranscribing {
        OnDeviceSpeechTranscriber(options: .repair)
    }

    /// The spoken words then the typed words, as one message, joined the way the pill shows them
    /// (one space; repair's report keeps them in two paragraphs instead).
    var words: String {
        let parts = [transcript.text, typed].map(MakeWriter.trimmed)
        let said = parts.filter(Self.hasWords)
        return said.joined(separator: " ")
    }

    private static func hasWords(_ text: String) -> Bool {
        !text.isEmpty
    }

    var canSend: Bool {
        !MakeWriter.trimmed(words).isEmpty
    }

    /// Settled words and the newest word for the pill.
    var pillText: RepairPillText {
        RepairPillText(spoken: transcript.text, typed: typed, isListening: isListening, isTyping: isTyping)
    }

    var orbState: JessOrbState {
        isListening && !isTyping ? .listening : .idle
    }

    var orbLevel: @Sendable () -> Double {
        guard let meter = transcriber?.audioLevelMeter, isListening else {
            return JessOrb.silence
        }
        return RepairSession.levelReader(for: meter)
    }

    /// Listens if Midas has the microphone and speech recognition (asked at launch); otherwise the
    /// person types.
    func startListening() async {
        guard !isListening, !isTyping else {
            return
        }
        listenGeneration += 1
        let generation = listenGeneration
        let transcriber = self.transcriber ?? makeTranscriber()
        self.transcriber = transcriber
        if listenGeneration == 1 {
            startedAt = Date()
        }
        func hear(_ newTranscript: RepairTranscript) {
            receive(newTranscript, generation: generation)
        }
        func ended(_ reason: VoiceTranscriptionEnd) {
            listeningEnded(generation: generation)
        }
        do {
            try await transcriber.start(sessionStartedAt: startedAt, onUpdate: hear, onEnd: ended)
            guard generation == listenGeneration else {
                return
            }
            isListening = true
        } catch {
            isListening = false
        }
    }

    func stopListening() {
        guard isListening else {
            return
        }
        listenGeneration += 1
        transcriber?.stop()
        isListening = false
        earlierTranscript = transcript
    }

    /// The orb as a button: listen, or stop.
    func toggleListening() {
        if isListening {
            stopListening()
            return
        }
        isTyping = false
        Task { @MainActor in
            await self.startListening()
        }
    }

    /// Send: the words, and an empty pill. Listening carries on if it was on, for the next words.
    func take() -> String? {
        let taken = MakeWriter.trimmed(words)
        guard !taken.isEmpty else {
            return nil
        }
        let wasListening = isListening
        stopListening()
        typed = ""
        transcript = .empty
        earlierTranscript = .empty
        if wasListening {
            Task { @MainActor in
                await self.startListening()
            }
        }
        return taken
    }

    private func receive(_ newTranscript: RepairTranscript, generation: Int) {
        guard generation == listenGeneration else {
            return
        }
        transcript = RepairListening.joined(earlierTranscript, newTranscript)
    }

    private func listeningEnded(generation: Int) {
        guard generation == listenGeneration, isListening else {
            return
        }
        isListening = false
        earlierTranscript = transcript
    }
}
