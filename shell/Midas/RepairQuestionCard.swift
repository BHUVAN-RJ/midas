import SwiftUI
import UIKit

// The ask-back card and the shell-can't sheet over the repair pill (founder, 2026-11-13, D4 = A;
// docs/mockups/repair-ask-back-2026-11-08.html, columns "A · Cards" and "Shell can't"). Both sit
// 14 pt above the B3 pill, between its side margins, and rise 40 pt as they fade in over 350 ms.

/// Every number from the mockup's `.qcard`, `.opt` and `.sheet`, at the phone's own scale.
enum RepairQuestionCardSpec {
    static let cornerRadius: CGFloat = 26
    static let padding: CGFloat = 16
    static let questionSize: CGFloat = 19
    static let questionGap: CGFloat = 12
    static let optionGap: CGFloat = 10
    static let optionCornerRadius: CGFloat = 18
    static let optionVerticalPadding: CGFloat = 12
    static let optionHorizontalPadding: CGFloat = 8
    static let optionLabelSize: CGFloat = 15
    static let pictureHeight: CGFloat = 44
    static let pictureGap: CGFloat = 6
    static let pictureSymbolSize: CGFloat = 28
    /// The picked guess: a 2 pt ink edge (mockup: 1 pt border plus 1 pt inset shadow).
    static let pickedEdge: CGFloat = 2
    /// Over the frozen page: 95% paper, a hairline, a soft shadow (0 8 24, 14%).
    static let backgroundOpacity = 0.95
    static let shadowRadius: CGFloat = 12
    static let shadowY: CGFloat = 8
    /// 14 pt between the card's bottom and the pill's top.
    static let gapAbovePill: CGFloat = 14

    static let sheetPadding: CGFloat = 18
    static let sheetTitleSize: CGFloat = 19
    static let sheetDetailSize: CGFloat = 15
    static let sheetLineGap: CGFloat = 4
    /// The sheet's grey line, #A3A3A3 on ink.
    static let sheetDetail = JessOrbColor(hex: 0xA3A3A3)
}

/// How a guess's picture is drawn.
enum RepairOptionPicture: Equatable {
    case symbol(String)
    case text(String)
    case blank

    /// An SF Symbol when iOS has one by that name; a short text (an emoji, "∅") as text;
    /// otherwise a plain mark, never a broken image.
    static func forIcon(_ icon: String?, symbolExists: (String) -> Bool = RepairOptionPicture.systemSymbolExists) -> RepairOptionPicture {
        guard let icon else {
            return .blank
        }
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .blank
        }
        if symbolExists(trimmed) {
            return .symbol(trimmed)
        }
        if trimmed.count <= 2 {
            return .text(trimmed)
        }
        return .blank
    }

    static func systemSymbolExists(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
}

/// "What should it be?" with 2–3 picture guesses side by side. A tap picks a guess and fills the
/// pill with its words; the pill's Send sends it (no Send on the card).
struct RepairQuestionCard: View {
    let question: RepairQuestion
    let pickedOptionId: String?
    let onPick: (RepairQuestionOption) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RepairQuestionCardSpec.questionGap) {
            Text(question.text)
                .font(.system(size: RepairQuestionCardSpec.questionSize, weight: .bold))
                .foregroundStyle(tokens.ink.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: RepairQuestionCardSpec.optionGap) {
                ForEach(question.options) { option in
                    optionButton(option)
                }
            }
        }
        .padding(RepairQuestionCardSpec.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The shadow is the card's alone: on the background shape, so the guesses have none
        .background {
            cardShape
                .fill(tokens.paper.color.opacity(RepairQuestionCardSpec.backgroundOpacity))
                .shadow(color: tokens.shadow.color, radius: RepairQuestionCardSpec.shadowRadius, y: RepairQuestionCardSpec.shadowY)
        }
        .overlay {
            cardShape
                .strokeBorder(tokens.rule.color, lineWidth: 1)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RepairQuestionCardSpec.cornerRadius)
    }

    private var optionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RepairQuestionCardSpec.optionCornerRadius)
    }

    private func optionButton(_ option: RepairQuestionOption) -> some View {
        let isPicked = option.id == pickedOptionId
        return Button(action: picker(for: option)) {
            VStack(spacing: RepairQuestionCardSpec.pictureGap) {
                picture(RepairOptionPicture.forIcon(option.icon))
                    .frame(height: RepairQuestionCardSpec.pictureHeight)
                Text(option.label)
                    .font(.system(size: RepairQuestionCardSpec.optionLabelSize, weight: .semibold))
                    .foregroundStyle(tokens.ink.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, RepairQuestionCardSpec.optionVerticalPadding)
            .padding(.horizontal, RepairQuestionCardSpec.optionHorizontalPadding)
            .frame(maxWidth: .infinity)
            .background(tokens.paper.color, in: optionShape)
            .overlay {
                optionShape
                    .strokeBorder(isPicked ? tokens.ink.color : tokens.rule.color, lineWidth: isPicked ? RepairQuestionCardSpec.pickedEdge : 1)
            }
            .contentShape(optionShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func picker(for option: RepairQuestionOption) -> () -> Void {
        func pickThisOption() {
            onPick(option)
        }
        return pickThisOption
    }

    @ViewBuilder
    private func picture(_ picture: RepairOptionPicture) -> some View {
        switch picture {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: RepairQuestionCardSpec.pictureSymbolSize, weight: .regular))
                .foregroundStyle(tokens.ink.color)
                .accessibilityHidden(true)
        case .text(let text):
            Text(text)
                .font(.system(size: RepairQuestionCardSpec.pictureSymbolSize))
                .foregroundStyle(tokens.ink3.color)
                .accessibilityHidden(true)
        case .blank:
            Circle()
                .strokeBorder(tokens.ink3.color, lineWidth: 2)
                .frame(width: RepairQuestionCardSpec.pictureSymbolSize, height: RepairQuestionCardSpec.pictureSymbolSize)
                .accessibilityHidden(true)
        }
    }
}

/// The shell can't: the message in bold, "Sent to Midas." under it in grey, on ink. Ink in both
/// modes (the mockup's dark sheet); in dark mode a hairline keeps its edge on a dark page.
struct RepairShellCantSheet: View {
    let message: RepairShellCantMessage

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: RepairQuestionCardSpec.sheetLineGap) {
            if !message.title.isEmpty {
                Text(message.title)
                    .font(.system(size: RepairQuestionCardSpec.sheetTitleSize, weight: .bold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(message.detail)
                .font(.system(size: RepairQuestionCardSpec.sheetDetailSize))
                .foregroundStyle(RepairQuestionCardSpec.sheetDetail.color)
        }
        .padding(RepairQuestionCardSpec.sheetPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepairVolt.ink.color, in: sheetShape)
        .overlay {
            if colorScheme == .dark {
                sheetShape
                    .strokeBorder(RepairTokens.dark.rule.color, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sheetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RepairQuestionCardSpec.cornerRadius)
    }
}

/// The card and the sheet come in the same way: up 40 pt and in over 350 ms; Reduce Motion fades.
enum RepairAskBackMotion {
    static func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        let rise = AnyTransition.offset(y: RepairAskBackSpec.enterRise)
        return rise.combined(with: .opacity)
    }

    static var animation: Animation {
        .easeOut(duration: RepairAskBackSpec.enter)
    }
}
