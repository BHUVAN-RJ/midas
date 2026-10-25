import SwiftUI

/// The founder's Inbox, F1 (founder, 2026-10-23): "Inbox", the people (unread count, last line)
/// → a person's requests (with their status) → the thread, where the founder replies with the
/// pill and sets the status: Figuring Out · Looking · Building · Built. Built asks which Sidekick
/// and a one-line plan. Cards show read-only here; they are made by a server path (contract
/// section 5).
struct MakeInboxView: View {
    let center: MakeCenter

    @State private var openPerson: MakePerson?
    @State private var openThread: MakeThreadRef?
    @Environment(\.colorScheme) private var colorScheme

    private var tokens: RepairTokens {
        RepairTokens.forScheme(colorScheme)
    }

    var body: some View {
        let _ = center.revision
        let records = center.inboxRecords()
        let people = MakeRecords.people(in: records)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(MakeCopy.inboxTitle)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(tokens.ink.color)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                ForEach(people) { person in
                    Button(action: opener(for: person)) {
                        personRow(person, records: records)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if people.isEmpty {
                Text(MakeCopy.noPeople)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink2.color)
            }
        }
        .background(tokens.paper.color)
        .toolbar(.hidden, for: .navigationBar)
        .background {
            SwipeBackEnabler()
                .frame(width: 0, height: 0)
        }
        .navigationDestination(item: $openPerson) { person in
            MakeInboxPersonView(center: center, person: person)
        }
        .navigationDestination(item: $openThread) { ref in
            MakeInboxThreadView(center: center, ref: ref)
        }
        .makeLivePull(center)
        .repairUnavailableSwipe(sidekickId: MakeSidekick.inboxId)
        .onAppear(perform: openPendingThread)
        .onChange(of: center.pendingInboxThread, pendingThreadChanged)
    }

    private func opener(for person: MakePerson) -> () -> Void {
        { openPerson = person }
    }

    private func personRow(_ person: MakePerson, records: [LocalRecord]) -> some View {
        let summary = MakeInboxSummary.person(person, records: records, readMarks: center.readMarks)
        return MakePersonRow(person: person, lastLine: summary.lastLine, time: summary.time, unread: summary.unread)
    }

    /// A push for a person's message or answer opens that thread.
    private func openPendingThread() {
        guard let ref = center.pendingInboxThread else {
            return
        }
        center.pendingInboxThread = nil
        openThread = ref
    }

    private func pendingThreadChanged(_ oldValue: MakeThreadRef?, _ newValue: MakeThreadRef?) {
        openPendingThread()
    }
}

/// A person's row in the inbox: the newest line of any of their requests, and every unread item.
enum MakeInboxSummary {
    @MainActor
    static func person(_ person: MakePerson, records: [LocalRecord], readMarks: MakeReadMarks, now: Date = Date()) -> MakeRowSummary {
        let requests = MakeRecords.requests(in: records, inInbox: true, userId: person.userId)
        var unread = 0
        var newest: (date: Date, line: String?)?
        for request in requests {
            let thread = MakeRecords.thread(request.ref, in: records)
            unread += readMarks.unreadCount(thread, ref: request.ref, forFounder: true)
            let latest = thread.latestSentAt ?? request.updatedAt ?? .distantPast
            if newest == nil || latest > newest!.date {
                newest = (latest, MakeRecords.lastLine(of: thread, forFounder: true))
            }
        }
        let time = newest.flatMap(hasDate).map(labeller(now: now))
        return MakeRowSummary(lastLine: newest?.line ?? nil, time: time, unread: unread)
    }

    private static func hasDate(_ newest: (date: Date, line: String?)) -> Date? {
        newest.date == .distantPast ? nil : newest.date
    }

    private static func labeller(now: Date) -> (Date) -> String {
        { date in MakeTime.listLabel(date, now: now) }
    }

    /// The person's name, or their initial's stand-in when the person record has not come yet.
    static func displayName(_ person: MakePerson) -> String {
        person.name.isEmpty ? String(person.userId.prefix(8)) : person.name
    }

    /// A person's face colour: one of the eight tile colours (docs/DESIGN.md 2.3), the same for
    /// the same person every time.
    static func faceColours(_ person: MakePerson) -> (fill: JessOrbColor, ink: JessOrbColor) {
        let palette: [(UInt32, UInt32)] = [
            (0xFFBF00, 0x111111), (0x2E2E2E, 0xFFFFFF), (0x9CAF88, 0x111111), (0xC41E3A, 0xFFFFFF),
            (0x30D5C8, 0x111111), (0xFFE600, 0x111111), (0xC9F24D, 0x111111), (0xFF6347, 0xFFFFFF),
        ]
        var hash: UInt32 = 5381
        for byte in person.userId.utf8 {
            hash = (hash &* 33) &+ UInt32(byte)
        }
        let pair = palette[Int(hash % UInt32(palette.count))]
        return (JessOrbColor(hex: pair.0), JessOrbColor(hex: pair.1))
    }
}

struct MakePersonFace: View {
    let person: MakePerson
    let size: CGFloat

    var body: some View {
        let colours = MakeInboxSummary.faceColours(person)
        MakeAvatar(letter: String(MakeInboxSummary.displayName(person).prefix(1)).uppercased(), size: size, fill: colours.fill.color, ink: colours.ink.color)
    }
}

struct MakePersonRow: View {
    let person: MakePerson
    let lastLine: String?
    let time: String?
    let unread: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        HStack(spacing: 12) {
            MakePersonFace(person: person, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(MakeInboxSummary.displayName(person))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink.color)
                if let lastLine {
                    Text(lastLine)
                        .font(.system(size: 15))
                        .foregroundStyle(tokens.ink2.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let time {
                    Text(time)
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.ink2.color)
                }
                if unread > 0 {
                    MakeCountBadge(count: unread)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.rule.color)
                .frame(height: 1)
                .padding(.leading, 80)
        }
        .contentShape(Rectangle())
    }
}

/// One person's requests, newest first, each with its status.
struct MakeInboxPersonView: View {
    let center: MakeCenter
    let person: MakePerson

    @State private var openThread: MakeThreadRef?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = center.revision
        let tokens = RepairTokens.forScheme(colorScheme)
        let records = center.inboxRecords()
        let requests = MakeRecords.requests(in: records, inInbox: true, userId: person.userId)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: goBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                    Text(MakeCopy.inboxTitle)
                        .font(.system(size: 17))
                }
                .foregroundStyle(tokens.ink.color)
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            HStack(spacing: 12) {
                MakePersonFace(person: person, size: 56)
                Text(MakeInboxSummary.displayName(person))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(tokens.ink.color)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(requests) { request in
                        Button(action: opener(for: request.ref)) {
                            row(request, records: records)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(tokens.paper.color)
        .toolbar(.hidden, for: .navigationBar)
        .background {
            SwipeBackEnabler()
                .frame(width: 0, height: 0)
        }
        .navigationDestination(item: $openThread) { ref in
            MakeInboxThreadView(center: center, ref: ref)
        }
        .makeLivePull(center)
        .repairUnavailableSwipe(sidekickId: MakeSidekick.inboxId)
    }

    private func row(_ request: MakeRequest, records: [LocalRecord]) -> some View {
        let thread = MakeRecords.thread(request.ref, in: records)
        let summary = MakeRowSummary.make(thread: thread, request: request, readMarks: center.readMarks, forFounder: true)
        return MakeRequestRow(title: request.title, lastLine: summary.lastLine, time: summary.time, status: request.status, unread: summary.unread, showsCount: true)
    }

    private func opener(for ref: MakeThreadRef) -> () -> Void {
        { openThread = ref }
    }

    private func goBack() {
        dismiss()
    }
}

/// The founder's side of one thread: the status buttons under the header, the thread, the reply
/// pill (it writes a maker message).
struct MakeInboxThreadView: View {
    let center: MakeCenter
    let ref: MakeThreadRef

    @State private var composer = PillVoiceComposer()
    @State private var pickingBuilt = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = center.revision
        let tokens = RepairTokens.forScheme(colorScheme)
        let records = center.inboxRecords()
        let thread = MakeRecords.thread(ref, in: records)
        let person = MakeRecords.people(in: records).first(where: isThisPerson) ?? MakePerson(userId: ref.userId ?? "", name: "", firstAt: nil)
        VStack(spacing: 0) {
            MakeThreadHeader(title: MakeInboxSummary.displayName(person), subtitle: thread.request?.title, onBack: goBack) {
                MakePersonFace(person: person, size: 34)
            }
            if let request = thread.request {
                MakeStatusButtons(current: request.status, onSet: setter(for: request))
            }
            MakeThreadList(thread: thread, forFounder: true, center: center)
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
        .sheet(isPresented: $pickingBuilt) {
            if let request = thread.request {
                MakeBuiltPicker(center: center, request: request)
            }
        }
        .makeLivePull(center)
        .repairUnavailableSwipe(sidekickId: MakeSidekick.inboxId)
        .onAppear(perform: appeared)
        .onDisappear(perform: disappeared)
        .onChange(of: center.revision, revisionChanged)
    }

    private func isThisPerson(_ person: MakePerson) -> Bool {
        person.userId == ref.userId
    }

    private var pill: some View {
        let text = composer.pillText
        return PillBar(
            settled: text.settled,
            pending: text.pending,
            typed: $composer.typed,
            isTyping: $composer.isTyping,
            placeholder: MakeCopy.replyPlaceholder,
            orbState: composer.orbState,
            orbLevel: composer.orbLevel,
            onOrbTap: composer.toggleListening,
            canSend: composer.canSend,
            sendLabel: MakeCopy.sendButton,
            onSend: sendReply
        )
        .padding(.horizontal, RepairPillSpec.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func sendReply() {
        guard let words = composer.take(), let userId = ref.userId else {
            return
        }
        try? center.writer.reply(words: words, userId: userId, reqId: ref.reqId)
        syncSoon()
    }

    private func setter(for request: MakeRequest) -> (MakeStatus) -> Void {
        { status in set(status, request: request) }
    }

    /// Built needs the Sidekick and the plan: it opens the picker. The others are written at once.
    private func set(_ status: MakeStatus, request: MakeRequest) {
        if status == .built {
            pickingBuilt = true
            return
        }
        try? center.writer.setStatus(status, request: request)
        syncSoon()
    }

    private func syncSoon() {
        Task { @MainActor in
            await center.sync()
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

/// F1's four buttons; the current status is filled.
struct MakeStatusButtons: View {
    let current: MakeStatus
    let onSet: (MakeStatus) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        HStack(spacing: 6) {
            ForEach(MakeStatus.handSet, id: \.self) { status in
                let isOn = status == current
                Button(action: setter(status)) {
                    Text(status.word)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? tokens.paper.color : tokens.ink.color)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? tokens.ink.color : tokens.paper.color, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isOn ? tokens.ink.color : tokens.rule.color, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.rule.color)
                .frame(height: 1)
        }
        .background(tokens.paper.color)
    }

    private func setter(_ status: MakeStatus) -> () -> Void {
        { onSet(status) }
    }
}

/// Built: which Sidekick (`GET /make/sidekicks`) and a one-line plan, then Send.
struct MakeBuiltPicker: View {
    let center: MakeCenter
    let request: MakeRequest

    @State private var buildables: [MakeBuildable] = []
    @State private var pickedId: String?
    @State private var plan = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(MakeCopy.planPlaceholder, text: $plan)
                }
                Section {
                    if buildables.isEmpty {
                        Text(MakeCopy.noSidekicksToPick)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(buildables) { buildable in
                        Button(action: picker(for: buildable)) {
                            HStack {
                                Text(buildable.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if pickedId == buildable.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(MakeCopy.builtPickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MakeCopy.cancelButton, action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(MakeCopy.sendButton, action: send)
                        .disabled(!MakeBuiltPicker.canSend(pickedId: pickedId, plan: plan))
                }
            }
        }
        .tint(.primary)
        .task(load)
    }

    static func canSend(pickedId: String?, plan: String) -> Bool {
        pickedId != nil && !MakeWriter.trimmed(plan).isEmpty
    }

    private func load() async {
        if MakeSeeds.isOn {
            buildables = MakeSeeds.buildables
            return
        }
        buildables = await center.api.fetchSidekicks()
    }

    private func picker(for buildable: MakeBuildable) -> () -> Void {
        { pickedId = buildable.id }
    }

    private func send() {
        guard MakeBuiltPicker.canSend(pickedId: pickedId, plan: plan), let pickedId else {
            return
        }
        try? center.writer.setStatus(.built, request: request, sidekickId: pickedId, plan: plan)
        Task { @MainActor in
            await center.sync()
        }
        dismiss()
    }

    private func close() {
        dismiss()
    }
}
