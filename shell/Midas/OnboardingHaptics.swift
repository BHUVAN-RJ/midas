import CoreHaptics
import Foundation

// The intro's haptics (docs/briefs/onboarding-build.md section 7): a continuous rumble while the
// hole charges, stronger and sharper as it fills, then one hard tap at the burst. The founder
// checks the feel on his phone. Does nothing where the phone has no haptics (the simulator).

@MainActor
final class OnboardingHaptics {
    private var engine: CHHapticEngine?
    private var rumblePlayer: CHHapticAdvancedPatternPlayer?
    private var isRumbling = false

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        try? engine?.start()
    }

    /// Rumble strength from the sim, 0..1. Zero stops it.
    func setRumble(_ strength: CGFloat) {
        guard let engine else {
            return
        }
        if strength <= 0.01 {
            stopRumble()
            return
        }
        if !isRumbling {
            startRumble(on: engine)
        }
        let intensity = Float(min(1, strength))
        // Sharpness 0.2 at the start of the charge, 0.6 when the hole is full
        let sharpness = Float(0.2 + 0.4 * min(1, strength))
        let intensityChange = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)
        let sharpnessChange = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0)
        try? rumblePlayer?.sendParameters([intensityChange, sharpnessChange], atTime: CHHapticTimeImmediate)
    }

    /// The burst: one hard tap.
    func burst() {
        guard let engine else {
            return
        }
        stopRumble()
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
        let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [tap], parameters: []) else {
            return
        }
        try? engine.start()
        let player = try? engine.makePlayer(with: pattern)
        try? player?.start(atTime: CHHapticTimeImmediate)
    }

    func stopRumble() {
        guard isRumbling else {
            return
        }
        try? rumblePlayer?.stop(atTime: CHHapticTimeImmediate)
        rumblePlayer = nil
        isRumbling = false
    }

    private func startRumble(on engine: CHHapticEngine) {
        // A long continuous event: intensity control multiplies 1, sharpness control adds to 0
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)
        let rumble = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: 30)
        guard let pattern = try? CHHapticPattern(events: [rumble], parameters: []) else {
            return
        }
        try? engine.start()
        rumblePlayer = try? engine.makeAdvancedPlayer(with: pattern)
        try? rumblePlayer?.start(atTime: CHHapticTimeImmediate)
        isRumbling = rumblePlayer != nil
    }
}
