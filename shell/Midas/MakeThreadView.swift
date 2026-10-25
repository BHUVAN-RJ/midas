import SwiftUI

/// The person's thread, T2 (founder, 2026-10-23/24): the request's messages and question cards in
/// order, no status (status shows only in the list). The B3 pill at the bottom: jess listens from
/// the moment the thread opens; tapping the words to type stops listening. The pill's words answer
/// the newest card when it is open and takes own words; otherwise they go as a message.
struct MakeThreadView: View {
    let center: MakeCenter
    let ref: MakeThreadRef
    var router: SidekickRouter = ShellServices.shared.router
    var directory: SidekickDirectory = ShellServices.shared.directory

    @State private var composer = PillVoiceComposer()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        let _ = center.revision
        let thread = center.thread(ref)
        VStack(spacing: 0) {
            MakeThreadHeader(title: thread.request?.title ?? "", onBack: goBack)
            MakeThreadList(thread: thread, forFounder: false, center: center, onAnswer: answer(card:option:), onOpenBuilt: openBuilt)
        }
        .safeAreaInset(edge: .bottom) {
            pill(thread: thread)
        }
        .background(tokens.paper.color)
        .toolbar(.hidden, for: .navigationBar)
        .background {
            SwipeBackEnabler()
                .frame(width: 0, height: 0)
        }
        .makeLivePull(center)
        .repairUnavailableSwipe(sidekickId: MakeSidekick.id)
        .onAppear(perform: appeared)
        .onDisappear(perform: disappeared)
        .onChange(of: center.revision, revisionChanged)
        .task {
            // Voice starts on open
            await composer.startListening()
        }
    }

    private func pill(thread: MakeThread) -> some View {
        let text = composer.pillText
        return PillBar(
            settled: text.settled,
            pending: text.pending,
            typed: $composer.typed,
            isTyping: $composer.isTyping,
            placeholder: MakeCopy.messagePlaceholder,
            orbState: composer.orbState,
            orbLevel: composer.orbLevel,
            onOrbTap: composer.toggleListening,
            canSend: composer.canSend,
            sendLabel: MakeCopy.sendButton,
            onSend: sendWords
        )
        .padding(.horizontal, RepairPillSpec.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func sendWords() {
        guard let words = composer.take() else {
            return
        }
        // Read again now: a card may have come in since the last redraw
        let thread = center.thread(ref)
        try? center.writer.send(words: words, in: thread, reqId: ref.reqId)
        syncSoon()
    }

    private func answer(card: MakeCard, option: MakeCardOption) {
        try? center.writer.answer(reqId: ref.reqId, cardId: card.cardId, optionId: option.id, text: nil)
        syncSoon()
    }

    private func syncSoon() {
        Task { @MainActor in
            await center.sync()
        }
    }

    /// R3: the Built card opens the new Sidekick.
    private func openBuilt(_ request: MakeRequest) {
        guard let sidekickId = request.sidekickId else {
            return
        }
        Task { @MainActor in
            if directory.entry(withId: sidekickId) == nil {
                await directory.refresh()
            }
            router.open(sidekickId: sidekickId)
        }
    }

    private func goBack() {
        dismiss()
    }

    private func appeared() {
        center.openThread = ref
        markSeen()
    }

    private func disappeared() {
        if center.openThread == ref {
            center.openThread = nil
        }
        composer.stopListening()
    }

    private func markSeen() {
        center.readMarks.markSeen(center.thread(ref), ref: ref)
    }

    private func revisionChanged(_ oldValue: Int, _ newValue: Int) {
        markSeen()
    }
}

/// A thread's header: back, and the request (or the person) as the title.
struct MakeThreadHeader<Leading: View>: View {
    let title: String
    var subtitle: String?
    let onBack: () -> Void
    @ViewBuilder var leading: () -> Leading

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tokens.ink.color)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MakeCopy.backButton)
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink.color)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.ink2.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 54)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.rule.color)
                .frame(height: 1)
        }
        .background(tokens.paper.color)
    }
}

extension MakeThreadHeader where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onBack: onBack, leading: Self.noLeading)
    }

    private static func noLeading() -> EmptyView {
        EmptyView()
    }
}

/// The thread's items, newest at the bottom; scrolled to the newest when something arrives.
/// The person sees their own words on the right; the founder sees his own on the right, the
/// person's on the left, and the cards read-only.
struct MakeThreadList: View {
    let thread: MakeThread
    let forFounder: Bool
    let center: MakeCenter
    var onAnswer: @MainActor (MakeCard, MakeCardOption) -> Void = MakeThreadList.ignoreAnswer
    var onOpenBuilt: @MainActor (MakeRequest) -> Void = MakeThreadList.ignoreBuilt

    static func ignoreAnswer(_ card: MakeCard, _ option: MakeCardOption) {}
    static func ignoreBuilt(_ request: MakeRequest) {}

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(thread.items) { item in
                        itemView(item)
                            .id(item.id)
                            .transition(.asymmetric(insertion: .offset(y: 14).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.42), value: thread.items.map(\.id))
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: thread.items.last?.id, scrollToNewest(proxy))
        }
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy) -> (String?, String?) -> Void {
        { _, newest in
            guard let newest else {
                return
            }
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(newest, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: MakeThreadItem) -> some View {
        switch item {
        case .message(let message):
            MakeBubble(text: message.text, isMine: isMine(message.from))
        case .ownWords(let answer):
            MakeBubble(text: answer.text ?? "", isMine: isMine(.person))
        case .card(let card, let answer):
            MakeQuestionCardView(card: card, answer: answer, isLive: !forFounder && thread.openCard?.cardId == card.cardId, fileData: center.fileData, onSend: sender(for: card))
        case .built(let request):
            MakeBuiltCard(request: request, center: center, onOpen: opener(for: request))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isMine(_ speaker: MakeSpeaker) -> Bool {
        forFounder ? speaker == .maker : speaker == .person
    }

    private func sender(for card: MakeCard) -> (MakeCardOption) -> Void {
        { option in onAnswer(card, option) }
    }

    private func opener(for request: MakeRequest) -> () -> Void {
        { onOpenBuilt(request) }
    }
}

/// One message: mine on the right in ink, theirs on the left in warm grey.
struct MakeBubble: View {
    let text: String
    let isMine: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        let theirs = colorScheme == .dark ? JessOrbColor(hex: 0x262626).color : tokens.paper2.color
        let shape = UnevenRoundedRectangle(topLeadingRadius: 19, bottomLeadingRadius: isMine ? 19 : 6, bottomTrailingRadius: isMine ? 6 : 19, topTrailingRadius: 19)
        HStack {
            if isMine {
                Spacer(minLength: 60)
            }
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(isMine ? tokens.paper.color : tokens.ink.color)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(isMine ? tokens.ink.color : theirs, in: shape)
                .textSelection(.enabled)
            if !isMine {
                Spacer(minLength: 60)
            }
        }
    }
}
