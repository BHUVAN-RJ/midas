import AVFoundation
import Foundation
import Speech

/// One spoken word with its time on the caller's clock (repair: the same clock as the strokes).
struct VoiceWord: Codable, Equatable, Sendable {
    let word: String
    let startMs: Int
    let endMs: Int
}

/// Rebases speech-recogniser timings (seconds since the audio started) onto the caller's clock.
enum VoiceWordTiming {
    static func word(_ text: String, segmentTimestamp: TimeInterval, segmentDuration: TimeInterval, audioStartedAt: Date, sessionStartedAt: Date) -> VoiceWord {
        let audioOffsetMs = audioStartedAt.timeIntervalSince(sessionStartedAt) * 1000
        let startMs = Int((audioOffsetMs + segmentTimestamp * 1000).rounded())
        let endMs = Int((audioOffsetMs + (segmentTimestamp + segmentDuration) * 1000).rounded())
        return VoiceWord(word: text, startMs: startMs, endMs: endMs)
    }
}

/// The words heard so far, with timings on the caller's clock.
struct VoiceTranscript: Equatable, Sendable {
    var text: String
    var words: [VoiceWord]

    static let empty = VoiceTranscript(text: "", words: [])
}

enum VoiceTranscriberError: Error, Equatable {
    /// No on-device model for the language on this phone. Audio never goes to a server instead.
    case onDeviceUnavailable
    /// Microphone or speech recognition not granted (asked at launch by `VoicePermissions`).
    case notAuthorized
    case audioFailed
}

/// Why listening ended. Delivered once per `start`, whatever ended it.
enum VoiceTranscriptionEnd: Equatable, Sendable {
    /// No new words for `VoiceTranscriberOptions.endOfSpeechSilence` after the first word.
    case silence
    /// `VoiceTranscriberOptions.maximumDuration` reached.
    case maximumLength
    /// `stop()` called (Done, Send, Cancel).
    case stopped
    /// The recogniser reported an error and stopped.
    case failed
}

/// Per-use settings of the shared transcriber (founder, 2026-10-15: every voice feature reuses
/// it; one that needs more extends it here). Repair uses `.repair`: no hint words, no silence end,
/// a 5 minute backstop.
struct VoiceTranscriberOptions: Equatable, Sendable {
    /// Words the recogniser should favour (`contextualStrings`), e.g. the user's list names.
    var hintWords: [String] = []
    /// Ends listening this long after the last new words. Counts only once a word was heard;
    /// before that, only `maximumDuration` ends it. Nil: never ends on silence.
    var endOfSpeechSilence: Duration?
    /// Ends listening this long after it started, however much is still being said.
    var maximumDuration: Duration = .seconds(5 * 60)

    /// A repair session is short; the maximum is a backstop, not a feature.
    static let repair = VoiceTranscriberOptions()
}

/// The microphone's loudness while listening, 0 (silence) to 1, for whatever draws it (jess's orb,
/// voice reminders 2026-10-19). Written on iOS's audio thread and read on the drawing's own frame
/// clock, so it is a lock around one number instead of a hop to the main actor per buffer.
final class VoiceAudioLevelMeter: @unchecked Sendable {
    /// Quieter than this is silence; louder than `loudDecibels` is full.
    static let quietDecibels: Float = -50
    static let loudDecibels: Float = -10

    private let lock = NSLock()
    private var storedLevel: Float = 0

    init() {}

    var level: Float {
        lock.withLock { storedLevel }
    }

    func record(_ buffer: AVAudioPCMBuffer) {
        let newLevel = Self.level(of: buffer)
        lock.withLock { storedLevel = newLevel }
    }

    func reset() {
        lock.withLock { storedLevel = 0 }
    }

    /// Root mean square of the first channel, in decibels, mapped from quiet..loud onto 0..1.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }
        let samples = channels[0]
        let frameCount = Int(buffer.frameLength)
        var sumOfSquares: Float = 0
        for index in 0..<frameCount {
            sumOfSquares += samples[index] * samples[index]
        }
        let rootMeanSquare = (sumOfSquares / Float(frameCount)).squareRoot()
        return level(fromRootMeanSquare: rootMeanSquare)
    }

    static func level(fromRootMeanSquare rootMeanSquare: Float) -> Float {
        guard rootMeanSquare > 0 else {
            return 0
        }
        let decibels = 20 * log10(rootMeanSquare)
        let fraction = (decibels - quietDecibels) / (loudDecibels - quietDecibels)
        return min(1, max(0, fraction))
    }
}

/// Shared on-device speech-to-text: repair now, the Action button voice reminders next.
@MainActor
protocol VoiceTranscribing: AnyObject {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws
    func stop()
}

/// A buffer of microphone audio, delivered by iOS on its own audio thread.
typealias VoiceAudioTap = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

/// A recognition result, delivered by iOS on the recogniser's queue.
typealias VoiceRecognitionHandler = @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void

/// The parts of iOS the transcriber drives: the microphone and the on-device recogniser. A
/// protocol so tests can capture the callbacks and call them from a background queue.
@MainActor
protocol SpeechRecognitionEngine: AnyObject {
    /// An on-device model exists for this phone's language and the recogniser is ready.
    var isOnDeviceAvailable: Bool { get }
    func startAudio(tap: @escaping VoiceAudioTap) throws
    func stopAudio()
    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler)
    func cancelRecognition()
}

/// What the recognition callback hands back to the main actor.
enum VoiceRecognitionEvent: Equatable, Sendable {
    case heard(VoiceTranscript)
    case failed
}

/// Holds the recognition request for the audio tap, which runs off the main actor.
final class VoiceRecognitionRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}

/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, always: the phone's own model, never
/// Apple's servers (PRODUCT.md §2: audio never leaves the phone). Partial results stream in as the
/// user speaks; each carries every word so far with its timing, rebased onto the caller's clock.
///
/// Swift 6 (bug 1, first phone test 2026-10-14): iOS calls the audio tap and the recognition
/// handler on background threads, and a main-actor closure called there traps. Both are built by
/// `nonisolated static` functions, so they carry no actor, and they hop to the main actor only to
/// deliver what was heard.
@MainActor
final class OnDeviceSpeechTranscriber: VoiceTranscribing, RepairTranscribing {
    let options: VoiceTranscriberOptions
    /// How loud the microphone is right now; 0 when not listening.
    let audioLevel: VoiceAudioLevelMeter
    private let permissions: VoicePermissionSystem
    private let engine: SpeechRecognitionEngine

    private var requestBox: VoiceRecognitionRequestBox?
    private var onUpdate: (@MainActor (VoiceTranscript) -> Void)?
    private var onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?
    private var lastHeardText = ""
    private var maximumTimer: Task<Void, Never>?
    private var silenceTimer: Task<Void, Never>?

    init(options: VoiceTranscriberOptions = .repair, permissions: VoicePermissionSystem = LiveVoicePermissionSystem(), engine: SpeechRecognitionEngine? = nil, audioLevel: VoiceAudioLevelMeter = VoiceAudioLevelMeter()) {
        self.options = options
        self.audioLevel = audioLevel
        self.permissions = permissions
        self.engine = engine ?? LiveSpeechRecognitionEngine()
    }

    var isListening: Bool {
        requestBox != nil
    }

    /// Repair's entry point (`RepairTranscribing`): no end callback.
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void) async throws {
        try await start(sessionStartedAt: sessionStartedAt, onUpdate: onUpdate, onEnd: nil)
    }

    /// Throws before touching the microphone if permission is missing or there is no on-device
    /// model; nothing listens then.
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        guard VoicePermissions.state(system: permissions) == .granted else {
            throw VoiceTranscriberError.notAuthorized
        }
        guard engine.isOnDeviceAvailable else {
            throw VoiceTranscriberError.onDeviceUnavailable
        }
        if isListening {
            finish(.stopped)
        }
        let request = Self.makeRequest(options: options)
        let box = VoiceRecognitionRequestBox(request: request)
        do {
            try engine.startAudio(tap: Self.makeAudioTap(feeding: box, meter: audioLevel))
        } catch {
            engine.stopAudio()
            throw VoiceTranscriberError.audioFailed
        }
        requestBox = box
        self.onUpdate = onUpdate
        self.onEnd = onEnd
        lastHeardText = ""
        let resultHandler = Self.makeResultHandler(audioStartedAt: Date(), sessionStartedAt: sessionStartedAt, deliver: makeDelivery())
        engine.startRecognition(request: request, resultHandler: resultHandler)
        maximumTimer = endTimer(after: options.maximumDuration, reason: .maximumLength)
    }

    func stop() {
        finish(.stopped)
    }

    /// Main-actor side of the recognition callback. Internal so tests can drive the silence end
    /// without a real recogniser.
    func receive(_ event: VoiceRecognitionEvent) {
        guard isListening else {
            return
        }
        switch event {
        case .heard(let transcript):
            onUpdate?(transcript)
            // Partial results repeat; only new words restart the silence count
            if transcript.text != lastHeardText {
                lastHeardText = transcript.text
                restartSilenceTimer()
            }
        case .failed:
            finish(.failed)
        }
    }

    private func restartSilenceTimer() {
        guard let silence = options.endOfSpeechSilence, !lastHeardText.isEmpty else {
            return
        }
        silenceTimer?.cancel()
        silenceTimer = endTimer(after: silence, reason: .silence)
    }

    private func endTimer(after duration: Duration, reason: VoiceTranscriptionEnd) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else {
                return
            }
            self?.finish(reason)
        }
    }

    private func finish(_ reason: VoiceTranscriptionEnd) {
        guard let box = requestBox else {
            return
        }
        maximumTimer?.cancel()
        maximumTimer = nil
        silenceTimer?.cancel()
        silenceTimer = nil
        engine.stopAudio()
        audioLevel.reset()
        box.request.endAudio()
        engine.cancelRecognition()
        requestBox = nil
        onUpdate = nil
        let endHandler = onEnd
        onEnd = nil
        endHandler?(reason)
    }

    /// A weak hop back to this transcriber, made on the main actor and called only on it.
    private func makeDelivery() -> @MainActor (VoiceRecognitionEvent) -> Void {
        { [weak self] event in
            self?.receive(event)
        }
    }

    nonisolated static func makeRequest(options: VoiceTranscriberOptions) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = options.hintWords
        return request
    }

    /// Runs on iOS's audio thread: no actor.
    nonisolated static func makeAudioTap(feeding box: VoiceRecognitionRequestBox) -> VoiceAudioTap {
        { buffer, _ in
            box.request.append(buffer)
        }
    }

    /// The same tap, also measuring how loud each buffer is. Runs on iOS's audio thread: no actor.
    nonisolated static func makeAudioTap(feeding box: VoiceRecognitionRequestBox, meter: VoiceAudioLevelMeter) -> VoiceAudioTap {
        { buffer, _ in
            box.request.append(buffer)
            meter.record(buffer)
        }
    }

    /// Runs on the recogniser's queue: no actor. Builds the transcript there, then hops to the
    /// main actor to deliver it.
    nonisolated static func makeResultHandler(audioStartedAt: Date, sessionStartedAt: Date, deliver: @escaping @MainActor (VoiceRecognitionEvent) -> Void) -> VoiceRecognitionHandler {
        let sendableDeliver = SendableDelivery(deliver: deliver)
        return { result, error in
            let event: VoiceRecognitionEvent
            if let result {
                event = .heard(transcript(from: result.bestTranscription, audioStartedAt: audioStartedAt, sessionStartedAt: sessionStartedAt))
            } else if error != nil {
                event = .failed
            } else {
                return
            }
            Task { @MainActor in
                sendableDeliver.deliver(event)
            }
        }
    }

    nonisolated static func transcript(from transcription: SFTranscription, audioStartedAt: Date, sessionStartedAt: Date) -> VoiceTranscript {
        var words: [VoiceWord] = []
        for segment in transcription.segments {
            let word = VoiceWordTiming.word(segment.substring, segmentTimestamp: segment.timestamp, segmentDuration: segment.duration, audioStartedAt: audioStartedAt, sessionStartedAt: sessionStartedAt)
            words.append(word)
        }
        return VoiceTranscript(text: transcription.formattedString, words: words)
    }
}

/// Carries the main-actor delivery closure through the recogniser's queue. It is only ever
/// called on the main actor.
private struct SendableDelivery: @unchecked Sendable {
    let deliver: @MainActor (VoiceRecognitionEvent) -> Void
}

/// The real microphone and recogniser.
@MainActor
final class LiveSpeechRecognitionEngine: SpeechRecognitionEngine {
    private let audioEngine: AVAudioEngine
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private var recognitionTask: SFSpeechRecognitionTask?

    /// `audioEngine` is the microphone's engine; tests pass one in offline rendering mode.
    init(audioEngine: AVAudioEngine = AVAudioEngine()) {
        self.audioEngine = audioEngine
    }

    var isOnDeviceAvailable: Bool {
        guard let recognizer else {
            return false
        }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        try installTapAndStart(tap)
    }

    /// Hands the tap to iOS as it is. Never wrap it in a closure written here: that closure would
    /// be main-actor and trap when iOS calls it on the audio thread (bug 1, 2026-10-14).
    func installTapAndStart(_ tap: @escaping VoiceAudioTap) throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        recognitionTask = recognizer?.recognitionTask(with: request, resultHandler: resultHandler)
    }

    func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
