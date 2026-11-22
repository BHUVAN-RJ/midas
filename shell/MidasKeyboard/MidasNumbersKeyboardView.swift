// Build 41: the numbers-first keyboard (TEST BUILD, founder 2026-11-22; branch agent/dictation-test,
// never merged; docs/briefs/dictation-keyboard-test.md, "Build 41"). Wispr Flow's keyboard is the
// reference: a top bar (undo left; ✕ right while Apple listens), then 1–0, the symbol row, #+= with
// . , ? ! ' and ⌫, then ABC · space · return. ABC goes to the next keyboard. While Apple's dictation
// runs, the listening view (jess's orb, the words so far, APPLE MIC) slides over the keys.
import SwiftUI

struct MidasNumbersKeyboard: View {
    let model: MidasKeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: DictationKeyboardMotion {
        DictationKeyboardMotion.forReduceMotion(reduceMotion)
    }

    private var animation: Animation {
        motion.slides ? .spring(duration: motion.duration, bounce: motion.bounce) : .easeInOut(duration: motion.duration)
    }

    private var coverTransition: AnyTransition {
        motion.slides ? .move(edge: .bottom).combined(with: .opacity) : .opacity
    }

    var body: some View {
        VStack(spacing: 0) {
            MidasTopBar(model: model)
                .frame(height: DictationKeyboardExperienceConstants.topBarHeight)
            ZStack {
                if model.appleCovering {
                    MidasAppleListeningView(model: model)
                        .transition(coverTransition)
                } else {
                    MidasNumberKeys(model: model)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .animation(animation, value: model.appleCovering)
    }
}

// MARK: Top bar

struct MidasTopBar: View {
    let model: MidasKeyboardModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            MidasBarButton(systemImage: "arrow.uturn.backward", accessibility: "Undo", enabled: model.undo.canUndo,
                           pressed: model.topBarPressed, action: model.undoLast)
            Spacer()
            if model.showsCancel {
                MidasBarButton(systemImage: "xmark", accessibility: "Cancel", enabled: true, pressed: model.topBarPressed, action: model.cancelApple)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .foregroundStyle(MidasKeyColors.label(colorScheme))
    }
}

/// A round top-bar button: 44 pt tap target, a 34 pt circle.
struct MidasBarButton: View {
    let systemImage: String
    let accessibility: String
    let enabled: Bool
    let pressed: () -> Void
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(MidasKeyColors.special(colorScheme), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(MidasPressReportingStyle(pressed: pressed))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(accessibility)
    }
}

/// Reports touch down (sound and haptic as the finger lands, as Apple's keyboard), dims while held.
struct MidasPressReportingStyle: ButtonStyle {
    let pressed: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChange(of: configuration.isPressed, initial: false) { _, isPressed in
                if isPressed {
                    pressed()
                }
            }
    }
}

// MARK: Keys

struct MidasNumberKeys: View {
    let model: MidasKeyboardModel

    var body: some View {
        GeometryReader { proxy in
            keyRows(width: proxy.size.width)
        }
        .padding(.top, 4)
    }

    /// One standard key's width: ten keys and their gaps fill the row (Apple's sizes on iPhone 16 Pro).
    private func unitWidth(_ totalWidth: CGFloat) -> CGFloat {
        let usable = totalWidth - MidasKeyMetrics.sidePadding * 2 - MidasKeyMetrics.keySpacing * 9
        return max(20, usable / 10)
    }

    private func keyRows(width: CGFloat) -> some View {
        let unit = unitWidth(width)
        let rows = model.numbersLayout.rows
        return VStack(spacing: MidasKeyMetrics.rowSpacing) {
            characterRow(rows[0], unit: unit)
            characterRow(rows[1], unit: unit)
            thirdRow(rows[2], unit: unit, totalWidth: width)
            bottomRow(unit: unit)
        }
        .padding(.horizontal, MidasKeyMetrics.sidePadding)
        .frame(width: width)
    }

    private func characterRow(_ characters: [String], unit: CGFloat) -> some View {
        HStack(spacing: MidasKeyMetrics.keySpacing) {
            ForEach(characters, id: \.self) { character in
                feedbackKey(label: character, style: .normal, width: unit, control: .character(character))
            }
        }
    }

    /// #+= (or 123), five wider punctuation keys, ⌫: as Apple's numbers page.
    private func thirdRow(_ characters: [String], unit: CGFloat, totalWidth: CGFloat) -> some View {
        let sideWidth = unit * 1.35
        let gaps = MidasKeyMetrics.keySpacing * CGFloat(characters.count + 1)
        let middleWidth = totalWidth - MidasKeyMetrics.sidePadding * 2 - sideWidth * 2 - gaps
        let characterWidth = middleWidth / CGFloat(characters.count)
        return HStack(spacing: MidasKeyMetrics.keySpacing) {
            feedbackKey(label: model.numbersLayout.pageKeyLabel, style: .special, width: sideWidth, control: .symbols)
            ForEach(characters, id: \.self) { character in
                feedbackKey(label: character, style: .normal, width: characterWidth, control: .character(character))
            }
            MidasRepeatingKey(systemImage: "delete.left", width: sideWidth, action: makeBackspaceAction())
        }
    }

    private func bottomRow(unit: CGFloat) -> some View {
        HStack(spacing: MidasKeyMetrics.keySpacing) {
            feedbackKey(label: "ABC", style: .special, width: unit * 2.1, control: .abc)
            // Only on phones where iOS draws no 🌐 under the keyboard
            if model.needsGlobeKey {
                feedbackKey(systemImage: "globe", style: .special, width: unit * 1.1, control: .nextKeyboard)
            }
            feedbackKey(label: "space", style: .normal, width: nil, control: .space)
            feedbackKey(label: "return", style: .special, width: unit * 2.1, control: .returnKey)
        }
    }

    private func feedbackKey(label: String? = nil, systemImage: String? = nil, style: MidasKeyStyle, width: CGFloat?,
                             control: DictationKeyboardControl) -> some View {
        MidasFeedbackKey(label: label, systemImage: systemImage, style: style, width: width, pressed: makePressAction(control),
                         action: makeTapAction(control))
    }

    private func makePressAction(_ control: DictationKeyboardControl) -> () -> Void {
        let keyboardModel = model
        return {
            keyboardModel.keyPressed(control)
        }
    }

    private func makeTapAction(_ control: DictationKeyboardControl) -> () -> Void {
        let keyboardModel = model
        return {
            keyboardModel.tap(control)
        }
    }

    /// Each delete, the first and every repeat while held, plays Apple's delete sound.
    private func makeBackspaceAction() -> () -> Void {
        let keyboardModel = model
        return {
            keyboardModel.keyPressed(.backspace)
            keyboardModel.tap(.backspace)
        }
    }
}

/// A key that plays its sound and haptic on touch down and types on touch up.
struct MidasFeedbackKey: View {
    let label: String?
    let systemImage: String?
    let style: MidasKeyStyle
    let width: CGFloat?
    let pressed: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            keyFace
        }
        .buttonStyle(MidasFeedbackKeyStyle(style: style, width: width, pressed: pressed))
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if systemImage == "globe" {
            return "Next Keyboard"
        }
        return label ?? ""
    }

    @ViewBuilder
    private var keyFace: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
        } else if let label {
            Text(label)
                .font(label.count == 1 ? .system(size: 23) : .system(size: 15))
        }
    }
}

/// MidasKeyButtonStyle's look, plus the touch-down report.
struct MidasFeedbackKeyStyle: ButtonStyle {
    let style: MidasKeyStyle
    let width: CGFloat?
    let pressed: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let base = style == .normal ? MidasKeyColors.key(colorScheme) : MidasKeyColors.special(colorScheme)
        let pressedColour = style == .normal ? MidasKeyColors.special(colorScheme) : MidasKeyColors.key(colorScheme)
        return configuration.label
            .foregroundStyle(MidasKeyColors.label(colorScheme))
            .frame(width: width, height: MidasKeyMetrics.keyHeight)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(configuration.isPressed ? pressedColour : base, in: RoundedRectangle(cornerRadius: MidasKeyMetrics.cornerRadius))
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed, initial: false) { _, isPressed in
                if isPressed {
                    pressed()
                }
            }
    }
}

// MARK: Listening (Apple's 🎙)

/// While Apple types: APPLE MIC, the words so far, jess's orb pulsing Volt; green as the cleaned
/// text lands.
struct MidasAppleListeningView: View {
    let model: MidasKeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            Text(DictationAppleConstants.label)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.primary)
            Text(heardWords)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .bottom)
                .padding(.horizontal, 18)
            JessOrb(state: orbState)
                .frame(width: 62, height: 62)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The words so far; the cleaned text while it lands.
    private var heardWords: String {
        model.appleWords
    }

    private var orbState: JessOrbState {
        model.panel == .inserted ? .added : .listening
    }
}
