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
    func stop()
}
