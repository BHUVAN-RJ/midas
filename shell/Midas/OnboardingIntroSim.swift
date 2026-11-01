import CoreGraphics
import Foundation

// The first-open black hole's physics (founder, 2026-10-31): a port of the approved mockup
// docs/mockups/onboarding-blackhole-v9-2026-10-31.html, numbers in docs/briefs/onboarding-build.md
// sections 3 and 5. Fixed 1/120 s steps, deterministic for a seed, so it can be tested.

/// The eight apps on the intro. `mass` makes heavy ones slower to pull.
struct OnboardingIntroApp: Equatable {
    let name: String
    let glyph: OnboardingGlyph
    let tileHex: String
    let markHex: String
    let mass: CGFloat
}

enum OnboardingGlyph: Equatable {
    case bell, drop, ring, card, check, book, pill, moon
}

/// Every word on the intro (docs/briefs/onboarding-build.md section 1).
enum OnboardingIntroCopy {
    static let prompt = "Touch and Hold"
    static let wordmark = "Midas"
    /// No full stop (founder, final round); "need", not "needed" (founder, 2026-11-01).
    static let line = "The personal touch your apps need"
    /// The line is typed out with a short pause after this part (founder, 2026-11-01).
    static let lineFirstPart = "The personal touch"
    static let button = "Get Started"
}

enum OnboardingIntroSpec {
    /// Tile colours from DESIGN.md 2.3, the founder's pick "Eight": each app its own colour.
    static let apps: [OnboardingIntroApp] = [
        OnboardingIntroApp(name: "Reminders", glyph: .bell, tileHex: "#FF6347", markHex: "#FFFFFF", mass: 1.2),
        OnboardingIntroApp(name: "Water", glyph: .drop, tileHex: "#30D5C8", markHex: "#111111", mass: 0.85),
        OnboardingIntroApp(name: "Habits", glyph: .ring, tileHex: "#FFE600", markHex: "#111111", mass: 1.0),
        OnboardingIntroApp(name: "Money", glyph: .card, tileHex: "#C9F24D", markHex: "#111111", mass: 1.35),
        OnboardingIntroApp(name: "To-Do", glyph: .check, tileHex: "#9CAF88", markHex: "#111111", mass: 0.9),
        OnboardingIntroApp(name: "Study", glyph: .book, tileHex: "#FFBF00", markHex: "#111111", mass: 1.25),
        OnboardingIntroApp(name: "Meds", glyph: .pill, tileHex: "#C41E3A", markHex: "#FFFFFF", mass: 0.8),
        OnboardingIntroApp(name: "Sleep", glyph: .moon, tileHex: "#2E2E2E", markHex: "#FFFFFF", mass: 1.1),
    ]

    /// Where the icons float at first, on the mockup's 402 x 874 pt screen (scaled to the phone).
    static let startPoints: [CGPoint] = [
        CGPoint(x: 92, y: 168), CGPoint(x: 300, y: 132), CGPoint(x: 214, y: 272), CGPoint(x: 74, y: 352),
        CGPoint(x: 318, y: 360), CGPoint(x: 116, y: 620), CGPoint(x: 300, y: 650), CGPoint(x: 206, y: 760),
    ]
    static let designSize = CGSize(width: 402, height: 874)

    static let iconSize: CGFloat = 60
    /// The home grid (SidekickHomeLayout): 4 columns, 20 pt sides, 8 pt between, rows 103 pt apart.
    static let columns = 4
    static let sideInset: CGFloat = 20
    static let columnGap: CGFloat = 8
    static let rowPitch: CGFloat = 103
    /// First row's centre below the safe area's top: 108 pt on iPhone 16 Pro (safe area 62 pt), so
    /// the icon tops sit 16 pt under the status bar like the home screen (founder, 2026-11-01).
    static let firstRowBelowSafeTop: CGFloat = 46

    // 3 s preset (founder's default)
    static let chargeSeconds: CGFloat = 1.4
    static let fullSeconds: CGFloat = 0.18
    static let burstSeconds: CGFloat = 0.28
    static let settleSeconds: CGFloat = 0.5
    /// Blast into place: every icon flies straight from the hole to its slot.
    static var flightSeconds: CGFloat { burstSeconds + settleSeconds }
    static let flyStagger: CGFloat = 0.02
    static let holeRadius: CGFloat = 16
    static let shake: CGFloat = 3
    static let swirl: CGFloat = 1

    // The popup (seconds from the icons landing)
    static let popupWait: CGFloat = 0.9
    static let popupGlass: CGFloat = 1.4
    static let wordFade: CGFloat = 0.7
    static let lineWait: CGFloat = 0.35
    static let buttonWait: CGFloat = 0.45
    static let buttonFade: CGFloat = 0.9

    /// When each word starts, in seconds from the start of the popup.
    static var wordmarkStart: CGFloat { popupGlass * 0.35 }
    static var lineStart: CGFloat { wordmarkStart + wordFade + lineWait }
    static var buttonStart: CGFloat { lineStart + typingSeconds + buttonWait }

    // Typing the line: a letter at a time, a pause after "The personal touch"
    static let secondsPerLetter: CGFloat = 0.045
    static let pauseAfterFirstPart: CGFloat = 0.2
    static var typingSeconds: CGFloat {
        CGFloat(OnboardingIntroCopy.line.count) * secondsPerLetter + pauseAfterFirstPart
    }

    /// The popup: 24 pt sides, 252 pt tall, its top 297 pt down on iPhone 16 Pro (safe area 62 pt).
    /// It stays put when the grid moved up (founder, 2026-11-01).
    static let cardSideInset: CGFloat = 24
    static let cardHeight: CGFloat = 252
    static let cardCorner: CGFloat = 44
    static let cardTopBelowSafeTop: CGFloat = 235

    static let step: CGFloat = 1.0 / 120.0
}

enum OnboardingIntroMode: Equatable {
    case idle
    case charging
    case collapse
    case full
    case burst
    case home
}

struct OnboardingIntroBody {
    let index: Int
    let mass: CGFloat
    var position: CGPoint
    var velocity: CGVector
    var rotation: CGFloat
    var spin: CGFloat
    var phase: CGFloat
    var scale: CGFloat
    var isPolished = false
    var isInside = false
    /// 0 grey, 1 in its colour: fills as it lands
    var colourIn: CGFloat = 0
    var grow: CGFloat = 1
    var drawScale: CGFloat = 1
    var stretch: CGFloat = 1
    var stretchAngle: CGFloat = 0
    var flightStart = CGPoint.zero
    var flightStartRotation: CGFloat = 0
    var flightStartScale: CGFloat = 1
}

/// Small seeded random numbers (mulberry32), so a run can be replayed.
struct OnboardingRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func next() -> CGFloat {
        state = state &+ 0x6D2B79F5
        var mixed = state
        mixed = (mixed ^ (mixed >> 15)) &* (mixed | 1)
        mixed ^= mixed &+ ((mixed ^ (mixed >> 7)) &* (mixed | 61))
        let result = mixed ^ (mixed >> 14)
        return CGFloat(result) / 4_294_967_296
    }
}

/// One run of the intro.
struct OnboardingIntroSim {
    private(set) var size: CGSize
    private(set) var safeTop: CGFloat
    private(set) var mode: OnboardingIntroMode = .idle
    private(set) var modeTime: CGFloat = 0
    private(set) var clock: CGFloat = 0
    private(set) var holdTime: CGFloat = 0
    private(set) var bodies: [OnboardingIntroBody] = []
    private(set) var finger = CGPoint.zero
    private(set) var isFingerDown = false
    private(set) var hole = CGPoint.zero
    private(set) var holeRadius: CGFloat = 0
    private(set) var waveRadius: CGFloat = 0
    private(set) var waveAmplitude: CGFloat = 0
    private(set) var shakeOffset = CGSize.zero
    /// How dark the screen is round the hole, 0..1
    private(set) var dim: CGFloat = 0
    private(set) var flash: CGFloat = 0
    private(set) var labelsAlpha: CGFloat = 0
    /// The haptic rumble's strength, 0..1, and a count of burst taps fired so far
    private(set) var rumble: CGFloat = 0
    private(set) var burstTaps = 0
    /// A new texture for the hole on every press
    private(set) var seed: CGFloat = 3.1
    private var random: OnboardingRandom

    init(size: CGSize, safeTop: CGFloat, seed: UInt32 = 11) {
        self.size = size
        self.safeTop = safeTop
        self.random = OnboardingRandom(seed: seed)
        bodies = makeBodies()
    }

    // MARK: Layout

    func gridSlot(_ index: Int) -> CGPoint {
        let spec = OnboardingIntroSpec.self
        let column = index % spec.columns
        let row = index / spec.columns
        let columnWidth = (size.width - 2 * spec.sideInset - CGFloat(spec.columns - 1) * spec.columnGap) / CGFloat(spec.columns)
        let x = spec.sideInset + columnWidth / 2 + CGFloat(column) * (columnWidth + spec.columnGap)
        let y = safeTop + spec.firstRowBelowSafeTop + CGFloat(row) * spec.rowPitch
        return CGPoint(x: x, y: y)
    }

    var cardFrame: CGRect {
        let spec = OnboardingIntroSpec.self
        let top = safeTop + spec.cardTopBelowSafeTop
        return CGRect(x: spec.cardSideInset, y: top, width: size.width - 2 * spec.cardSideInset, height: spec.cardHeight)
    }

    /// Seconds since the popup started rising (negative before).
    var popupClock: CGFloat {
        guard mode == .home else {
            return -1
        }
        return modeTime - OnboardingIntroSpec.popupWait
    }

    /// The charge, 0..1, while holding.
    var charge: CGFloat {
        if mode == .full {
            return 1
        }
        return Self.clamp01(holdTime / OnboardingIntroSpec.chargeSeconds)
    }

    private func makeBodies() -> [OnboardingIntroBody] {
        var seeded = OnboardingRandom(seed: 11)
        var made: [OnboardingIntroBody] = []
        let spec = OnboardingIntroSpec.self
        for (index, app) in spec.apps.enumerated() {
            let start = spec.startPoints[index]
            let position = CGPoint(x: start.x * size.width / spec.designSize.width, y: start.y * size.height / spec.designSize.height)
            let velocity = CGVector(dx: (seeded.next() - 0.5) * 20, dy: (seeded.next() - 0.5) * 20)
            let rotation = (seeded.next() - 0.5) * 0.4
            let spin = (seeded.next() - 0.5) * 0.3
            let phase = seeded.next() * 2 * .pi
            let scale = 0.86 + seeded.next() * 0.16
            made.append(OnboardingIntroBody(index: index, mass: app.mass, position: position, velocity: velocity, rotation: rotation, spin: spin, phase: phase, scale: scale))
        }
        return made
    }

    mutating func resize(to newSize: CGSize, safeTop newSafeTop: CGFloat) {
        guard newSize != size || newSafeTop != safeTop else {
            return
        }
        size = newSize
        safeTop = newSafeTop
        if mode == .idle {
            bodies = makeBodies()
        }
    }

    // MARK: Touch

    mutating func press(at point: CGPoint) {
        guard mode == .idle else {
            return
        }
        finger = point
        isFingerDown = true
        hole = point
        holdTime = 0
        seed = random.next() * 40
        // Each icon gets a sideways nudge so it falls in on an orbit, not a straight line
        for index in bodies.indices {
            let dx = bodies[index].position.x - point.x
            let dy = bodies[index].position.y - point.y
            let distance = max(hypot(dx, dy), 1)
            let orbit = 70 * OnboardingIntroSpec.swirl / sqrt(bodies[index].mass)
            bodies[index].velocity.dx += (-dy / distance) * orbit
            bodies[index].velocity.dy += (dx / distance) * orbit
        }
        setMode(.charging)
    }

    mutating func moveFinger(to point: CGPoint) {
        guard isFingerDown else {
            return
        }
        finger = point
    }

    mutating func liftFinger() {
        isFingerDown = false
    }

    // MARK: Stepping

    /// Advances by `seconds` in fixed steps.
    mutating func advance(by seconds: CGFloat) {
        let steps = Int((seconds / OnboardingIntroSpec.step).rounded())
        for _ in 0..<max(steps, 0) {
            stepOnce()
        }
    }

    mutating func stepOnce() {
        let step = OnboardingIntroSpec.step
        clock += step
        modeTime += step
        // The hole trails the finger slightly, like it has weight
        let follow = 1 - exp(-16 * step)
        hole.x += (finger.x - hole.x) * follow
        hole.y += (finger.y - hole.y) * follow
        switch mode {
        case .idle:
            stepIdle()
        case .charging:
            stepCharging()
        case .collapse:
            stepCollapse()
        case .full:
            stepFull()
        case .burst:
            stepBurst()
        case .home:
            stepHome()
        }
        flash *= exp(-9 * step)
        // Light comes back after the burst, or when the finger lets go early
        if mode != .charging && mode != .full {
            dim *= exp(-7 * step)
            rumble *= exp(-14 * step)
        }
        updateShake()
        for index in bodies.indices {
            updateLook(of: index)
        }
    }

    private mutating func setMode(_ newMode: OnboardingIntroMode) {
        mode = newMode
        modeTime = 0
    }

    private mutating func stepIdle() {
        for index in bodies.indices {
            applyFloat(to: index)
            keepInside(index, bounce: false)
            integrate(index, drag: 0.9)
        }
        separateBodies()
    }

    private mutating func stepCharging() {
        let step = OnboardingIntroSpec.step
        holdTime += step
        let charge = self.charge
        holeRadius = Self.lerp(6, OnboardingIntroSpec.holeRadius, Self.easeOutCubic(charge))
        var remaining = 0
        for index in bodies.indices where !bodies[index].isInside {
            let pull = gravity(at: bodies[index].position, mass: bodies[index].mass, charge: charge)
            bodies[index].velocity.dx += pull.dx * step
            bodies[index].velocity.dy += pull.dy * step
            // Torque: closer means faster tumbling
            let direction: CGFloat = index % 2 == 0 ? 1 : -1
            bodies[index].spin += (pull.distance < 160 ? 6 : 1) * step * direction
            // Late in the charge the hole wins outright, so the timing always holds
            if charge > 0.6 {
                let lateness = pow((charge - 0.6) / 0.4, 2)
                bodies[index].position.x += (hole.x - bodies[index].position.x) * lateness * 0.06
                bodies[index].position.y += (hole.y - bodies[index].position.y) * lateness * 0.06
            }
            integrate(index, drag: 1 + 2.4 * charge)
            if pull.distance < holeRadius * 1.1 || charge >= 1 {
                bodies[index].isInside = true
            } else {
                remaining += 1
            }
        }
        separateBodies()
        rumble = 0.15 + 0.85 * pow(charge, 1.6)
        dim = pow(charge, 0.9)
        if !isFingerDown {
            startCollapse()
            return
        }
        if charge >= 1 && remaining == 0 {
            setMode(.full)
        }
    }

    /// Let go early: the hole fades and spits everything back out as it was.
    private mutating func startCollapse() {
        setMode(.collapse)
        for index in bodies.indices where bodies[index].isInside {
            let angle = random.next() * 2 * .pi
            bodies[index].isInside = false
            bodies[index].position = CGPoint(x: hole.x + cos(angle) * holeRadius, y: hole.y + sin(angle) * holeRadius)
            bodies[index].velocity = CGVector(dx: cos(angle) * 320, dy: sin(angle) * 320)
        }
        rumble = 0
    }

    private mutating func stepCollapse() {
        let step = OnboardingIntroSpec.step
        holeRadius *= exp(-9 * step)
        for index in bodies.indices {
            keepInside(index, bounce: true)
            integrate(index, drag: 2.5)
            bodies[index].spin *= exp(-2 * step)
        }
        separateBodies()
        if modeTime > 0.6 {
            holeRadius = 0
            holdTime = 0
            setMode(.idle)
        }
    }

    /// Everything is in: the hole tightens and trembles, then lets go.
    private mutating func stepFull() {
        let full = OnboardingIntroSpec.fullSeconds
        holeRadius = OnboardingIntroSpec.holeRadius * (1 - 0.12 * Self.clamp01(modeTime / max(full, 0.01)))
        rumble = 1
        dim = 1
        if modeTime >= full {
            startBurst()
        }
    }

    private mutating func startBurst() {
        setMode(.burst)
        waveRadius = holeRadius
        waveAmplitude = 34
        burstTaps += 1
        rumble = 0
        flash = 0.9
        isFingerDown = false
        for index in bodies.indices {
            bodies[index].isInside = false
            bodies[index].isPolished = true
            bodies[index].colourIn = 0
            bodies[index].flightStart = hole
            bodies[index].position = hole
            bodies[index].flightStartRotation = (random.next() - 0.5) * 2.4
            bodies[index].flightStartScale = bodies[index].scale
            bodies[index].velocity = .zero
            bodies[index].spin = 0
            bodies[index].grow = 0
        }
    }

    /// The blast throws every icon straight to its home slot, fast out and slowing into place.
    private mutating func stepBurst() {
        let step = OnboardingIntroSpec.step
        holeRadius *= exp(-22 * step)
        if holeRadius < 0.3 {
            holeRadius = 0
        }
        advanceWave()
        let flight = OnboardingIntroSpec.flightSeconds
        for index in bodies.indices {
            bodies[index].grow = min(1, bodies[index].grow + step / 0.22)
            let slot = gridSlot(index)
            let progress = Self.clamp01((modeTime - CGFloat(index) * OnboardingIntroSpec.flyStagger) / flight)
            let eased = Self.easeOutQuart(progress)
            bodies[index].position = CGPoint(
                x: Self.lerp(bodies[index].flightStart.x, slot.x, eased),
                y: Self.lerp(bodies[index].flightStart.y, slot.y, eased)
            )
            bodies[index].rotation = bodies[index].flightStartRotation * (1 - eased)
            bodies[index].scale = Self.lerp(bodies[index].flightStartScale, 1, eased)
            fillColourOnLanding(index, slot: slot)
        }
        let lastLanding = flight + OnboardingIntroSpec.flyStagger * CGFloat(bodies.count - 1)
        if modeTime >= lastLanding {
            for index in bodies.indices {
                bodies[index].position = gridSlot(index)
                bodies[index].rotation = 0
                bodies[index].scale = 1
            }
            holeRadius = 0
            setMode(.home)
        }
    }

    private mutating func stepHome() {
        advanceWave()
        for index in bodies.indices {
            fillColourOnLanding(index, slot: gridSlot(index))
        }
        labelsAlpha = min(1, labelsAlpha + OnboardingIntroSpec.step / 0.3)
    }

    private mutating func advanceWave() {
        let step = OnboardingIntroSpec.step
        waveRadius += 1500 * step
        waveAmplitude *= exp(-3.2 * step)
    }

    /// An icon takes its colour once it is nearly in its slot, over a quarter second, and keeps it.
    private mutating func fillColourOnLanding(_ index: Int, slot: CGPoint) {
        let away = hypot(slot.x - bodies[index].position.x, slot.y - bodies[index].position.y)
        if away < 10 || bodies[index].colourIn > 0 {
            bodies[index].colourIn = min(1, bodies[index].colourIn + OnboardingIntroSpec.step / 0.25)
        }
    }

    // MARK: Forces

    private func gravity(at point: CGPoint, mass: CGFloat, charge: CGFloat) -> (dx: CGFloat, dy: CGFloat, distance: CGFloat) {
        let dx = hole.x - point.x
        let dy = hole.y - point.y
        let distance = max(hypot(dx, dy), 0.001)
        let strength = 2200 * (0.25 + 3 * charge * charge)
        let magnitude = (strength / mass) * (100 / (distance + 30))
        let swirl = OnboardingIntroSpec.swirl * 0.42 * magnitude
        let accelerationX = (dx / distance) * magnitude + (-dy / distance) * swirl
        let accelerationY = (dy / distance) * magnitude + (dx / distance) * swirl
        return (accelerationX, accelerationY, distance)
    }

    private mutating func applyFloat(to index: Int) {
        let step = OnboardingIntroSpec.step
        let phase = bodies[index].phase
        bodies[index].velocity.dx += sin(clock * 0.7 + phase) * 16 * step
        bodies[index].velocity.dy += cos(clock * 0.55 + phase * 1.3) * 16 * step
        bodies[index].spin += (sin(clock * 0.4 + phase) * 0.15 - bodies[index].spin) * step
    }

    private mutating func keepInside(_ index: Int, bounce: Bool) {
        let step = OnboardingIntroSpec.step
        let margin: CGFloat = 34
        let top = safeTop + 14
        let bottom = size.height - 40
        if bounce {
            // Walls are hard when icons are thrown: they bounce back in at half speed
            if bodies[index].position.x < margin {
                bodies[index].position.x = margin
                bodies[index].velocity.dx = abs(bodies[index].velocity.dx) * 0.5
            }
            if bodies[index].position.x > size.width - margin {
                bodies[index].position.x = size.width - margin
                bodies[index].velocity.dx = -abs(bodies[index].velocity.dx) * 0.5
            }
            if bodies[index].position.y < top {
                bodies[index].position.y = top
                bodies[index].velocity.dy = abs(bodies[index].velocity.dy) * 0.5
            }
            if bodies[index].position.y > bottom {
                bodies[index].position.y = bottom
                bodies[index].velocity.dy = -abs(bodies[index].velocity.dy) * 0.5
            }
            return
        }
        // Soft walls while floating
        let push: CGFloat = 60 * step * 0.2
        let left = margin + 10
        let right = size.width - margin - 10
        if bodies[index].position.x < left {
            bodies[index].velocity.dx += push * (left - bodies[index].position.x)
        }
        if bodies[index].position.x > right {
            bodies[index].velocity.dx -= push * (bodies[index].position.x - right)
        }
        if bodies[index].position.y < top + 10 {
            bodies[index].velocity.dy += push * (top + 10 - bodies[index].position.y)
        }
        if bodies[index].position.y > bottom - 10 {
            bodies[index].velocity.dy -= push * (bodies[index].position.y - (bottom - 10))
        }
    }

    private mutating func integrate(_ index: Int, drag: CGFloat) {
        let step = OnboardingIntroSpec.step
        let damping = exp(-drag * step)
        bodies[index].velocity.dx *= damping
        bodies[index].velocity.dy *= damping
        let speed = hypot(bodies[index].velocity.dx, bodies[index].velocity.dy)
        let maxSpeed: CGFloat = 1600
        if speed > maxSpeed {
            bodies[index].velocity.dx *= maxSpeed / speed
            bodies[index].velocity.dy *= maxSpeed / speed
        }
        bodies[index].position.x += bodies[index].velocity.dx * step
        bodies[index].position.y += bodies[index].velocity.dy * step
        bodies[index].rotation += bodies[index].spin * step
    }

    /// Icons are solid: overlapping ones push apart, heavier ones move less.
    private mutating func separateBodies() {
        for first in bodies.indices where !bodies[first].isInside {
            for second in bodies.indices where second > first && !bodies[second].isInside {
                let dx = bodies[second].position.x - bodies[first].position.x
                let dy = bodies[second].position.y - bodies[first].position.y
                let distance = max(hypot(dx, dy), 0.001)
                let minimum = 28 * (bodies[first].drawScale + bodies[second].drawScale)
                guard distance < minimum else {
                    continue
                }
                let overlap = (minimum - distance) * 0.5
                let normalX = dx / distance
                let normalY = dy / distance
                let totalMass = bodies[first].mass + bodies[second].mass
                let shareFirst = bodies[second].mass / totalMass
                let shareSecond = bodies[first].mass / totalMass
                bodies[first].position.x -= normalX * overlap * shareFirst
                bodies[first].position.y -= normalY * overlap * shareFirst
                bodies[second].position.x += normalX * overlap * shareSecond
                bodies[second].position.y += normalY * overlap * shareSecond
                let relative = (bodies[second].velocity.dx - bodies[first].velocity.dx) * normalX + (bodies[second].velocity.dy - bodies[first].velocity.dy) * normalY
                if relative < 0 {
                    let impulse = -relative * 0.8
                    bodies[first].velocity.dx -= normalX * impulse * shareFirst
                    bodies[first].velocity.dy -= normalY * impulse * shareFirst
                    bodies[second].velocity.dx += normalX * impulse * shareSecond
                    bodies[second].velocity.dy += normalY * impulse * shareSecond
                }
            }
        }
    }

    /// Near the hole an icon shrinks and stretches toward it (tidal pull).
    private mutating func updateLook(of index: Int) {
        let grown = bodies[index].isPolished ? Self.lerp(0.25, 1, Self.easeOutCubic(bodies[index].grow)) : 1
        bodies[index].drawScale = bodies[index].scale * grown
        bodies[index].stretch = 1
        let holeLive = holeRadius > 0.5 && (mode == .charging || mode == .full)
        guard holeLive else {
            return
        }
        let dx = bodies[index].position.x - hole.x
        let dy = bodies[index].position.y - hole.y
        let distance = hypot(dx, dy)
        let near = Self.clamp01(1 - (distance - holeRadius) / 130)
        bodies[index].drawScale *= Self.lerp(1, 0.3, near * near)
        bodies[index].stretch = 1 + 1.4 * near * near
        bodies[index].stretchAngle = atan2(dy, dx)
    }

    private mutating func updateShake() {
        var amplitude: CGFloat = 0
        switch mode {
        case .charging:
            amplitude = OnboardingIntroSpec.shake * charge * charge
        case .full:
            amplitude = OnboardingIntroSpec.shake * 1.4
        case .burst:
            let kick = Self.clamp01(modeTime / 0.35)
            amplitude = OnboardingIntroSpec.shake * 2.2 * (1 - kick) * (1 - kick)
        default:
            amplitude = 0
        }
        let x = amplitude * (sin(clock * 71.3) * 0.6 + sin(clock * 43.1 + 1.7) * 0.4)
        let y = amplitude * (sin(clock * 67.9 + 0.4) * 0.6 + sin(clock * 39.7 + 2.2) * 0.4)
        shakeOffset = CGSize(width: x, height: y)
    }

    // MARK: Small maths

    static func clamp01(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }

    static func lerp(_ from: CGFloat, _ to: CGFloat, _ amount: CGFloat) -> CGFloat {
        from + (to - from) * amount
    }

    static func easeOutCubic(_ value: CGFloat) -> CGFloat {
        let inverse = 1 - value
        return 1 - inverse * inverse * inverse
    }

    static func easeOutQuart(_ value: CGFloat) -> CGFloat {
        let inverse = 1 - value
        return 1 - inverse * inverse * inverse * inverse
    }

    /// Slow in, slow out: the popup arrives without a push
    static func easeInOutSine(_ value: CGFloat) -> CGFloat {
        0.5 - 0.5 * cos(.pi * value)
    }
}
