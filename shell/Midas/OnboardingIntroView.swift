import SwiftUI
import UIKit

// The first-open intro (founder, 2026-10-31; docs/briefs/onboarding-build.md): grey apps float;
// touch and hold opens a black hole under the finger that pulls them in; it bursts and throws each
// one straight into its home slot, where it takes its colour; then a glass popup: "Midas", the
// line, then sign in: a name, Get Started, Sign In (founder, 2026-11-01). The icons blur a little
// behind the popup. With Reduce Motion or VoiceOver: no hole, the icons cross-fade in place.

/// How far each part of the popup has come in, 0..1.
struct OnboardingPopupLook: Equatable {
    var glass: CGFloat = 0
    var wordmark: CGFloat = 0
    var line: CGFloat = 0
    var button: CGFloat = 0

    /// The full motion version, from seconds since the popup started (popupClock).
    static func motion(at popupClock: CGFloat) -> OnboardingPopupLook {
        let spec = OnboardingIntroSpec.self
        guard popupClock >= 0 else {
            return OnboardingPopupLook()
        }
        let glass = progress(popupClock, start: 0, length: spec.popupGlass)
        let wordmark = progress(popupClock, start: spec.wordmarkStart, length: spec.wordFade)
        // The line is typed, not faded: it shows as soon as its first letter does
        let line: CGFloat = popupClock > spec.lineStart ? 1 : 0
        let button = progress(popupClock, start: spec.buttonStart, length: spec.buttonFade)
        return OnboardingPopupLook(glass: glass, wordmark: wordmark, line: line, button: button)
    }

    /// The blur on the icons behind the popup: grows with "Midas" coming in.
    var backBlur: CGFloat {
        OnboardingIntroSpec.backBlur * wordmark
    }

    /// Slow in, slow out progress of one beat.
    static func progress(_ clock: CGFloat, start: CGFloat, length: CGFloat) -> CGFloat {
        let linear = OnboardingIntroSim.clamp01((clock - start) / max(length, 0.001))
        return OnboardingIntroSim.easeInOutSine(linear)
    }
}

/// How much of the line is typed: every letter shows in the calm version; in the motion version
/// letters appear one at a time from lineStart, with a pause after the first part.
enum OnboardingLineTyping {
    static var fullCount: Int {
        OnboardingIntroCopy.line.count
    }

    /// Letters showing at `popupClock` seconds into the popup.
    static func letters(at popupClock: CGFloat) -> Int {
        let spec = OnboardingIntroSpec.self
        let elapsed = popupClock - spec.lineStart
        guard elapsed > 0 else {
            return 0
        }
        let firstCount = OnboardingIntroCopy.lineFirstPart.count
        let firstDone = CGFloat(firstCount) * spec.secondsPerLetter
        if elapsed < firstDone {
            return Int(elapsed / spec.secondsPerLetter) + 1
        }
        let afterPause = elapsed - firstDone - spec.pauseAfterFirstPart
        guard afterPause >= 0 else {
            return firstCount
        }
        let secondCount = Int(afterPause / spec.secondsPerLetter) + 1
        return min(fullCount, firstCount + secondCount)
    }

    /// The typed part and the rest, which is laid out but clear so the line never shifts.
    static func split(letters: Int) -> (typed: String, rest: String) {
        let line = OnboardingIntroCopy.line
        let cut = line.index(line.startIndex, offsetBy: max(0, min(letters, line.count)))
        return (String(line[..<cut]), String(line[cut...]))
    }
}

/// The Reduce Motion version (brief section 9), from seconds since the tap.
enum OnboardingCalmTimeline {
    static let iconFade: CGFloat = 0.3
    static let iconStagger: CGFloat = 0.04
    static let labelFade: CGFloat = 0.3
    static let popupFade: CGFloat = 0.6
    static let buttonDelay: CGFloat = 0.6

    static var iconsDone: CGFloat {
        CGFloat(OnboardingIntroSpec.apps.count - 1) * iconStagger + iconFade
    }

    static var popupStart: CGFloat {
        iconsDone + labelFade
    }

    static func colourIn(icon index: Int, at elapsed: CGFloat) -> CGFloat {
        OnboardingPopupLook.progress(elapsed, start: CGFloat(index) * iconStagger, length: iconFade)
    }

    static func labels(at elapsed: CGFloat) -> CGFloat {
        OnboardingPopupLook.progress(elapsed, start: iconsDone, length: labelFade)
    }

    static func popup(at elapsed: CGFloat) -> OnboardingPopupLook {
        let fade = OnboardingPopupLook.progress(elapsed, start: popupStart, length: popupFade)
        let button = OnboardingPopupLook.progress(elapsed, start: popupStart + buttonDelay, length: popupFade)
        return OnboardingPopupLook(glass: fade, wordmark: fade, line: fade, button: button)
    }
}

/// Runs the sim against the clock. A plain class, read and advanced once per frame by the
/// TimelineView; its changes need no view updates of their own.
@MainActor
final class OnboardingIntroDriver {
    private(set) var sim = OnboardingIntroSim(size: OnboardingIntroSpec.designSize, safeTop: 62)
    private(set) var promptAlpha: CGFloat = 1
    /// The icons, drawn once. Kept here, not in view state: the canvas closure runs outside the
    /// view's body and could read a stale empty copy of view state (seen 2026-11-01).
    var images = OnboardingIconImages()
    /// Set when the Reduce Motion version starts
    private(set) var calmStart: Date?
    private(set) var calmElapsed: CGFloat = 0
    private var lastDate: Date?
    private var leftover: CGFloat = 0
    private var heardBurstTaps = 0
    private var hapticsEngine: OnboardingHaptics?

    private var haptics: OnboardingHaptics {
        if let hapticsEngine {
            return hapticsEngine
        }
        let made = OnboardingHaptics()
        hapticsEngine = made
        return made
    }

    func advance(to date: Date, size: CGSize, safeTop: CGFloat) {
        sim.resize(to: size, safeTop: safeTop)
        // A long gap (app in the background) is not replayed: at most 50 ms per frame
        let gap = lastDate.map(date.timeIntervalSince) ?? 0
        lastDate = date
        let frame = min(max(CGFloat(gap), 0), 0.05)
        if let calmStart {
            calmElapsed = CGFloat(date.timeIntervalSince(calmStart))
            return
        }
        leftover += frame
        pressForDemo(size: size)
        let step = OnboardingIntroSpec.step
        while leftover >= step {
            sim.stepOnce()
            leftover -= step
        }
        // "Touch and Hold" goes as soon as the hole opens and does not come back after the burst
        let promptTarget: CGFloat = sim.mode == .idle && sim.burstTaps == 0 ? 1 : 0
        promptAlpha += (promptTarget - promptAlpha) * min(1, frame * 10)
        playHaptics()
    }

    /// A DEBUG run with the launch argument `-MidasIntroDemo YES` holds the middle of the screen
    /// one second after launch, for simulator screenshots (a simulator cannot be held from a
    /// script). Never in a release build.
    private func pressForDemo(size: CGSize) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "MidasIntroDemo"), sim.mode == .idle, sim.burstTaps == 0 else {
            return
        }
        guard sim.clock > 1 else {
            return
        }
        sim.press(at: CGPoint(x: size.width / 2, y: size.height * 0.55))
        #endif
    }

    private func playHaptics() {
        if sim.burstTaps != heardBurstTaps {
            heardBurstTaps = sim.burstTaps
            haptics.burst()
            return
        }
        let holding = sim.mode == .charging || sim.mode == .full
        haptics.setRumble(holding ? sim.rumble : 0)
    }

    func press(at point: CGPoint) {
        sim.press(at: point)
    }

    func moveFinger(to point: CGPoint) {
        sim.moveFinger(to: point)
    }

    func liftFinger() {
        sim.liftFinger()
        if sim.mode == .charging {
            // Let go early: stop at once, no tap
            haptics.stopRumble()
        }
    }

    func startCalm(at date: Date) {
        guard calmStart == nil else {
            return
        }
        calmStart = date
        promptAlpha = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The popup's look this frame, for either version.
    var popupLook: OnboardingPopupLook {
        if calmStart != nil {
            return OnboardingCalmTimeline.popup(at: calmElapsed)
        }
        return OnboardingPopupLook.motion(at: sim.popupClock)
    }

    /// Letters of the line showing this frame: all of them in the calm version.
    var lineLetters: Int {
        if calmStart != nil {
            return OnboardingLineTyping.fullCount
        }
        return OnboardingLineTyping.letters(at: sim.popupClock)
    }
}

struct OnboardingIntroView: View {
    let auth: AuthModel
    /// Called before the passkey sheet, so the teaching cards follow the sign in
    let onSignInStarted: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var driver = OnboardingIntroDriver()
    @State private var isCalmStarted = false
    @State private var isFingerDown = false
    @State private var name = ""
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isNameFocused: Bool

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    /// The key window's top safe area (status bar and Dynamic Island), 0 if there is no window.
    private static func windowSafeTop() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        for scene in scenes {
            guard let windowScene = scene as? UIWindowScene else {
                continue
            }
            for window in windowScene.windows where window.isKeyWindow {
                return window.safeAreaInsets.top
            }
        }
        return 0
    }

    /// Reduce Motion and VoiceOver both get the calm version.
    private var isCalm: Bool {
        reduceMotion || voiceOver
    }

    var body: some View {
        GeometryReader(content: screen)
            .ignoresSafeArea()
            .background(tokens.paper.color)
            .onAppear(perform: renderImages)
            .onChange(of: colorScheme, renderImages)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification), perform: keyboardMoved)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification), perform: keyboardHidden)
    }

    /// The view ignores the keyboard's safe area (the grid must not move), so the popup lifts itself
    private func keyboardMoved(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let screenHeight = UIScreen.main.bounds.height
        withAnimation(.easeOut(duration: 0.25)) {
            keyboardHeight = max(0, screenHeight - frame.minY)
        }
    }

    private func keyboardHidden(_ notification: Notification) {
        withAnimation(.easeOut(duration: 0.25)) {
            keyboardHeight = 0
        }
    }

    private func screen(_ geometry: GeometryProxy) -> some View {
        let size = geometry.size
        // The view ignores the safe area, so its own proxy reports 0: read the window's as well
        let safeTop = max(geometry.safeAreaInsets.top, Self.windowSafeTop())
        return TimelineView(.animation) { timeline in
            frame(at: timeline.date, size: size, safeTop: safeTop)
        }
    }

    @ViewBuilder
    private func frame(at date: Date, size: CGSize, safeTop: CGFloat) -> some View {
        // Advancing here keeps the sim, the drawing and the shader on the same frame
        let _ = driver.advance(to: date, size: size, safeTop: safeTop)
        let sim = driver.sim
        let look = driver.popupLook
        let lift = OnboardingPopupLift.offset(card: sim.cardFrame, screenHeight: size.height, keyboardHeight: keyboardHeight)
        let liftedCard = sim.cardFrame.offsetBy(dx: 0, dy: lift)
        ZStack(alignment: .topLeading) {
            scene(size: size, at: date, blur: look.backBlur)
            popup(look: look, frame: liftedCard)
            errorLine(below: liftedCard)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: The scene under the hole

    private func scene(size: CGSize, at date: Date, blur: CGFloat) -> some View {
        let sim = driver.sim
        let isShaderOn = driver.calmStart == nil && (sim.holeRadius > 0.3 || sim.dim > 0.01 || sim.flash > 0.01 || sim.waveAmplitude > 0.3)
        // In the last tenth of a second before the burst the hole trembles (5% at about 7 Hz)
        let pulse: CGFloat = sim.mode == .full ? 1 + 0.05 * sin(sim.modeTime * 2 * .pi * 7) : 1
        let shader = ShaderLibrary.midasBlackHole(
            .float2(size),
            .float2(sim.hole),
            .float(sim.holeRadius * pulse / 2.6),
            .float(sim.charge),
            .float(sim.clock),
            .float(sim.seed),
            .float(OnboardingIntroSpec.swirl),
            .float(sim.dim),
            .float(sim.flash),
            .float(sim.waveRadius),
            .float(sim.waveAmplitude),
            .color(tokens.paper.color),
            .color(tokens.ink.color)
        )
        let reach = CGSize(width: size.width / 2, height: size.height / 2)
        return Canvas(renderer: sceneRenderer(at: date, blur: blur))
            .frame(width: size.width, height: size.height)
            .layerEffect(shader, maxSampleOffset: reach, isEnabled: isShaderOn)
            .contentShape(Rectangle())
            .gesture(touchGesture)
            .accessibilityElement()
            .accessibilityLabel(OnboardingIntroCopy.prompt)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, startCalmNow)
            .accessibilityHidden(isCalmStarted)
    }

    private func sceneRenderer(at date: Date, blur: CGFloat) -> (inout GraphicsContext, CGSize) -> Void {
        let sim = driver.sim
        let calmStart = driver.calmStart
        let calmElapsed = driver.calmElapsed
        let promptAlpha = driver.promptAlpha
        let images = driver.images
        let isCalm = self.isCalm
        let tokens = self.tokens
        func drawScene(_ context: inout GraphicsContext, _ size: CGSize) {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tokens.paper.color))
            guard images.isReady else {
                return
            }
            // A small blur on the icons once "Midas" is up (founder, 2026-11-01)
            var iconContext = context
            if blur > 0.01 {
                iconContext.addFilter(.blur(radius: blur))
            }
            drawIcons(in: iconContext)
            let breath = 0.7 + 0.3 * sin(CGFloat(date.timeIntervalSinceReferenceDate) * 2 * .pi / 2.9)
            OnboardingSceneDrawing.drawPrompt(in: context, size: size, alpha: promptAlpha * breath, ink2: tokens.ink2.color)
        }
        func drawIcons(in context: GraphicsContext) {
            if isCalm {
                OnboardingSceneDrawing.drawCalm(in: context, sim: sim, images: images, elapsed: calmStart == nil ? -1 : calmElapsed, ink: tokens.ink.color)
            } else {
                OnboardingSceneDrawing.drawMotion(in: context, sim: sim, images: images, ink: tokens.ink.color)
            }
        }
        return drawScene
    }

    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged(touchMoved)
            .onEnded(touchEnded)
    }

    private func touchMoved(_ value: DragGesture.Value) {
        // A touch outside the popup puts the keyboard away
        if isNameFocused {
            isNameFocused = false
            return
        }
        if isCalm {
            startCalmNow()
            return
        }
        if isFingerDown {
            driver.moveFinger(to: value.location)
            return
        }
        isFingerDown = true
        driver.press(at: value.location)
    }

    private func touchEnded(_ value: DragGesture.Value) {
        isFingerDown = false
        driver.liftFinger()
    }

    private func startCalmNow() {
        driver.startCalm(at: Date())
        isCalmStarted = true
    }

    private func renderImages() {
        driver.images = OnboardingIconImages.render(for: colorScheme, displayScale: displayScale)
    }

    // MARK: The popup

    private func popup(look: OnboardingPopupLook, frame: CGRect) -> some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingIntroSpec.cardCorner, style: .continuous)
        let isCalmPopup = driver.calmStart != nil
        // The motion version grows the glass 98.5% to 100%; the calm one only fades
        let scale = isCalmPopup ? 1 : 0.985 + 0.015 * look.glass
        return OnboardingPopupContent(
            look: look,
            lineLetters: driver.lineLetters,
            tokens: tokens,
            name: $name,
            isNameFocused: $isNameFocused,
            isWorking: auth.isWorking,
            onGetStarted: createAccount,
            onSignIn: signIn
        )
            .frame(width: frame.width, height: frame.height)
            .background(popupTint(shape: shape))
            .onboardingGlass(in: shape)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 30, x: 0, y: 14)
            .scaleEffect(scale)
            .opacity(look.glass)
            .allowsHitTesting(look.button > 0.5)
            .offset(x: frame.minX, y: frame.minY)
    }

    /// The sign-in error (AuthCopy), just under the popup.
    @ViewBuilder
    private func errorLine(below card: CGRect) -> some View {
        if let message = auth.errorMessage, driver.popupLook.button > 0.5 {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(width: card.width)
                .multilineTextAlignment(.center)
                .offset(x: card.minX, y: card.maxY + 12)
        }
    }

    private func createAccount() {
        let enteredName = name
        isNameFocused = false
        onSignInStarted()
        Task {
            await auth.createAccount(name: enteredName)
        }
    }

    private func signIn() {
        isNameFocused = false
        onSignInStarted()
        Task {
            await auth.signInWithPasskey()
        }
    }

    /// Less see-through than plain glass (founder): a paper wash of about 70% over the frost.
    private func popupTint(shape: RoundedRectangle) -> some View {
        let wash = colorScheme == .dark ? Color(.sRGB, red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255) : Color.white
        return shape.fill(wash.opacity(0.7))
    }
}

/// The words and the sign in inside the popup.
private struct OnboardingPopupContent: View {
    let look: OnboardingPopupLook
    let lineLetters: Int
    let tokens: RepairTokens
    @Binding var name: String
    var isNameFocused: FocusState<Bool>.Binding
    let isWorking: Bool
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The hand's "s" swings past the end of its own text box and the box clips it: a thin
            // space each side widens the box and keeps the word centred (padding alone did not)
            Text("\u{2009}" + OnboardingIntroCopy.wordmark + "\u{2009}")
                .font(.custom(MakeWelcomeSpec.handFontName, size: 76))
                .foregroundStyle(tokens.ink.color)
                .accessibilityLabel(OnboardingIntroCopy.wordmark)
                .padding(.horizontal, 16)
                .opacity(look.wordmark)
                .offset(y: 6 * (1 - look.wordmark))
            typedLine
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                // VoiceOver reads the whole line, whatever is typed so far
                .accessibilityLabel(OnboardingIntroCopy.line)
                .padding(.top, 4)
                .padding(.horizontal, 22)
                .opacity(look.line)
                .offset(y: 4 * (1 - look.line))
            Spacer(minLength: 0)
            signInForm
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                .opacity(look.button)
                .offset(y: 6 * (1 - look.button))
        }
        .padding(.top, 34)
    }

    /// A name, Get Started (off until a name is typed), Sign In for returning users.
    private var signInForm: some View {
        VStack(spacing: 10) {
            TextField(OnboardingIntroCopy.namePlaceholder, text: $name)
                .focused(isNameFocused)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .onSubmit(submitName)
                .font(.system(size: 17))
                .padding(.horizontal, 20)
                .frame(height: 50)
                .background(tokens.paper.color.opacity(0.7), in: Capsule())
                .overlay(Capsule().stroke(tokens.ink.color.opacity(0.08), lineWidth: 1))
            Button(action: onGetStarted) {
                Text(OnboardingIntroCopy.button)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.paper.color)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(tokens.ink.color, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canGetStarted)
            .opacity(canGetStarted ? 1 : 0.35)
            Button(action: onSignIn) {
                Text(OnboardingIntroCopy.signIn)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink.color)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
    }

    private var canGetStarted: Bool {
        OnboardingSignInRules.canGetStarted(name: name, isWorking: isWorking)
    }

    private func submitName() {
        if canGetStarted {
            onGetStarted()
        }
    }

    /// The typed letters in ink 2, the rest clear: the whole line is laid out from the start.
    private var typedLine: Text {
        let parts = OnboardingLineTyping.split(letters: lineLetters)
        let typed = Text(parts.typed).foregroundStyle(tokens.ink2.color)
        let rest = Text(parts.rest).foregroundStyle(Color.clear)
        return typed + rest
    }
}

/// Get Started needs a name, as on the welcome screen.
enum OnboardingSignInRules {
    static func canGetStarted(name: String, isWorking: Bool) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isWorking
    }
}

/// How far the popup lifts so its bottom clears the keyboard (0 with the keyboard down).
enum OnboardingPopupLift {
    static func offset(card: CGRect, screenHeight: CGFloat, keyboardHeight: CGFloat) -> CGFloat {
        guard keyboardHeight > 0 else {
            return 0
        }
        let highestBottom = screenHeight - keyboardHeight - OnboardingIntroSpec.cardAboveKeyboard
        return min(0, highestBottom - card.maxY)
    }
}

private extension View {
    /// Liquid Glass on iOS 26; a frosted material before it.
    @ViewBuilder
    func onboardingGlass(in shape: RoundedRectangle) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// Drawing the icons, labels and prompt into the scene's canvas.
enum OnboardingSceneDrawing {
    static func drawMotion(in context: GraphicsContext, sim: OnboardingIntroSim, images: OnboardingIconImages, ink: Color) {
        var shaken = context
        shaken.translateBy(x: sim.shakeOffset.width, y: sim.shakeOffset.height)
        if sim.labelsAlpha > 0 {
            drawLabels(in: shaken, sim: sim, alpha: sim.labelsAlpha, ink: ink)
        }
        for body in sim.bodies where !body.isInside {
            drawBody(body, in: shaken, images: images)
        }
    }

    /// Reduce Motion: grey icons sit in their slots and cross-fade to colour after the tap.
    static func drawCalm(in context: GraphicsContext, sim: OnboardingIntroSim, images: OnboardingIconImages, elapsed: CGFloat, ink: Color) {
        let unit = OnboardingIntroSpec.iconSize
        let span = unit * OnboardingIconArt.polishedSpan
        for index in OnboardingIntroSpec.apps.indices {
            let slot = sim.gridSlot(index)
            let colour = elapsed < 0 ? 0 : OnboardingCalmTimeline.colourIn(icon: index, at: elapsed)
            let plainRect = CGRect(x: slot.x - unit / 2, y: slot.y - unit / 2, width: unit, height: unit)
            let polishedRect = CGRect(x: slot.x - span / 2, y: slot.y - span / 2, width: span, height: span)
            var plainContext = context
            plainContext.opacity = 1 - colour
            plainContext.draw(images.plain[index], in: plainRect)
            var colourContext = context
            colourContext.opacity = colour
            colourContext.draw(images.colour[index], in: polishedRect)
        }
        if elapsed >= 0 {
            drawLabels(in: context, sim: sim, alpha: OnboardingCalmTimeline.labels(at: elapsed), ink: ink)
        }
    }

    private static func drawBody(_ body: OnboardingIntroBody, in context: GraphicsContext, images: OnboardingIconImages) {
        let unit = OnboardingIntroSpec.iconSize
        var placed = context
        placed.translateBy(x: body.position.x, y: body.position.y)
        if body.stretch > 1.001 {
            // Tidal pull: longer toward the hole, thinner across it
            placed.rotate(by: .radians(body.stretchAngle))
            placed.scaleBy(x: body.stretch, y: 1 / sqrt(body.stretch))
            placed.rotate(by: .radians(-body.stretchAngle))
        }
        placed.rotate(by: .radians(body.rotation))
        placed.scaleBy(x: body.drawScale, y: body.drawScale)
        guard body.isPolished else {
            placed.draw(images.plain[body.index], in: CGRect(x: -unit / 2, y: -unit / 2, width: unit, height: unit))
            return
        }
        let span = unit * OnboardingIconArt.polishedSpan
        let rect = CGRect(x: -span / 2, y: -span / 2, width: span, height: span)
        var greyContext = placed
        greyContext.opacity = 1 - body.colourIn
        greyContext.draw(images.greyGlass[body.index], in: rect)
        var colourContext = placed
        colourContext.opacity = body.colourIn
        colourContext.draw(images.colour[body.index], in: rect)
    }

    private static func drawLabels(in context: GraphicsContext, sim: OnboardingIntroSim, alpha: CGFloat, ink: Color) {
        var faded = context
        faded.opacity = alpha
        for (index, app) in OnboardingIntroSpec.apps.enumerated() {
            let slot = sim.gridSlot(index)
            let label = Text(app.name).font(.caption).foregroundStyle(ink)
            faded.draw(label, at: CGPoint(x: slot.x, y: slot.y + OnboardingIntroSpec.iconSize / 2 + 12))
        }
    }

    static func drawPrompt(in context: GraphicsContext, size: CGSize, alpha: CGFloat, ink2: Color) {
        guard alpha > 0.01 else {
            return
        }
        var faded = context
        faded.opacity = alpha
        let prompt = Text(OnboardingIntroCopy.prompt).font(.system(size: 17, weight: .semibold)).foregroundStyle(ink2)
        faded.draw(prompt, at: CGPoint(x: size.width / 2, y: size.height / 2))
    }
}
