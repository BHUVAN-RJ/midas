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
    /// The shell can't: answered on the phone, no edit on its way (repair lanes, 2026-11-13).
    /// Leaves like Cancel: the rim fades, the tag goes back into the island.
    case answered
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
    /// The keyboard is up for the pill's text area: the orb and the rim go still, and listening
    /// stops; the words already heard stay and the typing carries on after them. A tap on the orb
    /// listens again (founder, 2026-10-31, docs/briefs/build-22-2026-10-31.md).
    var isTyping = false {
        didSet {
            if isTyping && !oldValue {
                stopListening()
            }
        }
    }
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
    /// "Allow AI?" (founder, 2026-11-02): Send asks first until the person allowed it. Nil: no ask.
    var aiConsent: AIConsentCenter?
    /// How the layer ended; nil while it is open.
    private(set) var finish: RepairFinish?
    /// Where the fingers lifted, in window points: jess's orb pops there (O4). Nil when the layer
    /// was opened another way; the orb then starts in the pill.
    var liftPoint: CGPoint?
    /// Light or dark when the swipe fired: the pen's ink line is drawn in light mode only.
    var interfaceStyle: UIUserInterfaceStyle = .light

    // MARK: Lanes (founder, 2026-11-13, D4 = A)

    /// Where the layer is between Send and closing (`RepairSortRules`).
    private(set) var askStage: RepairAskStage = .open
    /// The phone's id for the next report: the session's id, renewed after "not a request" (no
    /// job was made, so the next Send is a new report).
    private(set) var reportId: String
    /// The guess the person tapped on the question card; its label fills the pill.
    private(set) var pickedOptionId: String?
    /// The server's id for the report the card asks about.
    private var askedRepairId: String?
    /// The report and its circled screenshot waiting for the lane; handed to the tag on close.
    private var waitingReport: RepairReport?
    private var waitingDrawing: UIImage?
    /// Bumped by every Send and answer, so a late reply or time-out of an older one is dropped.
    private var sortGeneration = 0
    /// How long Send waits for the lane before it closes as an edit.
    var sortWaitSeconds = RepairAskBackSpec.sortWaitSeconds
    /// How long the dark sheet stays before the layer closes.
    var shellCantSeconds = RepairAskBackSpec.shellCantSeconds
    /// jess_command: the person's words and how long they spoke, handed to jess as if said to
    /// jess (the live app: `JessResults.submit`, set in `begin`). Nil: the words go nowhere.
    var onJessCommand: ((_ transcript: String, _ listenMs: Int) -> Void)?

    init(sidekickId: String, snapshot: UIImage, viewSize: CGSize, transcriber: RepairTranscribing, uploader: RepairUploader, bundleVersions: SidekickBundleVersions = .shared, startedAt: Date = Date()) {
        self.sidekickId = sidekickId
        self.snapshot = snapshot
        self.viewSize = viewSize
        self.transcriber = transcriber
        self.uploader = uploader
        self.bundleVersions = bundleVersions
        self.startedAt = startedAt
        self.reportId = id
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
        session.onJessCommand = submitToJess
        return session
    }

    /// The words go to jess the way the Listening screen sends them: a home page card that
    /// finishes in the background (jess router, founder 2026-10-21/22).
    private static func submitToJess(transcript: String, listenMs: Int) {
        let results = ShellServices.shared.jessResults
        Task { @MainActor in
            await results.submit(transcript: transcript, listenMs: listenMs)
        }
    }

    /// Send lights up once there is a word, spoken or typed; the server rejects an empty transcript.
    /// Off while the lane is on its way and while the dark sheet is up.
    var canSend: Bool {
        switch askStage {
        case .sorting, .shellCant:
            return false
        case .open, .asking, .notARequest:
            break
        }
        return !combinedWords.isEmpty
    }

    private var combinedWords: String {
        RepairReportBuilder.combinedTranscript(spokenText: transcript.text, typedText: typedText)
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
        guard !isListening, !isTyping, finish == nil else {
            return
        }
        // Words of the listen the keyboard stopped stay, before the new listen's
        earlierTranscript = transcript
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

    /// Ends the listen for good (no listening again by itself). Its words stay; the recogniser's
    /// last words for it may still arrive and are kept.
    private func stopListening() {
        guard isListening else {
            return
        }
        isListening = false
        transcriber.stop()
    }

    /// A tap on the pill's orb: the keyboard goes down and jess listens again, after the words
    /// already there. Already listening: nothing changes.
    func listenAgain() {
        guard !isListening, finish == nil else {
            return
        }
        isTyping = false
        retriesLeft = RepairListening.retries
        Task { @MainActor [weak self] in
            await self?.startListening()
        }
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

    /// The level the V1 rim follows (L1): the orb's microphone level while jess listens, 0 while
    /// the user types or nothing is listening.
    func rimLevel() -> Double {
        guard isListening, !isTyping else {
            return 0
        }
        return orbLevel()
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
        sortGeneration += 1
        finish = .cancelled
        onFinish?()
    }

    /// True while a finger is drawing: the rim steps back.
    var isDrawing: Bool {
        activeStroke != nil
    }

    /// The pill's Send: "Allow AI?" first when not allowed yet (Not Now keeps the layer open, nothing
    /// is sent); otherwise sends.
    func sendWhenAllowed() {
        guard canSend else {
            return
        }
        guard let aiConsent else {
            send()
            return
        }
        aiConsent.run(send)
    }

    /// Send. With the question card up, sends the answer instead. When the Worker sorts reports
    /// (repair lanes, 2026-11-13) the layer stays on until the lane comes back; otherwise it
    /// dismisses at once and the upload runs on its own, queued if it cannot go now.
    func send() {
        guard canSend else {
            return
        }
        if askStage.question != nil {
            sendAnswer()
            return
        }
        endStroke()
        stopListening()
        let drawing = renderDrawing()
        let report = buildReport(drawing: drawing)
        guard uploader.sortsReports, let report else {
            sendWithoutSort(report: report, drawing: drawing)
            return
        }
        waitingReport = report
        waitingDrawing = drawing
        askStage = .sorting
        let generation = beginWaiting()
        let uploader = self.uploader
        Task { @MainActor [weak self] in
            let reply = await uploader.sendSorted(report)
            self?.receiveSort(reply, generation: generation)
        }
    }

    /// Before the lanes: the layer goes at once, the tag takes the report.
    private func sendWithoutSort(report: RepairReport?, drawing: UIImage) {
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

    /// The answer to the question card joins the same request; the Worker sorts it again.
    private func sendAnswer() {
        guard let question = askStage.question, let repairId = askedRepairId else {
            return
        }
        guard let answer = RepairSortRules.answer(pickedOptionId: pickedOptionId, options: question.options, words: combinedWords) else {
            return
        }
        endStroke()
        stopListening()
        askStage = .sorting
        let generation = beginWaiting()
        let uploader = self.uploader
        Task { @MainActor [weak self] in
            let outcome = await uploader.answer(repairId: repairId, answer: answer)
            self?.receiveAnswer(outcome, generation: generation)
        }
    }

    /// A dropped card (410) closes quietly: the card goes, the words stay in the pill, and the
    /// next Send is a new report. Otherwise the reply is read like the first one.
    private func receiveAnswer(_ outcome: RepairAnswerOutcome, generation: Int) {
        switch outcome {
        case .sorted(let reply):
            receiveSort(reply, generation: generation)
        case .failed:
            receiveSort(nil, generation: generation)
        case .dropped:
            guard generation == sortGeneration, askStage.isWaiting, finish == nil else {
                return
            }
            sortGeneration += 1
            dropCard()
        }
    }

    private func dropCard() {
        reportId = UUID().uuidString
        askedRepairId = nil
        pickedOptionId = nil
        waitingReport = nil
        waitingDrawing = nil
        askStage = .open
        retriesLeft = RepairListening.retries
        Task { @MainActor [weak self] in
            await self?.startListening()
        }
    }

    /// A new wait for the lane, with its own time-out: past `sortWaitSeconds` the layer closes
    /// as an edit (up a lane, never down).
    private func beginWaiting() -> Int {
        sortGeneration += 1
        let generation = sortGeneration
        let seconds = sortWaitSeconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.sortTimedOut(generation: generation)
        }
        return generation
    }

    private func sortTimedOut(generation: Int) {
        guard generation == sortGeneration, askStage.isWaiting, finish == nil else {
            return
        }
        voiceLog.info("repair sort did not answer in time; closing as an edit")
        receiveSort(nil, generation: generation)
    }

    /// The lane came back (or the wait ended): close, ask, keep listening, or show the sheet.
    func receiveSort(_ reply: RepairSortReply?, generation: Int) {
        guard generation == sortGeneration, askStage.isWaiting, finish == nil else {
            return
        }
        sortGeneration += 1
        if RepairSortRules.handsToJess(reply) {
            handToJess()
            return
        }
        let decision = RepairSortRules.decision(for: reply, knownRepairId: askedRepairId)
        switch decision {
        case .close:
            closeAsSent()
        case .ask(let question, let repairId):
            askedRepairId = repairId
            pickedOptionId = nil
            askStage = .asking(question)
            listenAfresh()
        case .listen(let message):
            // No job was made: the next Send is a new report, under a new phone id
            reportId = UUID().uuidString
            askedRepairId = nil
            pickedOptionId = nil
            waitingReport = nil
            waitingDrawing = nil
            askStage = .notARequest(message)
            listenAfresh()
        case .shellCant(let message):
            askStage = .shellCant(message)
            closeAfterSheet()
        }
    }

    /// jess_command: the words go to jess and repair mode closes; no edit is on its way, so the
    /// tag gets nothing.
    private func handToJess() {
        let words = waitingReport?.transcript ?? combinedWords
        let listenMs = Int(elapsedMs())
        waitingReport = nil
        waitingDrawing = nil
        finish = .answered
        onFinish?()
        guard !words.isEmpty else {
            return
        }
        onJessCommand?(words, listenMs)
    }

    /// The layer goes; the tag takes the report and plays Send into itself, as Send always did.
    private func closeAsSent() {
        finish = .sent
        onFinish?()
        guard let report = waitingReport, let drawing = waitingDrawing else {
            return
        }
        waitingReport = nil
        waitingDrawing = nil
        onSent?(report, drawing)
    }

    /// The dark sheet stays `shellCantSeconds`, then repair mode closes; no edit is on its way.
    private func closeAfterSheet() {
        let seconds = shellCantSeconds
        let generation = sortGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.finishAnswered(generation: generation)
        }
    }

    private func finishAnswered(generation: Int) {
        guard generation == sortGeneration, finish == nil else {
            return
        }
        stopListening()
        waitingReport = nil
        waitingDrawing = nil
        finish = .answered
        onFinish?()
    }

    /// A tap on a guess: it is picked and its words fill the pill, replacing what was there, so
    /// Send is one tap away. Another tap picks another.
    func pick(_ option: RepairQuestionOption) {
        guard let question = askStage.question, question.options.contains(option) else {
            return
        }
        pickedOptionId = option.id
        isTyping = false
        clearWords()
        typedText = option.label
    }

    /// Empty pill, jess listening again from nothing: the card's answer, or the next try after
    /// "not a request". The drawing stays.
    private func listenAfresh() {
        stopListening()
        clearWords()
        retriesLeft = RepairListening.retries
        Task { @MainActor [weak self] in
            await self?.startListening()
        }
    }

    /// The words heard and typed go; a late word of the listen that just ended is dropped.
    private func clearWords() {
        if isListening {
            stopListening()
            retriesLeft = RepairListening.retries
            Task { @MainActor [weak self] in
                await self?.startListening()
            }
        }
        listenGeneration += 1
        transcript = .empty
        earlierTranscript = .empty
        typedText = ""
    }

    /// The placeholder in the pill: "Or say it…" while the card is up, "What to fix" otherwise.
    var pillPlaceholder: String {
        if askStage.question != nil {
            return RepairAskBackCopy.orSayIt
        }
        return pillText(isTyping: isTyping).placeholder
    }

    /// "Say or draw what to change.", in the pill in bold, until there is a word again.
    var pillMessage: String? {
        guard case .notARequest(let message) = askStage, combinedWords.isEmpty, !isTyping else {
            return nil
        }
        return message
    }

    /// The screenshot with the strokes, as the user saw them.
    func renderDrawing() -> UIImage {
        RepairDrawingRenderer.render(screenshot: snapshot, strokes: strokes, penColor: RepairPen.uiColor, keylineColor: RepairPen.keyline(for: interfaceStyle))
    }

    private func buildReport(drawing: UIImage) -> RepairReport? {
        let screenScale = UIScreen.main.scale
        return try? RepairReportBuilder.build(
            clientReportId: reportId,
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
