#if MIDAS_TEST_BUILD
// Build 34: mic inside the keyboard (TEST BUILD, founder 2026-11-19; branch agent/dictation-test,
// never merged; docs/briefs/dictation-keyboard-test.md, "Build 34"). Compiled into the Midas Test
// app and the MidasKeyboard extension.
//
// Apple's guide says a keyboard gets no microphone; one unverified report says it may work with
// Full Access on and the microphone already allowed for the app. With `keyboardMic` "keyboard" in
// the Dictation Sidekick's settings:main (the default), the keyboard tries to record itself: the
// app's own transcriber (OnDeviceSpeechTranscriber) on a keyboard engine that does each step
// apart (session category, activate, engine start; then audio and the recogniser), the gate on
// each pause (DictationKeyboardInsertText), then insertText, with no app switch. Each keyboard
// appearance is one attempt and ends in one `dictation.probe`: works (words were recognised) or
// failed, with the step and the exact error. A failed attempt falls back to the app switch
// (build 33). "app" skips the keyboard microphone.
//
// The keyboard cannot write the app's records: probes and runs wait as files in the App Group
// (`probes/`, `keyboard-runs/`) until Midas Test saves them (DictationKeyboardSession).
import AVFoundation
import Foundation
import Speech
import UIKit

extension VoiceTranscriberOptions {
    /// Keyboard dictation: a pause of 1 s inserts; a listen never runs past 5 minutes.
    static let keyboardDictation = VoiceTranscriberOptions(endOfSpeechSilence: DictationKeyboardConstants.endOfSpeechSilence,
                                                           maximumDuration: .seconds(5 * 60))
}

// MARK: The setting

/// Where keyboard dictation records: settings:main `keyboardMic`.
enum DictationKeyboardMicMode: String, Equatable, Sendable, CaseIterable {
    /// Try the microphone in the keyboard; fall back to the app switch on failure.
    case keyboard
    /// Build 33's path: the microphone runs in Midas Test.
    case app

    static let builtIn: DictationKeyboardMicMode = .keyboard
    static let settingsField = "keyboardMic"

    /// The mode a settings:main value asks for; the built-in one when missing or unknown.
    static func from(settings value: JSONValue?) -> DictationKeyboardMicMode {
        guard let text = value?[settingsField]?.stringValue, let mode = DictationKeyboardMicMode(rawValue: text) else {
            return builtIn
        }
        return mode
    }
}

/// Which microphone the keyboard listens with now.
enum DictationKeyboardMicRoute: Equatable, Sendable {
    case keyboardMic
    /// Midas Test's microphone, through the App Group (build 33).
    case app

    /// Nil without Full Access (letters only, no dictation). A failed keyboard attempt falls back
    /// to the app until the keyboard appears again.
    static func route(mode: DictationKeyboardMicMode, hasFullAccess: Bool, keyboardMicFailed: Bool) -> DictationKeyboardMicRoute? {
        guard hasFullAccess else {
            return nil
        }
        switch mode {
        case .app:
            return .app
        case .keyboard:
            return keyboardMicFailed ? .app : .keyboardMic
        }
    }
}

// MARK: The probe

/// The step of recording in the keyboard, in order.
enum DictationKeyboardProbeStep: String, Codable, Equatable, Sendable, CaseIterable {
    case sessionCategory = "session-category"
    case activate
    case engineStart = "engine-start"
    /// Buffers from the microphone, and not all zeros.
    case audio
    case recogniser

    var label: String {
        switch self {
        case .sessionCategory:
            return "session category"
        case .activate:
            return "activate"
        case .engineStart:
            return "engine start"
        case .audio:
            return "audio"
        case .recogniser:
            return "recogniser"
        }
    }
}

enum DictationKeyboardProbeResult: String, Codable, Equatable, Sendable {
    case works
    case failed
}

/// An error as iOS (or the keyboard) reported it.
struct DictationKeyboardProbeError: Codable, Equatable, Sendable {
    let domain: String
    let code: Int
    let message: String

    init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }

    init(_ error: any Error) {
        let nsError = error as NSError
        self.init(domain: nsError.domain, code: nsError.code, message: nsError.localizedDescription)
    }

    /// The keyboard's own errors, when iOS reported none.
    static let keyboardDomain = "MidasKeyboardMic"
    static let noAudio = DictationKeyboardProbeError(domain: keyboardDomain, code: 1, message: "No audio from the microphone.")
    static let silentAudio = DictationKeyboardProbeError(domain: keyboardDomain, code: 2, message: "Audio was all zeros.")
    static let noWords = DictationKeyboardProbeError(domain: keyboardDomain, code: 3, message: "No words recognised.")
    static let keyboardEnded = DictationKeyboardProbeError(domain: keyboardDomain, code: 4, message: "The keyboard stopped during this step.")
    static let noOnDeviceModel = DictationKeyboardProbeError(domain: keyboardDomain, code: 5, message: "No on-device speech model.")
    static let recogniserFailed = DictationKeyboardProbeError(domain: keyboardDomain, code: 6, message: "The recogniser failed without details.")

    /// "kAFAssistantErrorDomain 1101: The operation couldn't be completed."
    var summary: String {
        "\(domain) \(code): \(message)"
    }
}

/// What the keyboard knew when it tried.
struct DictationKeyboardProbeContext: Codable, Equatable, Sendable {
    let fullAccess: Bool
    /// granted | denied | undetermined (AVAudioApplication, as the keyboard sees it).
    let microphone: String
    /// authorized | denied | restricted | not-determined (SFSpeechRecognizer, as the keyboard sees it).
    let speech: String
    let build: String
    let ios: String

    static func current(fullAccess: Bool) -> DictationKeyboardProbeContext {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return DictationKeyboardProbeContext(fullAccess: fullAccess, microphone: microphoneName(AVAudioApplication.shared.recordPermission),
                                             speech: speechName(SFSpeechRecognizer.authorizationStatus()), build: build,
                                             ios: UIDevice.current.systemVersion)
    }

    static func microphoneName(_ permission: AVAudioApplication.recordPermission) -> String {
        switch permission {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .undetermined:
            return "undetermined"
        @unknown default:
            return "unknown"
        }
    }

    static func speechName(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not-determined"
        @unknown default:
            return "unknown"
        }
    }
}

/// How much audio the keyboard's microphone delivered.
struct DictationKeyboardAudioCount: Codable, Equatable, Sendable {
    let buffers: Int
    /// The loudest sample, 0 to 1; exactly 0 means every buffer was zeros.
    let peak: Double

    static let none = DictationKeyboardAudioCount(buffers: 0, peak: 0)
}

/// One attempt's answer, saved as a `dictation.probe` record.
struct DictationKeyboardProbe: Codable, Equatable, Sendable {
    let id: String
    let at: Date
    let result: DictationKeyboardProbeResult
    /// The step that failed; nil when it works.
    let step: DictationKeyboardProbeStep?
    let error: DictationKeyboardProbeError?
    let context: DictationKeyboardProbeContext
    let audio: DictationKeyboardAudioCount

    /// The one line on the listening panel while testing.
    var panelLine: String {
        guard result == .failed else {
            return "Mic in keyboard: works"
        }
        let stepLabel = step?.label ?? "start"
        let errorText = error?.summary ?? "no details"
        return "Mic in keyboard: \(stepLabel), \(errorText)"
    }
}

/// One keyboard appearance's try at the microphone. Saved to the App Group at every step, so an
/// attempt iOS ends (the keyboard's memory limit, a crash) still becomes a probe the next time.
struct DictationKeyboardProbeAttempt: Codable, Equatable, Sendable {
    let id: String
    let startedAt: Date
    let context: DictationKeyboardProbeContext
    /// The step being tried now (the last one reached).
    private(set) var step: DictationKeyboardProbeStep = .sessionCategory

    init(id: String, startedAt: Date, context: DictationKeyboardProbeContext) {
        self.id = id
        self.startedAt = startedAt
        self.context = context
    }

    /// "20261119T231502123Z" plus a counter: sorts by time.
    static func newId(at date: Date, counter: Int) -> String {
        let milliseconds = Int((date.timeIntervalSince1970 * 1000).rounded(.down))
        return "\(milliseconds)-\(String(format: "%04d", counter % 10_000))"
    }

    mutating func reached(_ newStep: DictationKeyboardProbeStep) {
        step = newStep
    }

    func works(audio: DictationKeyboardAudioCount, at date: Date) -> DictationKeyboardProbe {
        DictationKeyboardProbe(id: id, at: date, result: .works, step: nil, error: nil, context: context, audio: audio)
    }

    func failed(at failedStep: DictationKeyboardProbeStep, error: DictationKeyboardProbeError, audio: DictationKeyboardAudioCount,
                date: Date) -> DictationKeyboardProbe {
        DictationKeyboardProbe(id: id, at: date, result: .failed, step: failedStep, error: error, context: context, audio: audio)
    }

    /// The keyboard stopped listening before any words: the audio tells which step.
    func noWords(audio: DictationKeyboardAudioCount, at date: Date) -> DictationKeyboardProbe {
        let mapped = Self.noWordsFailure(audio: audio)
        return failed(at: mapped.step, error: mapped.error, audio: audio, date: date)
    }

    /// Left in the App Group: iOS ended the keyboard during `step`.
    func ended(at date: Date) -> DictationKeyboardProbe {
        failed(at: step, error: .keyboardEnded, audio: .none, date: date)
    }

    /// No buffers: audio. All zeros (what a muted microphone gives): audio. Sound but no words:
    /// the recogniser (or nothing was said).
    static func noWordsFailure(audio: DictationKeyboardAudioCount) -> (step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError) {
        if audio.buffers == 0 {
            return (.audio, .noAudio)
        }
        if audio.peak <= 0 {
            return (.audio, .silentAudio)
        }
        return (.recogniser, .noWords)
    }

    /// The step and error for a listen that would not start: the engine's own step when it
    /// recorded one; no on-device model is the recogniser.
    static func startFailure(engineFailure: (step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError)?,
                             thrown: any Error) -> (step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError) {
        // Thrown before the engine was asked for audio: an older engine failure does not count
        if let transcriberError = thrown as? VoiceTranscriberError, transcriberError == .onDeviceUnavailable {
            return (.recogniser, .noOnDeviceModel)
        }
        if let engineFailure {
            return engineFailure
        }
        return (.engineStart, DictationKeyboardProbeError(thrown))
    }
}

/// The `dictation.probe` record (manifest `probe:`).
enum DictationProbeRecord {
    static let keyPrefix = "probe:"
    static let maxMessageCharacters = 400

    static func value(_ probe: DictationKeyboardProbe) -> JSONValue {
        var fields: [String: JSONValue] = [
            "at": .string(DictationProbeRecord.timestamp(probe.at)),
            "result": .string(probe.result.rawValue),
            "fullAccess": .bool(probe.context.fullAccess),
            "microphone": .string(String(probe.context.microphone.prefix(20))),
            "speech": .string(String(probe.context.speech.prefix(20))),
            "build": .string(String(probe.context.build.prefix(20))),
            "ios": .string(String(probe.context.ios.prefix(20))),
            "buffers": .number(Double(max(0, probe.audio.buffers))),
            "peak": .number(min(1, max(0, probe.audio.peak))),
        ]
        if let step = probe.step {
            fields["step"] = .string(step.rawValue)
        }
        if let error = probe.error {
            fields["errorDomain"] = .string(String(error.domain.prefix(120)))
            fields["errorCode"] = .number(Double(error.code))
            fields["errorMessage"] = .string(String(error.message.prefix(maxMessageCharacters)))
        }
        return .object(fields)
    }

    /// "2026-11-19T23:15:02.123Z"
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// One pause the keyboard's own microphone inserted, waiting for the app to save it as a
/// `dictation.run` (source keyboard), like build 33's.
struct DictationKeyboardMicRun: Codable, Equatable, Sendable {
    let id: String
    let raw: String
    let text: String
    let path: String
    let trigger: String?
    let matched: [String]
    let gateMs: Double
    let endOfSpeechAt: Date
    let rawFinalAt: Date
    let insertedAt: Date
    let thermal: String

    init(id: String, raw: String, outcome: DictationKeyboardInsertText.Outcome, endOfSpeechAt: Date, rawFinalAt: Date, insertedAt: Date,
         thermal: DictationThermal) {
        self.id = id
        self.raw = raw
        self.text = outcome.text
        self.path = outcome.gate.decision.path.rawValue
        self.trigger = outcome.gate.decision.trigger
        self.matched = outcome.gate.decision.matched
        self.gateMs = outcome.gate.gateMs
        self.endOfSpeechAt = endOfSpeechAt
        self.rawFinalAt = rawFinalAt
        self.insertedAt = insertedAt
        self.thermal = thermal.rawValue
    }

    /// The gate's outcome again, for DictationTestRuns.keyboard; nil for a path this build does
    /// not know.
    var gateOutcome: DictationGateOutcome? {
        guard let decodedPath = DictationPath(rawValue: path) else {
            return nil
        }
        let decision = DictationGateDecision(path: decodedPath, trigger: trigger, matched: matched, text: text, instruction: nil)
        return DictationGateOutcome(decision: decision, gateMs: gateMs)
    }
}

// MARK: The keyboard's microphone

/// Buffers and the loudest sample, counted on iOS's audio thread.
final class DictationKeyboardAudioCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers = 0
    private var peak: Float = 0

    func record(_ buffer: AVAudioPCMBuffer) {
        let loudest = Self.peak(of: buffer)
        lock.withLock {
            buffers += 1
            peak = max(peak, loudest)
        }
    }

    func reset() {
        lock.withLock {
            buffers = 0
            peak = 0
        }
    }

    var count: DictationKeyboardAudioCount {
        lock.withLock {
            DictationKeyboardAudioCount(buffers: buffers, peak: Double(peak))
        }
    }

    static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }
        let samples = channels[0]
        var loudest: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            loudest = max(loudest, abs(samples[index]))
        }
        return loudest
    }
}

/// The recogniser's last error with its message, kept on the recogniser's queue.
final class DictationKeyboardErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: DictationKeyboardProbeError?

    func set(_ error: DictationKeyboardProbeError?) {
        lock.withLock {
            stored = error
        }
    }

    var error: DictationKeyboardProbeError? {
        lock.withLock {
            stored
        }
    }
}

/// What the keyboard's listener needs from an engine beyond the transcriber's: which step it is
/// on and how each failed. A protocol so the tests drive the listener without a microphone.
@MainActor
protocol DictationKeyboardMicEngine: SpeechRecognitionEngine {
    /// Called as each step starts.
    var onStep: ((DictationKeyboardProbeStep) -> Void)? { get set }
    /// The step that threw in the last `startAudio`, with iOS's error.
    var lastStepFailure: (step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError)? { get }
    /// The recogniser's last error with its message.
    var lastRecogniserError: DictationKeyboardProbeError? { get }
    var audioCount: DictationKeyboardAudioCount { get }
}

/// The microphone and recogniser in the keyboard, one step at a time so a failure names its
/// step. The same calls as LiveSpeechRecognitionEngine.
@MainActor
final class DictationKeyboardLiveMicEngine: DictationKeyboardMicEngine {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private var recognitionTask: SFSpeechRecognitionTask?
    private let counter = DictationKeyboardAudioCounter()
    private let errorBox = DictationKeyboardErrorBox()
    private var tapInstalled = false
    var onStep: ((DictationKeyboardProbeStep) -> Void)?
    private(set) var lastStepFailure: (step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError)?

    var lastRecogniserError: DictationKeyboardProbeError? {
        errorBox.error
    }

    var audioCount: DictationKeyboardAudioCount {
        counter.count
    }

    var isOnDeviceAvailable: Bool {
        guard let recognizer else {
            return false
        }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        lastStepFailure = nil
        let audioSession = AVAudioSession.sharedInstance()
        try runStep(.sessionCategory) {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        }
        try runStep(.activate) {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
        try runStep(.engineStart) {
            try self.installTapAndStart(tap)
        }
        onStep?(.audio)
    }

    /// One step: announced, and its error kept with the step's name.
    private func runStep(_ step: DictationKeyboardProbeStep, _ body: () throws -> Void) throws {
        onStep?(step)
        do {
            try body()
        } catch {
            lastStepFailure = (step, DictationKeyboardProbeError(error))
            throw error
        }
    }

    private func installTapAndStart(_ tap: @escaping VoiceAudioTap) throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // No input: iOS reports 0 Hz, and installing a tap with it raises instead of throwing
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "MidasAudioInput", code: Int(format.sampleRate),
                          userInfo: [NSLocalizedDescriptionKey: "The microphone input has no format (\(format.sampleRate) Hz, \(format.channelCount) channels)."])
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeCountingTap(tap, counter: counter))
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Runs on iOS's audio thread: no actor.
    nonisolated static func makeCountingTap(_ tap: @escaping VoiceAudioTap, counter: DictationKeyboardAudioCounter) -> VoiceAudioTap {
        { buffer, time in
            counter.record(buffer)
            tap(buffer, time)
        }
    }

    func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        onStep?(.recogniser)
        errorBox.set(nil)
        recognitionTask = recognizer?.recognitionTask(with: request, resultHandler: Self.makeErrorKeepingHandler(resultHandler, box: errorBox))
    }

    /// Runs on the recogniser's queue: no actor. Keeps the error's message, which VoiceFailure drops.
    nonisolated static func makeErrorKeepingHandler(_ handler: @escaping VoiceRecognitionHandler, box: DictationKeyboardErrorBox) -> VoiceRecognitionHandler {
        { result, error in
            if let error {
                box.set(DictationKeyboardProbeError(error))
            }
            handler(result, error)
        }
    }

    func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

/// Microphone and speech as granted, so the transcriber makes iOS's own calls and the probe gets
/// iOS's own error (the real permission states are in the probe's context).
struct DictationKeyboardProbePermissions: VoicePermissionSystem {
    var microphone: VoicePermissionAnswer {
        .granted
    }

    var speech: VoicePermissionAnswer {
        .granted
    }

    func requestMicrophone() async {}

    func requestSpeech() async {}
}

/// Dictation with the keyboard's own microphone: listen, a 1 s pause runs the gate and inserts,
/// listen again. One probe per attempt: works at the first words; failed at the step that threw,
/// or, when listening stops with no words, at the step the audio points to.
@MainActor
final class DictationKeyboardMicListener {
    struct Handlers {
        /// The raw words of the current listen, as they come.
        var heard: @MainActor (String) -> Void
        /// Text to insert (the gate's output; the keyboard adds the space). Returns when it went in.
        var insert: @MainActor (String) -> Date
        /// The attempt's answer, once.
        var answered: @MainActor (DictationKeyboardProbe) -> Void
        /// A pause that went in, for the app to save.
        var inserted: @MainActor (DictationKeyboardMicRun) -> Void
        /// The attempt as it stands (nil once answered), kept in case iOS ends the keyboard.
        var attemptChanged: @MainActor (DictationKeyboardProbeAttempt?) -> Void
        /// Listening stopped by itself after it worked (the recogniser failed later).
        var stoppedListening: @MainActor () -> Void
    }

    private let engine: DictationKeyboardMicEngine
    private let transcriber: OnDeviceSpeechTranscriber
    private let settings: @MainActor () -> DictationGateSettings
    private let handlers: Handlers
    private let now: @MainActor () -> Date
    private var attempt: DictationKeyboardProbeAttempt?
    private(set) var answer: DictationKeyboardProbe?
    private(set) var wantsListening = false
    private var heardText = ""
    private var lastWordsAt: Date?
    private var stopAskedAt: Date?
    private var counter = 0

    init(engine: DictationKeyboardMicEngine, settings: @escaping @MainActor () -> DictationGateSettings, handlers: Handlers,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.engine = engine
        self.settings = settings
        self.handlers = handlers
        self.now = now
        self.transcriber = OnDeviceSpeechTranscriber(options: .keyboardDictation, permissions: DictationKeyboardProbePermissions(), engine: engine)
        self.engine.onStep = makeStepHandler()
    }

    private func makeStepHandler() -> (DictationKeyboardProbeStep) -> Void {
        { [weak self] step in
            self?.reached(step)
        }
    }

    var isListening: Bool {
        transcriber.isListening
    }

    /// The transcriber, for tests that feed it words.
    var transcriberForTests: OnDeviceSpeechTranscriber {
        transcriber
    }

    /// The keyboard appeared (or the ● key): a new attempt unless this appearance has one.
    func start(context: DictationKeyboardProbeContext) async {
        wantsListening = true
        if attempt == nil && answer == nil {
            counter += 1
            attempt = DictationKeyboardProbeAttempt(id: DictationKeyboardProbeAttempt.newId(at: now(), counter: counter), startedAt: now(), context: context)
            handlers.attemptChanged(attempt)
        }
        await beginListening()
    }

    /// The keyboard went away or switched to typing: the words already said still go in.
    func stop() {
        wantsListening = false
        if transcriber.isListening {
            stopAskedAt = now()
            transcriber.stopAndAwaitFinal()
        } else {
            answerNoWordsIfOpen()
        }
    }

    /// A new keyboard appearance: a new attempt next time.
    func reset() {
        attempt = nil
        answer = nil
    }

    private func reached(_ step: DictationKeyboardProbeStep) {
        guard var current = attempt, answer == nil else {
            return
        }
        current.reached(step)
        attempt = current
        handlers.attemptChanged(current)
    }

    private func beginListening() async {
        heardText = ""
        lastWordsAt = nil
        stopAskedAt = nil
        let listenStartedAt = now()
        do {
            try await transcriber.start(sessionStartedAt: listenStartedAt, onUpdate: makeUpdateHandler(), onEnd: makeEndHandler())
        } catch {
            let failure = DictationKeyboardProbeAttempt.startFailure(engineFailure: engine.lastStepFailure, thrown: error)
            let hadWorked = answer != nil
            wantsListening = false
            answerFailed(step: failure.step, error: failure.error)
            // A later listen that would not start, after this attempt worked: the panel goes idle
            if hadWorked {
                handlers.stoppedListening()
            }
            return
        }
        // The keyboard stopped while the recogniser was starting
        if !wantsListening {
            stopAskedAt = stopAskedAt ?? now()
            transcriber.stopAndAwaitFinal()
        }
    }

    private func makeUpdateHandler() -> @MainActor (VoiceTranscript) -> Void {
        { [weak self] transcript in
            self?.heardWords(transcript)
        }
    }

    private func makeEndHandler() -> @MainActor (VoiceTranscriptionEnd) -> Void {
        { [weak self] reason in
            self?.listenEnded(reason)
        }
    }

    private func heardWords(_ transcript: VoiceTranscript) {
        guard transcript.text != heardText else {
            return
        }
        heardText = transcript.text
        lastWordsAt = now()
        let hasWords = !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasWords, let current = attempt, answer == nil {
            answerWith(current.works(audio: engine.audioCount, at: now()))
        }
        handlers.heard(transcript.text)
    }

    private func listenEnded(_ reason: VoiceTranscriptionEnd) {
        let rawFinalAt = now()
        let raw = heardText
        heardText = ""
        // A pause: speech ended with the last new words. Stopped by the keyboard: when it asked
        let endOfSpeechAt: Date
        switch reason {
        case .silence:
            endOfSpeechAt = lastWordsAt ?? rawFinalAt
        default:
            endOfSpeechAt = stopAskedAt ?? lastWordsAt ?? rawFinalAt
        }
        insert(raw, endOfSpeechAt: endOfSpeechAt, rawFinalAt: rawFinalAt)
        if reason == .failed {
            let error = engine.lastRecogniserError ?? .recogniserFailed
            wantsListening = false
            answerFailed(step: .recogniser, error: error)
            handlers.stoppedListening()
            return
        }
        guard wantsListening else {
            answerNoWordsIfOpen()
            return
        }
        Task { @MainActor [weak self] in
            await self?.beginListening()
        }
    }

    /// The gate on the raw words, then the keyboard inserts them.
    private func insert(_ raw: String, endOfSpeechAt: Date, rawFinalAt: Date) {
        guard let outcome = DictationKeyboardInsertText.make(raw: raw, settings: settings()) else {
            return
        }
        let insertedAt = handlers.insert(outcome.text)
        counter += 1
        let runId = DictationKeyboardProbeAttempt.newId(at: insertedAt, counter: counter)
        let run = DictationKeyboardMicRun(id: runId, raw: raw, outcome: outcome, endOfSpeechAt: endOfSpeechAt, rawFinalAt: rawFinalAt,
                                          insertedAt: insertedAt, thermal: .current())
        handlers.inserted(run)
    }

    private func answerNoWordsIfOpen() {
        guard let current = attempt, answer == nil else {
            return
        }
        answerWith(current.noWords(audio: engine.audioCount, at: now()))
    }

    private func answerFailed(step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError) {
        guard let current = attempt, answer == nil else {
            return
        }
        answerWith(current.failed(at: step, error: error, audio: engine.audioCount, date: now()))
    }

    private func answerWith(_ probe: DictationKeyboardProbe) {
        answer = probe
        handlers.attemptChanged(nil)
        handlers.answered(probe)
    }
}
#endif
