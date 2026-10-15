import AVFoundation
import Foundation
import Speech

/// Microphone and speech recognition as one state. Shared by every voice feature: repair now,
/// the Action button voice reminders next. Both are per app (not per Sidekick): iOS asks once,
/// and a denial can only be undone in Settings.
enum VoicePermissionState: Equatable, Sendable {
    case granted
    case notAsked
    case denied
}

/// One permission as iOS reports it.
enum VoicePermissionAnswer: Equatable, Sendable {
    case granted
    case notAsked
    case denied
}

/// What iOS reports and asks. A protocol so tests can stand in for the system prompts.
protocol VoicePermissionSystem: Sendable {
    var microphone: VoicePermissionAnswer { get }
    var speech: VoicePermissionAnswer { get }
    func requestMicrophone() async
    func requestSpeech() async
}

/// Founder, 2026-10-15: Midas asks for both when it opens (once signed in), so no voice feature
/// ever stops for prompts. Only the iOS prompts, no Midas screen before them.
enum VoicePermissions {
    static func state(system: VoicePermissionSystem = LiveVoicePermissionSystem()) -> VoicePermissionState {
        let microphone = system.microphone
        let speech = system.speech
        if microphone == .denied || speech == .denied {
            return .denied
        }
        if microphone == .granted && speech == .granted {
            return .granted
        }
        return .notAsked
    }

    /// Shows each iOS prompt that has never been answered, microphone first. A prompt already
    /// answered either way is never shown again. Returns the state afterwards.
    @discardableResult
    static func askAtLaunch(system: VoicePermissionSystem = LiveVoicePermissionSystem()) async -> VoicePermissionState {
        if system.microphone == .notAsked {
            await system.requestMicrophone()
        }
        if system.speech == .notAsked {
            await system.requestSpeech()
        }
        return state(system: system)
    }
}

/// The real iOS permissions. Deliberately not main-actor: iOS calls the speech authorization
/// handler on a background queue, and under Swift 6 a main-actor closure called there traps.
struct LiveVoicePermissionSystem: VoicePermissionSystem {
    var microphone: VoicePermissionAnswer {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notAsked
        @unknown default:
            return .denied
        }
    }

    var speech: VoicePermissionAnswer {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notAsked
        @unknown default:
            return .denied
        }
    }

    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }

    func requestSpeech() async {
        _ = await Self.requestSpeechAuthorization()
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation(resumeSpeechContinuation)
    }

    /// Built here, outside any actor, so the handler iOS calls on its own queue is nonisolated.
    private static func resumeSpeechContinuation(_ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) {
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
}
