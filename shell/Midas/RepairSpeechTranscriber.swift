import Foundation

/// Repair's names for the shared voice types (`VoiceTranscriber.swift`, founder 2026-10-15:
/// every voice feature reuses one transcriber).
typealias RepairTranscript = VoiceTranscript
typealias RepairSpeechError = VoiceTranscriberError

/// Transcribes the repair session. Audio never leaves the phone (PRODUCT.md §2, 2026-10-13).
/// `OnDeviceSpeechTranscriber` with `VoiceTranscriberOptions.repair` is the real one.
@MainActor
protocol RepairTranscribing: AnyObject {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws
    /// The same, and told once when listening ends, whatever ended it (repair voice bug,
    /// 2026-10-23: the recogniser stopped and the orb kept showing listening).
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws
    func stop()
    /// Why the last listen failed to start or ended with an error.
    var lastFailure: VoiceFailure? { get }
    /// Microphone buffers received so far; nil when the transcriber cannot tell.
    var audioBufferCount: Int? { get }
}

/// A transcriber that never ends by itself and knows nothing of iOS's errors.
extension RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        try await start(sessionStartedAt: sessionStartedAt, onUpdate: onUpdate)
    }

    var lastFailure: VoiceFailure? {
        nil
    }

    var audioBufferCount: Int? {
        nil
    }
}
