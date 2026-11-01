import SwiftUI

/// The status beside a request: S2, the word plus four steps (founder, 2026-10-23). How the pill
/// is drawn is still open (Q1 soft capsule, Q2 word over a bar, Q3 capsule that fills;
/// docs/mockups/make-2026-10-23.html section 2); `MakeStatusPill.style` is the one place to switch.
enum MakeStatusStyle: Sendable {
    /// S2 as confirmed: the word, then four small steps.
    case plain
    case softCapsule
    case wordOverBar
    case fillingCapsule
}

struct MakeStatusPill: View {
    /// The founder's pick goes here.
    static let style: MakeStatusStyle = .plain

    let status: MakeStatus
    var style: MakeStatusStyle = MakeStatusPill.style

    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.word)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .plain:
            HStack(spacing: 8) {
                word(color: wordColor)
                steps(width: 6, height: 6, on: tokens.ink.color, off: tokens.ink3.color, round: true)
            }
        case .softCapsule:
            let built = status == .built
            HStack(spacing: 8) {
                word(color: built ? tokens.paper.color : wordColor)
                steps(width: 7, height: 3, on: built ? tokens.paper.color : tokens.ink.color, off: tokens.ink3.color, round: false)
            }
            .padding(.leading, 11)
            .padding(.trailing, 10)
            .frame(height: 28)
            .background(built ? tokens.ink.color : tokens.paper2.color, in: Capsule())
        case .wordOverBar:
            VStack(alignment: .trailing, spacing: 5) {
                word(color: wordColor)
                steps(width: 14, height: 3, on: tokens.ink.color, off: tokens.rule.color, round: false)
            }
        case .fillingCapsule:
            let built = status == .built
            word(color: built ? tokens.paper.color : wordColor)
                .padding(.horizontal, 12)
                .frame(minWidth: 96, minHeight: 28)
                .background(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(built ? tokens.ink.color : tokens.ink.color.opacity(0.12))
                            .frame(width: proxy.size.width * Double(status.stepCount) / 4)
                    }
                }
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(tokens.rule.color, lineWidth: 1)
                }
        }
    }

    /// Sent is grey: nobody has looked yet.
    private var wordColor: Color {
        status == .sent ? tokens.ink2.color : tokens.ink.color
    }

    private func word(color: Color) -> some View {
        Text(status.word)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private func steps(width: CGFloat, height: CGFloat, on: Color, off: Color, round: Bool) -> some View {
        HStack(spacing: round ? 5 : 3) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: round ? width / 2 : 2)
                    .fill(index < status.stepCount ? on : off)
                    .frame(width: width, height: height)
            }
        }
    }
}

/// One request in a list: unread dot, the request, "last line · time" under it, the status on the
/// right (H1: the time moved under the request, so the right side holds only the status).
struct MakeRequestRow: View {
    let title: String
    let lastLine: String?
    let time: String?
    let status: MakeStatus
    let unread: Int
    /// The founder's list shows the count; the person's a dot.
    var showsCount = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if unread > 0 && !showsCount {
                        Circle()
                            .fill(tokens.ink.color)
                            .frame(width: 9, height: 9)
                            .alignmentGuide(.firstTextBaseline, computeValue: unreadDotBaseline)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tokens.ink.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let subline = MakeRequestRow.subline(lastLine: lastLine, time: time) {
                    Text(subline)
                        .font(.system(size: 14))
                        .foregroundStyle(tokens.ink2.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if showsCount && unread > 0 {
                    MakeCountBadge(count: unread)
                }
                MakeStatusPill(status: status)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.rule.color)
                .frame(height: 1)
                .padding(.leading, 20)
        }
        .contentShape(Rectangle())
    }

    nonisolated private func unreadDotBaseline(_ dimensions: ViewDimensions) -> CGFloat {
        dimensions[VerticalAlignment.center] + 4
    }

    /// "Make: 3 designs · 9:30 AM", or only the time.
    static func subline(lastLine: String?, time: String?) -> String? {
        var parts: [String] = []
        if let lastLine, !lastLine.isEmpty {
            parts.append(lastLine)
        }
        if let time, !time.isEmpty {
            parts.append(time)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct MakeCountBadge: View {
    let count: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        Text("\(count)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tokens.paper.color)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(tokens.ink.color, in: Capsule())
    }
}

/// One row's words, worked out from the thread (shared by the home list and the inbox).
struct MakeRowSummary: Equatable {
    let lastLine: String?
    let time: String?
    let unread: Int

    @MainActor
    static func make(thread: MakeThread, request: MakeRequest, readMarks: MakeReadMarks, forFounder: Bool, now: Date = Date()) -> MakeRowSummary {
        let lastLine = MakeRecords.lastLine(of: thread, forFounder: forFounder)
        let latest = thread.latestSentAt ?? request.updatedAt ?? request.createdAt
        let time = latest.map(labelRelative(to: now))
        let unread = readMarks.unreadCount(thread, ref: request.ref, forFounder: forFounder)
        return MakeRowSummary(lastLine: lastLine, time: time, unread: unread)
    }

    private static func labelRelative(to now: Date) -> (Date) -> String {
        { date in MakeTime.listLabel(date, now: now) }
    }
}

/// Make home, H1 (founder, 2026-10-23): "Make", every request newest first, and the B3 pill to
/// start a new one. Send writes the request and its first message, then pulls.
struct MakeHomeView: View {
    let center: MakeCenter
    var router: SidekickRouter = ShellServices.shared.router
    var directory: SidekickDirectory = ShellServices.shared.directory

    @State private var composer = PillVoiceComposer()
    @State private var openRequest: MakeThreadRef?
    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        // Reading the revision redraws the list on every Make record change
        let _ = center.revision
        let requests = MakeRecords.requests(in: center.personRecords(), inInbox: false)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(MakeCopy.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(tokens.ink.color)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                ForEach(requests) { request in
                    Button(action: opener(for: request.ref)) {
                        row(for: request)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if requests.isEmpty {
                Text(MakeCopy.noRequests)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink2.color)
            }
        }
        .safeAreaInset(edge: .bottom) {
            pill
        }
        .background(tokens.paper.color)
        .toolbar(.hidden, for: .navigationBar)
        .background {
            SwipeBackEnabler()
                .frame(width: 0, height: 0)
        }
        .navigationDestination(item: $openRequest) { ref in
            MakeThreadView(center: center, ref: ref)
        }
        .makeLivePull(center)
        .repairUnavailableSwipe(sidekickId: MakeSidekick.id)
        // C1, once: "Built by Hand", signed RJ (founder, 2026-10-31)
        .makeWelcomeOnFirstOpen()
        .onAppear(perform: appeared)
        .onChange(of: center.pendingRequestId, pendingRequestChanged)
    }

    private func row(for request: MakeRequest) -> some View {
        let thread = center.thread(request.ref)
        let summary = MakeRowSummary.make(thread: thread, request: request, readMarks: center.readMarks, forFounder: false)
        return MakeRequestRow(title: request.title, lastLine: summary.lastLine, time: summary.time, status: request.status, unread: summary.unread)
    }

    private func opener(for ref: MakeThreadRef) -> () -> Void {
        { openRequest = ref }
    }

    private var pill: some View {
        let text = composer.pillText
        return PillBar(
            settled: text.settled,
            pending: text.pending,
            typed: $composer.typed,
            isTyping: $composer.isTyping,
            placeholder: MakeCopy.newRequestPlaceholder,
            orbState: composer.orbState,
            orbLevel: composer.orbLevel,
            onOrbTap: composer.toggleListening,
            canSend: composer.canSend,
            sendLabel: MakeCopy.sendButton,
            onSend: sendNewRequest
        )
        .padding(.horizontal, RepairPillSpec.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// H1's Send: the request and its first message, then a pull so the inbox has it.
    private func sendNewRequest() {
        guard let words = composer.take() else {
            return
        }
        _ = try? center.writer.newRequest(words: words)
        Task { @MainActor in
            await center.sync()
        }
    }

    private func appeared() {
        openPendingRequest()
        playBuiltIfNeeded()
    }

    private func openPendingRequest() {
        guard let reqId = center.pendingRequestId else {
            return
        }
        center.pendingRequestId = nil
        openRequest = MakeThreadRef(userId: nil, reqId: reqId)
    }

    private func pendingRequestChanged(_ oldValue: String?, _ newValue: String?) {
        openPendingRequest()
    }

    /// R2: a Built request not yet shown on this phone plays the Built screen over the home grid
    /// and locks into its tile there.
    private func playBuiltIfNeeded() {
        guard openRequest == nil, center.pendingRequestId == nil, let request = center.unshownBuilt(), let sidekickId = request.sidekickId else {
            return
        }
        center.builtShown.insert(request.reqId)
        Task { @MainActor in
            // The server assigned the new Sidekick when it was built; the listing brings its tile
            await directory.refresh()
            let entry = directory.entry(withId: sidekickId) ?? MakeBuiltStage.placeholderEntry(sidekickId: sidekickId)
            router.goHome()
            center.builtStage.play(entry: entry, plan: request.plan ?? "")
        }
    }
}
