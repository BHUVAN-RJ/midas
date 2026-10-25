import SwiftUI
import UIKit

/// T2, a question card in the thread (founder, 2026-10-23/24; docs/mockups/make-2026-10-23.html,
/// Confirmed): who asks, the question, then the choices as chips or the designs as a carousel that
/// swipes both ways. Tapping an option only selects it; Send at the card's bottom right sends it,
/// greyed until something is picked. Once answered the card locks: the pick stays marked, the rest
/// fade, Send becomes a check. In the inbox the founder sees it read-only.
struct MakeQuestionCardView: View {
    let card: MakeCard
    let answer: MakeAnswer?
    /// False in the founder's inbox, and for every card but the newest unanswered one.
    let isLive: Bool
    var senderName: String = MakeCopy.senderName
    /// A design's picture by file id.
    var fileData: @MainActor (String) async -> Data? = MakeCenter.noFile
    let onSend: (MakeCardOption) -> Void

    @State private var selectedId: String?
    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(card.question)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tokens.ink.color)
                .fixedSize(horizontal: false, vertical: true)
            options
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.paper.color, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(tokens.rule.color, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            MakeAvatar(letter: String(senderName.prefix(1)), size: 22, fill: tokens.ink.color, ink: tokens.paper.color)
            Text(senderName)
                .font(.system(size: 13))
                .foregroundStyle(tokens.ink2.color)
        }
    }

    // MARK: Options

    /// What shows as picked: the live selection, or the sent answer.
    var shownSelection: String? {
        MakeQuestionCardState.shownSelection(isLive: isLive, selectedId: selectedId, answer: answer)
    }

    @ViewBuilder
    private var options: some View {
        switch card.kind {
        case .choice:
            MakeChipFlow(spacing: 8) {
                ForEach(card.options) { option in
                    chip(option)
                }
            }
        case .design:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(card.options.enumerated()), id: \.element.id) { index, option in
                        design(option, index: index)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -4)
        }
    }

    private func chip(_ option: MakeCardOption) -> some View {
        let look = MakeQuestionCardState.look(optionId: option.id, isLive: isLive, shownSelection: shownSelection, isAnswered: answer != nil)
        return Button(action: selector(for: option)) {
            Text(option.label ?? option.id)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(look == .picked ? tokens.paper.color : tokens.ink.color)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(look == .picked ? tokens.ink.color : tokens.paper.color, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(tokens.ink.color, lineWidth: 1.5)
                }
                .opacity(look == .faded ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .accessibilityAddTraits(look == .picked ? .isSelected : [])
    }

    private func design(_ option: MakeCardOption, index: Int) -> some View {
        let look = MakeQuestionCardState.look(optionId: option.id, isLive: isLive, shownSelection: shownSelection, isAnswered: answer != nil)
        return Button(action: selector(for: option)) {
            MakeDesignPicture(reference: option.image, fileData: fileData)
                .frame(width: MakeQuestionCardSpec.designWidth, height: MakeQuestionCardSpec.designHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(tokens.ink.color.opacity(0.14), lineWidth: 1)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(option.label ?? MakeCard.letter(at: index))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color(.sRGB, red: 17 / 255, green: 17 / 255, blue: 17 / 255, opacity: 0.75), in: Capsule())
                        .padding(6)
                }
                .overlay {
                    if look == .picked {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(tokens.ink.color, lineWidth: 3)
                            .padding(-3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if look == .picked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(tokens.paper.color)
                            .frame(width: 24, height: 24)
                            .background(tokens.ink.color, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(tokens.paper.color, lineWidth: 2)
                            }
                            .offset(x: 6, y: -6)
                    }
                }
                .opacity(look == .faded ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .accessibilityLabel(option.label ?? MakeCard.letter(at: index))
        .accessibilityAddTraits(look == .picked ? .isSelected : [])
    }

    private func selector(for option: MakeCardOption) -> () -> Void {
        { select(option) }
    }

    /// Tapping only selects; another tap changes the selection.
    private func select(_ option: MakeCardOption) {
        guard isLive else {
            return
        }
        selectedId = option.id
    }

    // MARK: Send

    private var footer: some View {
        HStack {
            Spacer()
            if answer != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tokens.ink2.color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle()
                            .strokeBorder(tokens.rule.color, lineWidth: 1)
                    }
                    .accessibilityLabel(MakeCopy.sendButton)
            } else if isLive {
                sendButton
            }
        }
    }

    private var sendButton: some View {
        let isOn = MakeQuestionCardState.canSend(isLive: isLive, selectedId: selectedId, answer: answer)
        return Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isOn ? tokens.paper.color : tokens.ink3.color)
                .frame(width: 44, height: 44)
                .background(isOn ? tokens.ink.color : tokens.paper2.color, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn)
        .accessibilityLabel(MakeCopy.sendButton)
    }

    private func send() {
        guard MakeQuestionCardState.canSend(isLive: isLive, selectedId: selectedId, answer: answer), let selectedId, let option = card.option(withId: selectedId) else {
            return
        }
        onSend(option)
    }
}

/// A card's rules, pure so the tests read them: what is picked, faded, and whether Send is on.
enum MakeQuestionCardState {
    enum Look: Equatable {
        case plain
        case picked
        case faded
    }

    static func shownSelection(isLive: Bool, selectedId: String?, answer: MakeAnswer?) -> String? {
        if let answer {
            return answer.optionId
        }
        return isLive ? selectedId : nil
    }

    /// Answered: the pick stays, the rest fade. Live: only the selection is marked.
    static func look(optionId: String, isLive: Bool, shownSelection: String?, isAnswered: Bool) -> Look {
        if shownSelection == optionId {
            return .picked
        }
        if isAnswered {
            return .faded
        }
        return .plain
    }

    /// Send is on once something is selected, and only before the card has its answer.
    static func canSend(isLive: Bool, selectedId: String?, answer: MakeAnswer?) -> Bool {
        isLive && answer == nil && selectedId != nil
    }
}

enum MakeQuestionCardSpec {
    static let designWidth: CGFloat = 150
    /// The mockup's pictures are phone-shaped, 1.9 times as tall as wide.
    static let designHeight: CGFloat = 285
}

/// A design's picture from `file:<id>`, grey until it has loaded.
struct MakeDesignPicture: View {
    let reference: String?
    let fileData: @MainActor (String) async -> Data?

    @State private var image: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RepairTokens.forScheme(colorScheme).paper2.color
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: reference, load)
    }

    private func load() async {
        guard let reference, let fileId = FileStore.fileId(fromReference: reference), let data = await fileData(fileId) else {
            return
        }
        image = UIImage(data: data)
    }
}

/// A round letter: the founder's face in a card, a person's in the inbox.
struct MakeAvatar: View {
    let letter: String
    let size: CGFloat
    let fill: Color
    let ink: Color

    var body: some View {
        Text(letter)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Chips in rows that wrap, left to right.
struct MakeChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map(rowBottom) ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.top), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var top: CGFloat = 0
    }

    private func rowBottom(_ row: Row) -> CGFloat {
        row.top + row.height
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            // A chip that does not fit starts the next row
            if needed > width && !current.indices.isEmpty {
                let nextTop = current.top + current.height + spacing
                rows.append(current)
                current = Row(top: nextTop)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
