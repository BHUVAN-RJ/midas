// The Midas keyboard's keys (TEST BUILD, founder 2026-11-14; docs/mockups/
// dictation-keyboard-2026-11-13.html). Listening: the raw words, jess's orb, ABC on the left, 123
// and 😊 on the right. Letters, numbers and symbols: full keys, ● next to space goes back to
// listening. Light and dark follow the system keyboard colours.
import SwiftUI

/// Key colours from the mockup, light and dark.
enum MidasKeyColors {
    static func key(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6E / 255) : .white
    }

    static func special(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x46 / 255, green: 0x46 / 255, blue: 0x49 / 255) : Color(red: 0xAB / 255, green: 0xB0 / 255, blue: 0xBA / 255)
    }

    static func label(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    }
}

/// Sizes shared by every page.
enum MidasKeyMetrics {
    static let keyHeight: CGFloat = 42
    static let keySpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 11
    static let sidePadding: CGFloat = 3
    static let cornerRadius: CGFloat = 5
}

struct MidasKeyboardView: View {
    let model: MidasKeyboardModel

    var body: some View {
        VStack(spacing: 0) {
            if let line = model.layout.fullAccessLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            if model.layout.page == .listening {
                MidasListeningPanel(model: model)
            } else {
                MidasTypingKeys(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Listening

struct MidasListeningPanel: View {
    let model: MidasKeyboardModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            centre
            Spacer(minLength: 8)
            bottomRow
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var centre: some View {
        switch model.panel {
        case .startButton:
            Button(DictationKeyboardConstants.startButtonTitle, action: model.startDictation)
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(MidasKeyColors.key(colorScheme), in: Capsule())
                .foregroundStyle(MidasKeyColors.label(colorScheme))
                .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
        default:
            VStack(spacing: 14) {
                Text(heardWords)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottom)
                    .padding(.horizontal, 18)
                Button(action: model.listenAgain) {
                    JessOrb(state: orbState)
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(.plain)
                // Only the idle orb listens again; the others are not dimmed
                .allowsHitTesting(model.panel == .idle)
            }
        }
    }

    private var heardWords: String {
        if case .listening(let heard) = model.panel {
            return heard
        }
        return ""
    }

    private var orbState: JessOrbState {
        switch model.panel {
        case .listening:
            return .listening
        case .inserted:
            return .added
        case .connecting:
            return .thinking
        case .idle, .startButton:
            return .idle
        }
    }

    private var bottomRow: some View {
        HStack(spacing: MidasKeyMetrics.keySpacing) {
            MidasKey(label: "ABC", style: .special, width: 56, action: tapABC)
            Spacer()
            MidasKey(label: "123", style: .special, width: 56, action: tapNumbers)
            MidasKey(label: "😊", style: .special, width: 56, action: tapNextKeyboard)
        }
    }

    private func tapABC() {
        model.tap(.abc)
    }

    private func tapNumbers() {
        model.tap(.numbers)
    }

    private func tapNextKeyboard() {
        model.tap(.nextKeyboard)
    }
}

// MARK: Typing

struct MidasTypingKeys: View {
    let model: MidasKeyboardModel

    var body: some View {
        GeometryReader { proxy in
            keyRows(width: proxy.size.width)
        }
        .padding(.top, 8)
    }

    /// One standard key's width: ten keys and their gaps fill the row.
    private func unitWidth(_ totalWidth: CGFloat) -> CGFloat {
        let usable = totalWidth - MidasKeyMetrics.sidePadding * 2 - MidasKeyMetrics.keySpacing * 9
        return max(20, usable / 10)
    }

    private func keyRows(width: CGFloat) -> some View {
        let unit = unitWidth(width)
        let rows = model.layout.rows
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
                MidasKey(label: displayed(character), style: .normal, width: unit, action: characterAction(character))
            }
        }
    }

    private func thirdRow(_ characters: [String], unit: CGFloat, totalWidth: CGFloat) -> some View {
        let isLetters = model.layout.page == .letters
        let sideWidth = unit * 1.35
        // Numbers and symbols have five wider keys between the side keys
        let gaps = MidasKeyMetrics.keySpacing * CGFloat(characters.count + 1)
        let middleWidth = totalWidth - MidasKeyMetrics.sidePadding * 2 - sideWidth * 2 - gaps
        let characterWidth = isLetters ? unit : middleWidth / CGFloat(characters.count)
        return HStack(spacing: MidasKeyMetrics.keySpacing) {
            leftOfThirdRow(width: sideWidth)
            ForEach(characters, id: \.self) { character in
                MidasKey(label: displayed(character), style: .normal, width: characterWidth, action: characterAction(character))
            }
            MidasRepeatingKey(systemImage: "delete.left", width: sideWidth, action: tapBackspace)
        }
    }

    @ViewBuilder
    private func leftOfThirdRow(width: CGFloat) -> some View {
        switch model.layout.page {
        case .letters:
            MidasKey(systemImage: shiftSymbol, style: model.layout.shift == .off ? .special : .normal, width: width, action: tapShift)
        case .numbers:
            MidasKey(label: "#+=", style: .special, width: width, action: tapSymbols)
        case .symbols, .listening:
            MidasKey(label: "123", style: .special, width: width, action: tapNumbers)
        }
    }

    private var shiftSymbol: String {
        switch model.layout.shift {
        case .off:
            return "shift"
        case .once:
            return "shift.fill"
        case .locked:
            return "capslock.fill"
        }
    }

    private func bottomRow(unit: CGFloat) -> some View {
        let isLetters = model.layout.page == .letters
        return HStack(spacing: MidasKeyMetrics.keySpacing) {
            MidasKey(label: isLetters ? "123" : "ABC", style: .special, width: unit * 1.25, action: isLetters ? tapNumbers : tapABC)
            if model.needsGlobeKey {
                MidasKey(systemImage: "globe", style: .special, width: unit * 1.1, action: tapNextKeyboard)
            }
            if model.layout.showsListenKey {
                MidasListenKey(width: unit * 1.1, action: tapListen)
            }
            MidasKey(label: "space", style: .normal, width: nil, action: tapSpace)
            MidasKey(label: "return", style: .special, width: unit * 2.1, action: tapReturn)
        }
    }

    private func displayed(_ character: String) -> String {
        let isCapital = model.layout.page == .letters && model.layout.shift != .off
        return isCapital ? character.uppercased() : character
    }

    private func characterAction(_ character: String) -> () -> Void {
        let keyboardModel = model
        return {
            keyboardModel.tap(.character(character))
        }
    }

    private func tapShift() {
        model.tap(.shift)
    }

    private func tapSymbols() {
        model.tap(.symbols)
    }

    private func tapNumbers() {
        model.tap(.numbers)
    }

    private func tapABC() {
        model.tap(.abc)
    }

    private func tapListen() {
        model.tap(.listen)
    }

    private func tapNextKeyboard() {
        model.tap(.nextKeyboard)
    }

    private func tapSpace() {
        model.tap(.space)
    }

    private func tapReturn() {
        model.tap(.returnKey)
    }

    private func tapBackspace() {
        model.tap(.backspace)
    }
}

// MARK: Keys

enum MidasKeyStyle {
    case normal
    case special
}

/// One key: a label or a symbol, pressed state darker.
struct MidasKey: View {
    var label: String? = nil
    var systemImage: String? = nil
    let style: MidasKeyStyle
    /// Nil: takes the space left in the row.
    let width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            keyFace
        }
        .buttonStyle(MidasKeyButtonStyle(style: style, width: width))
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

struct MidasKeyButtonStyle: ButtonStyle {
    let style: MidasKeyStyle
    let width: CGFloat?
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
    }
}

/// ● next to space: a small jess orb on an ink key, back to listening.
struct MidasListenKey: View {
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: MidasKeyMetrics.cornerRadius)
                    .fill(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255))
                JessOrb(state: .idle)
                    .frame(width: 24, height: 24)
            }
            .frame(width: width, height: MidasKeyMetrics.keyHeight)
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dictate")
    }
}

/// Backspace: one delete on touch, then repeats while held.
struct MidasRepeatingKey: View {
    let systemImage: String
    let width: CGFloat
    let action: () -> Void
    @State private var repeating: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17))
            .foregroundStyle(MidasKeyColors.label(colorScheme))
            .frame(width: width, height: MidasKeyMetrics.keyHeight)
            .background(repeating == nil ? MidasKeyColors.special(colorScheme) : MidasKeyColors.key(colorScheme),
                        in: RoundedRectangle(cornerRadius: MidasKeyMetrics.cornerRadius))
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
            .contentShape(Rectangle())
            .gesture(pressGesture)
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged(pressChanged)
            .onEnded(pressEnded)
    }

    private func pressChanged(_ value: DragGesture.Value) {
        guard repeating == nil else {
            return
        }
        action()
        let keyAction = action
        repeating = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                keyAction()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func pressEnded(_ value: DragGesture.Value) {
        repeating?.cancel()
        repeating = nil
    }
}
