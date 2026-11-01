import SwiftUI

// Make, first open, once (founder, 2026-10-31, docs/mockups/repair-words-make-welcome-2026-10-31.html
// "Final", C1): a sheet over Make, "Built by Hand", the line with "myself" marked in Volt, signed
// "RJ" in the hand, and Continue. Never again after it has shown once on this phone.

enum MakeWelcomeCopy {
    static let title = "Built by Hand"
    static let line = "I build your first version myself, so it arrives near perfect."
    /// The marked word in the line.
    static let marked = "myself"
    static let signature = "RJ"
    static let continueButton = "Continue"
}

enum MakeWelcomeSpec {
    /// The hand, bundled with the app (UIAppFonts in shell/project.yml).
    static let handFontName = "Caveat-Bold"
    static let titleSize: CGFloat = 22
    static let lineSize: CGFloat = 17
    static let signatureSize: CGFloat = 34
    static let buttonHeight: CGFloat = 50
    static let height: CGFloat = 300
}

/// Remembers on this phone that the sheet has shown.
struct MakeWelcomeMemory {
    static let defaultsKey = "midas.make.welcomeShown"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True the first time only: the sheet counts as shown as soon as it is asked for.
    func takeFirstOpen() -> Bool {
        guard !defaults.bool(forKey: Self.defaultsKey) else {
            return false
        }
        defaults.set(true, forKey: Self.defaultsKey)
        return true
    }
}

struct MakeWelcomeSheet: View {
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MakeWelcomeCopy.title)
                .font(.system(size: MakeWelcomeSpec.titleSize, weight: .bold))
                .foregroundStyle(tokens.ink.color)
            Text(Self.markedLine(scheme: colorScheme))
                .font(.system(size: MakeWelcomeSpec.lineSize))
                .foregroundStyle(tokens.ink2.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(MakeWelcomeCopy.signature)
                .font(.custom(MakeWelcomeSpec.handFontName, size: MakeWelcomeSpec.signatureSize))
                .foregroundStyle(tokens.ink.color)
                .padding(.top, 14)
                .padding(.bottom, 22)
            Button(action: onContinue) {
                Text(MakeWelcomeCopy.continueButton)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.paper.color)
                    .frame(maxWidth: .infinity, minHeight: MakeWelcomeSpec.buttonHeight)
                    .background(tokens.ink.color, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(MakeWelcomeSpec.height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    /// The line with "myself" marked in Volt (in dark mode a softer Volt, as in the mockup).
    static func markedLine(scheme: ColorScheme) -> AttributedString {
        var line = AttributedString(MakeWelcomeCopy.line)
        if let range = line.range(of: MakeWelcomeCopy.marked) {
            let volt = RepairVolt.color.color
            line[range].backgroundColor = scheme == .dark ? volt.opacity(0.55) : volt
            line[range].foregroundColor = scheme == .dark ? Color.white : RepairVolt.ink.color
        }
        return line
    }
}

extension View {
    /// Make's first-open sheet, once per phone.
    func makeWelcomeOnFirstOpen(memory: MakeWelcomeMemory = MakeWelcomeMemory()) -> some View {
        modifier(MakeWelcomeModifier(memory: memory))
    }
}

private struct MakeWelcomeModifier: ViewModifier {
    let memory: MakeWelcomeMemory

    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isShown) {
                MakeWelcomeSheet(onContinue: close)
            }
            .onAppear(perform: showOnFirstOpen)
    }

    private func showOnFirstOpen() {
        if memory.takeFirstOpen() {
            isShown = true
        }
    }

    private func close() {
        isShown = false
    }
}
