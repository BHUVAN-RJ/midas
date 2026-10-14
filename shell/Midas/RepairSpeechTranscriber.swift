import AVFoundation
import Foundation
import Speech

/// The words heard so far, with timings on the session clock.
struct RepairTranscript: Equatable, Sendable {
    var text: String
    var words: [RepairWord]

    static let empty = RepairTranscript(text: "", words: [])
}

enum RepairSpeechError: Error, Equatable {
    /// No on-device model for the language on this phone. Audio never goes to a server instead.
    case onDeviceUnavailable
    case notAuthorized
    case audioFailed
}

/// Transcribes the repair session. Audio never leaves the phone (PRODUCT.md §2, 2026-10-13).
@MainActor
protocol RepairTranscribing: AnyObject {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws
    func stop()
}

/// Microphone and speech permission as one state. Both are per app, asked once by iOS; a denial
/// can only be undone in Settings.
enum RepairPermissionState: Equatable, Sendable {
    case granted
    case notAsked
    case denied
}

enum RepairPermissions {
    @MainActor
    static func state() -> RepairPermissionState {
        let microphone = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        if microphone == .denied || speech == .denied || speech == .restricted {
            return .denied
        }
        if microphone == .granted && speech == .authorized {
            return .granted
        }
        return .notAsked
    }

    /// Shows the iOS prompts that are still unanswered. Returns the state afterwards.
    @MainActor
    static func request() async -> RepairPermissionState {
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        let speechStatus = await requestSpeechAuthorization()
        if microphoneGranted && speechStatus == .authorized {
            return .granted
        }
        return .denied
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// Holds the recognition request for the audio tap, which runs off the main actor.
private final class RecognitionRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}

/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition`: the phone's own model, no server.
/// Partial results stream in as the user speaks; each result carries every word so far with
/// its timing, rebased onto the session clock.
@MainActor
final class OnDeviceSpeechTranscriber: RepairTranscribing {
    /// A repair session is short; this is a backstop, not a feature.
    static let maximumDuration: Duration = .seconds(5 * 60)

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var requestBox: RecognitionRequestBox?
    private var stopTimer: Task<Void, Never>?

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        guard RepairPermissions.state() == .granted else {
            throw RepairSpeechError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw RepairSpeechError.onDeviceUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        let box = RecognitionRequestBox(request: request)
        requestBox = box

        do {
            try startAudio(feeding: box)
        } catch {
            throw RepairSpeechError.audioFailed
        }
        let audioStartedAt = Date()
        recognitionTask = recognizer.recognitionTask(with: request) { result, _ in
            guard let result else {
                return
            }
            let transcript = Self.transcript(from: result.bestTranscription, audioStartedAt: audioStartedAt, sessionStartedAt: sessionStartedAt)
            Task { @MainActor in
                onUpdate(transcript)
            }
        }
        stopTimer = Task { @MainActor in
            try? await Task.sleep(for: Self.maximumDuration)
            guard !Task.isCancelled else {
                return
            }
            self.stop()
        }
    }

    func stop() {
        stopTimer?.cancel()
        stopTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        requestBox?.request.endAudio()
        requestBox = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startAudio(feeding box: RecognitionRequestBox) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    nonisolated private static func transcript(from transcription: SFTranscription, audioStartedAt: Date, sessionStartedAt: Date) -> RepairTranscript {
        var words: [RepairWord] = []
        for segment in transcription.segments {
            let word = RepairWordTiming.word(segment.substring, segmentTimestamp: segment.timestamp, segmentDuration: segment.duration, audioStartedAt: audioStartedAt, sessionStartedAt: sessionStartedAt)
            words.append(word)
        }
        return RepairTranscript(text: transcription.formattedString, words: words)
    }
}
