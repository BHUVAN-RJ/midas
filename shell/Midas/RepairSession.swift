import Foundation
import Observation
import SwiftUI
import WebKit

/// Words on the repair layer (docs/WRITING.md; founder approved the layout 2026-10-13).
enum RepairCopy {
    static let cancelLabel = "Cancel"
    static let undoButton = "Undo"
    static let clearButton = "Clear"
    static let sendButton = "Send"
    static let textPlaceholder = "What to fix"
}

/// The pen follows V1 (founder, 2026-10-23: tomato left Midas's colours): 5 pt Volt, and in light
/// mode over an 8 pt ink line so it shows on white (docs/DESIGN.md 2.2).
enum RepairPen {
    static let colorHex = RepairVolt.hex
    static let uiColor = RepairVolt.color.uiColor
    static let color = Color(uiColor: uiColor)
    static let lineWidth: CGFloat = RepairDrawingRenderer.lineWidth
    static let keylineUIColor = RepairVolt.ink.uiColor
    static let keylineColor = Color(uiColor: keylineUIColor)
    static let keylineWidth: CGFloat = 8

    /// The ink line goes under the Volt in light mode only.
    static func keyline(for style: UIUserInterfaceStyle) -> UIColor? {
        style == .dark ? nil : keylineUIColor
    }
}

/// How a repair layer ended, so the rim and the tag can leave the right way.
enum RepairFinish: Equatable, Sendable {
    case sent
    case cancelled
}

/// One repair from the three-finger swipe to Send or Cancel: the frozen Sidekick, the strokes, the words
/// heard and typed. Every time is on one clock, zero at the moment the swipe fired.
@MainActor
@Observable
final class RepairSession: Identifiable {
    let id = UUID().uuidString
    let sidekickId: String
    let snapshot: UIImage
    let viewSize: CGSize
    let startedAt: Date

    private(set) var strokes: [RepairStroke] = []
    private(set) var activeStroke: RepairStroke?
    var typedText = ""
    private(set) var transcript: RepairTranscript = .empty
    private(set) var isListening = false
    /// What went wrong with voice in this session, oldest first: why listening would not start,
    /// iOS's recogniser errors, and "no words" with the microphone's buffer count. Sent with the
    /// report (`voiceError`) so the next phone test says why voice failed.
    private(set) var voiceProblems: [String] = []

    /// Words from listens that already ended; a new listen's words follow them.
    private var earlierTranscript: RepairTranscript = .empty
    /// Bumped by every listen, so an end or words from an older one are dropped.
    private var listenGeneration = 0
    private var listenStartedAt: Date?
    /// Listening again after it ended by itself: once. A listen that lasted `RepairListening.healthyListen`
    /// before ending earns the retry back, so the recogniser's own time-outs while the user draws
    /// never leave the layer deaf.
    private var retriesLeft = RepairListening.retries

    private let transcriber: RepairTranscribing
    private let uploader: RepairUploader
    private let bundleVersions: SidekickBundleVersions
    /// Set by the host view; dismisses the layer.
    var onFinish: (() -> Void)?
    /// Set by the host view; the sent report and the circled screenshot, for the Repair tag.
    var onSent: ((RepairReport, UIImage) -> Void)?
    /// How the layer ended; nil while it is open.
    private(set) var finish: RepairFinish?
    /// Where the fingers lifted, in window points: jess's orb pops there (O4). Nil when the layer
    /// was opened another way; the orb then starts in the pill.
    var liftPoint: CGPoint?
    /// Light or dark when the swipe fired: the pen's ink line is drawn in light mode only.
    var interfaceStyle: UIUserInterfaceStyle = .light

    init(sidekickId: String, snapshot: UIImage, viewSize: CGSize, transcriber: RepairTranscribing, uploader: RepairUploader, bundleVersions: SidekickBundleVersions = .shared, startedAt: Date = Date()) {
        self.sidekickId = sidekickId
        self.snapshot = snapshot
        self.viewSize = viewSize
        self.transcriber = transcriber
        self.uploader = uploader
        self.bundleVersions = bundleVersions
        self.startedAt = startedAt
    }

    /// Freezes the web view: a snapshot at its exact size, no chrome, so the Sidekick looks
    /// stopped rather than photographed. Nil if WebKit could not snapshot.
    static func begin(sidekickId: String, webView: WKWebView, transcriber: RepairTranscribing, uploader: RepairUploader) async -> RepairSession? {
        let startedAt = Date()
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = false
        guard let snapshot = try? await webView.takeSnapshot(configuration: configuration) else {
            return nil
        }
        let session = RepairSession(sidekickId: sidekickId, snapshot: snapshot, viewSize: webView.bounds.size, transcriber: transcriber, uploader: uploader, startedAt: startedAt)
        session.interfaceStyle = webView.traitCollection.userInterfaceStyle
        return session
    }

    /// Send lights up once there is a word, spoken or typed; the server rejects an empty transcript.
    var canSend: Bool {
        let combined = RepairReportBuilder.combinedTranscript(spokenText: transcript.text, typedText: typedText)
        return !combined.isEmpty
    }

    var allStrokes: [RepairStroke] {
        if let activeStroke {
            return strokes + [activeStroke]
        }
        return strokes
    }

    // MARK: Listening

    /// Listens if Midas was given the microphone and speech recognition at launch
    /// (`VoicePermissions`, founder 2026-10-15). The layer never asks.
    func startListening() async {
        guard !isListening, finish == nil else {
            return
        }
        listenGeneration += 1
        let generation = listenGeneration
        func hear(_ newTranscript: RepairTranscript) {
            receiveTranscript(newTranscript, generation: generation)
        }
        func ended(_ reason: VoiceTranscriptionEnd) {
            listeningEnded(reason, generation: generation)
        }
        do {
            try await transcriber.start(sessionStartedAt: startedAt, onUpdate: hear, onEnd: ended)
            isListening = true
            listenStartedAt = Date()
        } catch {
            // Permission declined, no on-device model, or the audio engine failed: the user can
            // still draw and type.
            isListening = false
            recordStartFailure(error)
        }
    }

    private func receiveTranscript(_ newTranscript: RepairTranscript, generation: Int) {
        guard generation == listenGeneration else {
            return
        }
        transcript = RepairListening.joined(earlierTranscript, newTranscript)
    }

    /// The orb goes idle at once; a listen that ended by itself starts again (see `retriesLeft`).
    private func listeningEnded(_ reason: VoiceTranscriptionEnd, generation: Int) {
        guard generation == listenGeneration, isListening else {
            return
        }
        isListening = false
        earlierTranscript = transcript
        if reason == .failed {
            let failure = transcriber.lastFailure?.summary ?? "recogniser error"
            recordVoiceProblem(failure)
        }
        guard RepairListening.listensAgain(after: reason), finish == nil else {
            return
        }
        let listenedFor = listenStartedAt.map(Self.secondsSince) ?? 0
        if listenedFor >= RepairListening.healthyListen {
            retriesLeft = RepairListening.retries
        }
        guard retriesLeft > 0 else {
            voiceLog.error("repair stops listening after a second failure")
            return
        }
        retriesLeft -= 1
        voiceLog.info("repair listens again after \(String(describing: reason), privacy: .public)")
        Task { @MainActor [weak self] in
            await self?.startListening()
        }
    }

    private static func secondsSince(_ date: Date) -> TimeInterval {
        Date().timeIntervalSince(date)
    }

    private func recordStartFailure(_ error: any Error) {
        guard let speechError = error as? VoiceTranscriberError else {
            recordVoiceProblem("start " + VoiceFailure(error).summary)
            return
        }
        switch speechError {
        case .notAuthorized:
            recordVoiceProblem("start notAuthorized")
        case .onDeviceUnavailable:
            recordVoiceProblem("start onDeviceUnavailable")
        case .audioFailed:
            let detail = transcriber.lastFailure?.summary ?? "unknown"
            recordVoiceProblem("start audioFailed " + detail)
        }
    }

    /// The same problem twice in a row is kept once.
    private func recordVoiceProblem(_ problem: String) {
        guard voiceProblems.last != problem else {
            return
        }
        voiceProblems.append(problem)
    }

    /// One line for the report, nil when voice worked. Adds "no words" with the microphone's
    /// buffer count when nothing was heard, so silence and a dead microphone look different.
    var voiceError: String? {
        var problems = voiceProblems
        if transcript.words.isEmpty, let bufferCount = transcriber.audioBufferCount {
            problems.append("no words, \(bufferCount) audio buffers")
        }
        guard !problems.isEmpty else {
            return nil
        }
        let joined = problems.joined(separator: "; ")
        return String(joined.prefix(RepairListening.maxVoiceErrorLength))
    }

    private func stopListening() {
        guard isListening else {
            return
        }
        transcriber.stop()
        isListening = false
    }

    /// The microphone's loudness for the pill's orb, read on the orb's own frame clock (the same
    /// way jess's orb reads it, `VoiceCaptureView`). Silence when the transcriber has no meter.
    var orbLevel: @Sendable () -> Double {
        guard let meter = transcriber.audioLevelMeter else {
            return JessOrb.silence
        }
        return Self.levelReader(for: meter)
    }

    /// Built outside the main actor: the orb calls it on its own frame clock.
    nonisolated static func levelReader(for meter: VoiceAudioLevelMeter) -> @Sendable () -> Double {
        { Double(meter.level) }
    }

    /// What the pill shows for the words, spoken and typed.
    func pillText(isTyping: Bool) -> RepairPillText {
        RepairPillText(spoken: transcript.text, typed: typedText, isListening: isListening, isTyping: isTyping)
    }

    // MARK: Drawing

    func elapsedMs(at date: Date = Date()) -> Double {
        (date.timeIntervalSince(startedAt) * 1000).rounded()
    }

    func beginStroke(at point: CGPoint) {
        activeStroke = RepairStroke(points: [[point.x, point.y, elapsedMs()]])
    }

    func extendStroke(to point: CGPoint) {
        guard activeStroke != nil else {
            beginStroke(at: point)
            return
        }
        activeStroke?.points.append([point.x, point.y, elapsedMs()])
    }

    func endStroke() {
        guard let activeStroke else {
            return
        }
        strokes.append(activeStroke)
        self.activeStroke = nil
    }

    func undo() {
        guard !strokes.isEmpty else {
            return
        }
        strokes.removeLast()
    }

    func clear() {
        strokes.removeAll()
        activeStroke = nil
    }

    // MARK: Finish

    func cancel() {
        stopListening()
        finish = .cancelled
        onFinish?()
    }

    /// True while a finger is drawing: the rim steps back.
    var isDrawing: Bool {
        activeStroke != nil
    }

    /// Dismisses at once; the upload runs on its own and is queued if it cannot go now.
    func send() {
        guard canSend else {
            return
        }
        endStroke()
        stopListening()
        let drawing = renderDrawing()
        let report = buildReport(drawing: drawing)
        finish = .sent
        onFinish?()
        guard let report else {
            return
        }
        onSent?(report, drawing)
        let uploader = self.uploader
        Task { @MainActor in
            await uploader.send(report)
        }
    }

    /// The screenshot with the strokes, as the user saw them.
    func renderDrawing() -> UIImage {
        RepairDrawingRenderer.render(screenshot: snapshot, strokes: strokes, penColor: RepairPen.uiColor, keylineColor: RepairPen.keyline(for: interfaceStyle))
    }

    private func buildReport(drawing: UIImage) -> RepairReport? {
        let screenScale = UIScreen.main.scale
        return try? RepairReportBuilder.build(
            clientReportId: id,
            sidekickId: sidekickId,
            bundle: bundleVersions.entry(forSidekickId: sidekickId),
            spokenText: transcript.text,
            typedText: typedText,
            words: transcript.words,
            strokes: strokes,
            screenshot: snapshot,
            drawing: drawing,
            viewSize: viewSize,
            screenScale: screenScale,
            sessionStartedAt: startedAt,
            deviceInfo: RepairDeviceInfo.current(),
            voiceError: voiceError
        )
    }
}

/// When the repair layer listens again (repair voice bug, 2026-10-23).
enum RepairListening {
    static let retries = 1
    /// A listen at least this long before it ended was working; the next end gets a fresh retry.
    static let healthyListen: TimeInterval = 2
    /// The server's short-field length (backend/src/repairs.ts MAX_SHORT_FIELD_LENGTH).
    static let maxVoiceErrorLength = 80

    /// Stop (Send, Cancel) and the five-minute backstop end it for good; the recogniser's own end
    /// (an error, or a final result while the layer is still open) does not.
    static func listensAgain(after reason: VoiceTranscriptionEnd) -> Bool {
        switch reason {
        case .stopped, .maximumLength:
            return false
        case .failed, .recognizerFinished, .silence:
            return true
        }
    }

    /// Words of an earlier listen, then the new listen's, on the same session clock.
    static func joined(_ earlier: RepairTranscript, _ later: RepairTranscript) -> RepairTranscript {
        let parts = [earlier.text, later.text]
        let spoken = parts.filter(hasWords)
        return RepairTranscript(text: spoken.joined(separator: " "), words: earlier.words + later.words)
    }

    private static func hasWords(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The words in the B3 pill (docs/mockups/repair-feedback-2026-10-23.html, section 1, states
/// listening / words appearing / typing / ready). Spoken words show live as they arrive; while
/// jess is still listening the newest word is grey, it may still change. Tapping the words types:
/// the typed words carry on after the spoken words in the same text area (`RepairPillTextView`,
/// founder 2026-10-23: typed text "appears somewhere else" when it had a box of its own) and both
/// are sent (`RepairReportBuilder.combinedTranscript`). "What to fix" only when there is neither.
struct RepairPillText: Equatable, Sendable {
    /// Spoken words that will not change any more.
    let settled: String
    /// The newest spoken word while listening; empty otherwise.
    let pending: String
    /// The text field's placeholder.
    let placeholder: String
    /// The text field is shown (otherwise it is folded away under the spoken words).
    let showsField: Bool

    /// Spoken words can take up to three lines; with the field under them, two.
    static let maxSpokenLines = 3

    init(spoken: String, typed: String, isListening: Bool, isTyping: Bool) {
        let pieces = spoken.split(whereSeparator: \.isWhitespace)
        let words = pieces.map(String.init)
        let hasSpoken = !words.isEmpty
        let hasTyped = !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isListening && hasSpoken {
            settled = words.dropLast().joined(separator: " ")
            pending = words[words.count - 1]
        } else {
            settled = words.joined(separator: " ")
            pending = ""
        }
        placeholder = hasSpoken ? "" : RepairCopy.textPlaceholder
        showsField = !hasSpoken || hasTyped || isTyping
    }

    var hasSpoken: Bool {
        !settled.isEmpty || !pending.isEmpty
    }

    /// Lines the spoken words may take: fewer when the field is under them.
    var spokenLineLimit: Int {
        showsField ? Self.maxSpokenLines - 1 : Self.maxSpokenLines
    }
}
