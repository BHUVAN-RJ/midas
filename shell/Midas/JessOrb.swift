import SwiftUI

// jess's orb (docs/DESIGN.md §5a, founder 2026-10-15): the one voice mark across Midas. Voice
// reminders use it now; repair and every later voice feature drop the same view in
// (`JessOrb(state:level:)`). The drawing follows the approved mockup's code
// (docs/mockups/jess-orb-2026-10-15.html, variation 1 "Neon core", tuned glow 3, spread 0): a soft
// body whose outline is the sum of three low-order wobble modes, an ink ring, and a crisp solid
// core with no halo. The body's soft glow is the only glow. Never purple.

/// What the orb is showing.
enum JessOrbState: Equatable, Sendable {
    /// Faint core, a slow breath.
    case idle
    /// The outline ripples with the voice; the core grows slightly with it.
    case listening
    /// An arc sweeps the rim and pushes the wall out ahead of it.
    case thinking
    /// Core flat green.
    case added
    /// Core flat red.
    case failed
}

/// An sRGB colour with alpha, kept as numbers so tests can check the exact values.
struct JessOrbColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(hex: UInt32, alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// The mockup's MODE_COLOURS and RESULT, per appearance.
struct JessOrbPalette: Equatable, Sendable {
    let body: JessOrbColor
    let bodyGlow: JessOrbColor
    let ring: JessOrbColor
    let core: JessOrbColor
    let arc: JessOrbColor
    let arcGlow: JessOrbColor
    let added: JessOrbColor
    let failed: JessOrbColor

    /// White body, ink ring, black core.
    static let light = JessOrbPalette(
        body: JessOrbColor(hex: 0xFFFFFF),
        bodyGlow: JessOrbColor(hex: 0x000000, alpha: 0.18),
        ring: JessOrbColor(hex: 0x111111),
        core: JessOrbColor(hex: 0x000000),
        arc: JessOrbColor(hex: 0x111111),
        arcGlow: JessOrbColor(hex: 0x000000),
        added: JessOrbColor(hex: 0x00873A),
        failed: JessOrbColor(hex: 0xE00000)
    )

    /// Black body with a soft white glow, dark ring, white core.
    static let dark = JessOrbPalette(
        body: JessOrbColor(hex: 0x000000),
        bodyGlow: JessOrbColor(hex: 0xFFFFFF, alpha: 0.22),
        ring: JessOrbColor(hex: 0x2A2A2A),
        core: JessOrbColor(hex: 0xFFFFFF),
        arc: JessOrbColor(hex: 0xFFFFFF),
        arcGlow: JessOrbColor(hex: 0xFFFFFF, alpha: 0.95),
        added: JessOrbColor(hex: 0x3DDC84),
        failed: JessOrbColor(hex: 0xFF5C5C)
    )

    static func forScheme(_ scheme: ColorScheme) -> JessOrbPalette {
        scheme == .dark ? .dark : .light
    }

    /// Green and red are the core only: the ring and body never change with the result.
    func coreColor(for state: JessOrbState) -> JessOrbColor {
        switch state {
        case .added:
            return added
        case .failed:
            return failed
        case .idle, .listening, .thinking:
            return core
        }
    }
}

/// The orb's soft body: spring-driven wobble modes, stepped at a fixed 60 per second as the
/// mockup's requestAnimationFrame loop is. Pure, so tests can step it.
struct JessOrbMotion: Equatable, Sendable {
    static let modes: [Double] = [2, 3, 4]
    static let outlinePoints = 72
    static let stepsPerSecond: Double = 60
    /// A long pause (the app in the background) is not replayed frame by frame.
    static let maximumStepsPerAdvance = 30

    private(set) var amplitudes: [Double] = [0, 0, 0]
    private(set) var velocities: [Double] = [0, 0, 0]
    private(set) var phases: [Double]
    /// Where the thinking arc's head is, in radians.
    private(set) var arcAngle: Double = 0
    private(set) var lastTime: Double?

    init(phases: [Double] = [0.4, 2.1, 4.4]) {
        self.phases = phases
    }

    /// The level that drives the wobble: the voice while listening (at least 0.25, so the orb
    /// never looks frozen mid-sentence), a fixed hum while thinking, a slow breath otherwise.
    static func drivingLevel(state: JessOrbState, audioLevel: Double, time: Double) -> Double {
        switch state {
        case .listening:
            return 0.25 + 0.75 * min(1, max(0, audioLevel))
        case .thinking:
            return 0.18
        case .idle, .added, .failed:
            return 0.06 + 0.05 * sin(time * 1.5)
        }
    }

    /// Springs pull each mode toward a target set by the level (the mockup's stepModes).
    mutating func step(level: Double, thinking: Bool) {
        for index in 0..<Self.modes.count {
            let target = level * (0.05 / Double(index + 1))
            let pull = (target - amplitudes[index]) * 0.08
            velocities[index] = (velocities[index] + pull) * 0.88
            amplitudes[index] += velocities[index]
            phases[index] += 0.02 + Double(index) * 0.012
        }
        if thinking {
            arcAngle += 0.06
        }
    }

    /// Steps for the time passed since the last call, at 60 per second.
    mutating func advance(to time: Double, state: JessOrbState, audioLevel: Double) {
        guard let previousTime = lastTime else {
            lastTime = time
            settle(state: state, audioLevel: audioLevel)
            return
        }
        let wholeSteps = Int(((time - previousTime) * Self.stepsPerSecond).rounded(.down))
        guard wholeSteps > 0 else {
            return
        }
        let stepCount = min(wholeSteps, Self.maximumStepsPerAdvance)
        let level = Self.drivingLevel(state: state, audioLevel: audioLevel, time: time)
        for _ in 0..<stepCount {
            step(level: level, thinking: state == .thinking)
        }
        lastTime = previousTime + Double(wholeSteps) / Self.stepsPerSecond
    }

    /// The mockup's warm-up: 40 steps so the first still frame already shows the shape.
    mutating func settle(state: JessOrbState, audioLevel: Double) {
        for warmup in 0..<40 {
            let level = Self.drivingLevel(state: state, audioLevel: audioLevel, time: Double(warmup) / 30)
            step(level: level, thinking: false)
        }
    }

    /// How far the outline sits from the circle at an angle, as a fraction of the radius.
    func outlineOffset(at angle: Double, thinking: Bool) -> Double {
        var offset = 0.0
        for index in 0..<Self.modes.count {
            offset += amplitudes[index] * sin(Self.modes[index] * angle + phases[index])
        }
        // While thinking, the wall bulges just ahead of the sweeping arc
        if thinking {
            let distance = atan2(sin(angle - arcAngle), cos(angle - arcAngle))
            offset += 0.05 * exp(-(distance * distance) / 0.12)
        }
        return offset
    }

    func outline(center: CGPoint, radius: Double, thinking: Bool) -> [CGPoint] {
        var points: [CGPoint] = []
        for pointIndex in 0..<Self.outlinePoints {
            let angle = Double(pointIndex) / Double(Self.outlinePoints) * 2 * Double.pi
            let pointRadius = radius * (1 + outlineOffset(at: angle, thinking: thinking))
            points.append(CGPoint(x: center.x + cos(angle) * pointRadius, y: center.y + sin(angle) * pointRadius))
        }
        return points
    }

    /// The core: 0.3 of the body's radius, a little bigger with the voice while listening.
    static func coreRadius(bodyRadius: Double, state: JessOrbState, level: Double) -> Double {
        let growth = state == .listening ? level * 0.08 : 0
        return bodyRadius * (0.3 + growth)
    }
}

/// Measures of the drawing, as fractions of the orb's side (the mockup's drawOrb).
enum JessOrbGeometry {
    static let bodyRadiusFraction = 0.33
    static let ringWidthFraction = 0.02
    static let minimumRingWidth = 1.5
    static let arcRadiusFraction = 1.02
    static let arcTail = 0.55
    static let arcHead = 0.15

    /// The body's soft glow grows a little with the level.
    static func bodyGlowRadius(side: Double, level: Double) -> Double {
        // A canvas shadowBlur is about twice SwiftUI's shadow radius
        side * (0.14 + level * 0.08) / 2
    }
}

/// jess's orb. `level` is the microphone's loudness (0...1) and matters only while listening.
/// With Reduce Motion on, the orb is drawn still; its colours still follow the state.
struct JessOrb: View {
    let state: JessOrbState
    var level: @Sendable () -> Double = JessOrb.silence

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motionBox = JessOrbMotionBox()

    nonisolated static func silence() -> Double {
        0
    }

    /// The orb animates unless Reduce Motion is on.
    static func isAnimated(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(paused: !Self.isAnimated(reduceMotion: reduceMotion))) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let audioLevel = level()
        if Self.isAnimated(reduceMotion: reduceMotion) {
            motionBox.motion.advance(to: time, state: state, audioLevel: audioLevel)
        } else if motionBox.motion.lastTime == nil {
            motionBox.motion.advance(to: 0, state: state, audioLevel: audioLevel)
        }
        let motion = motionBox.motion
        let palette = JessOrbPalette.forScheme(colorScheme)
        let side = Double(min(size.width, size.height))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side * JessOrbGeometry.bodyRadiusFraction
        let thinking = state == .thinking
        let drivingLevel = JessOrbMotion.drivingLevel(state: state, audioLevel: audioLevel, time: time)
        let bodyPath = Self.smoothPath(through: motion.outline(center: center, radius: radius, thinking: thinking))
        let ringWidth = max(JessOrbGeometry.minimumRingWidth, side * JessOrbGeometry.ringWidthFraction)

        // Body: a soft glow around it, then the fill
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: palette.bodyGlow.color, radius: JessOrbGeometry.bodyGlowRadius(side: side, level: drivingLevel)))
            layer.fill(bodyPath, with: .color(palette.body.color))
        }
        // Ring: never changes colour with the result
        context.stroke(bodyPath, with: .color(palette.ring.color), lineWidth: ringWidth)

        if thinking {
            var arcPath = Path()
            arcPath.addArc(center: center, radius: radius * JessOrbGeometry.arcRadiusFraction, startAngle: .radians(motion.arcAngle - JessOrbGeometry.arcTail), endAngle: .radians(motion.arcAngle + JessOrbGeometry.arcHead), clockwise: false)
            // No glow on the thinking arc (founder, 2026-10-22)
            context.stroke(arcPath, with: .color(palette.arc.color), style: StrokeStyle(lineWidth: ringWidth * 1.4, lineCap: .round))
        }

        // Core: crisp and solid, no halo (founder, 2026-10-15: glow max, spread 0)
        let coreRadius = JessOrbMotion.coreRadius(bodyRadius: radius, state: state, level: drivingLevel)
        let coreRect = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
        context.fill(Path(ellipseIn: coreRect), with: .color(palette.coreColor(for: state).color))
    }

    /// A closed curve through the outline points (Catmull-Rom as cubic Béziers, as the Job
    /// Autopilot orb draws its ring).
    static func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        guard count > 2 else {
            return path
        }
        path.move(to: points[0])
        for index in 0..<count {
            let previous = points[(index - 1 + count) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let afterNext = points[(index + 2) % count]
            let firstControl = CGPoint(x: current.x + (next.x - previous.x) / 6, y: current.y + (next.y - previous.y) / 6)
            let secondControl = CGPoint(x: next.x - (afterNext.x - current.x) / 6, y: next.y - (afterNext.y - current.y) / 6)
            path.addCurve(to: next, control1: firstControl, control2: secondControl)
        }
        path.closeSubpath()
        return path
    }
}

/// Holds the motion across frames without making every frame a SwiftUI state change.
@MainActor
final class JessOrbMotionBox {
    var motion = JessOrbMotion()
}
