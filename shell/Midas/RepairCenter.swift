import Foundation
import Observation
import UIKit

// Repair state per Sidekick (founder, 2026-10-23, docs/briefs/repair-ux-upgrade.md, S2): after
// Send the Repair tag says "On it", then "Editing" (founder, 2026-10-31) while the user is on the Sidekick being repaired, hides on
// home and in other Sidekicks, comes back on return, and shows the result there. Never in the
// island. Results come from GET /repairs/notices, matched by the phone's own report id.

/// What a repair came to, in the user's terms (server field `kind`).
enum RepairResultKind: String, Codable, Equatable, Sendable {
    case fixed
    case alreadyThere = "already_there"
    case couldntFix = "couldnt_fix"
}

extension JessRepairNotice {
    private enum CodingKeys: String, CodingKey {
        case id
        case reportId
        case text
        case kind
        case summary
        case clientReportId
    }

    // A kind this shell does not know reads as no kind, so one new kind never hides every notice
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            reportId: try container.decode(String.self, forKey: .reportId),
            text: try container.decode(String.self, forKey: .text),
            kind: rawKind.flatMap(RepairResultKind.init(rawValue:)),
            summary: try container.decodeIfPresent(String.self, forKey: .summary),
            clientReportId: try container.decodeIfPresent(String.self, forKey: .clientReportId)
        )
    }
}

/// Words on the Repair tag (docs/WRITING.md; founder's words for the fixed one, 2026-10-23). The
/// person sees "Edit", never "Repair"; after Send the tag says "On it", then "Editing" (A2); an
/// edit the agent could not make says "Taking a Deeper Look" while the founder makes it by hand,
/// so a person's edit never ends as a failure (founder, 2026-11-01,
/// docs/mockups/edit-deeper-look-2026-11-01.html; it was "Check back in some time.").
enum RepairTagCopy {
    static let repairMode = "Edit"
    static let repairing = "Editing"
    /// The first words after Send, until `RepairTagSpec.onItSeconds`.
    static let onIt = "On it"
    static let takingLonger = "Taking longer"
    static let fixedOnPage = "Edit done. Tap to update"
    /// Shown for 1 s on return when the fix landed while the user was away (founder, 2026-10-23).
    static let fixedAway = "Fixed"
    static let alreadyThere = "Already There"
    static let couldntFix = "Taking a Deeper Look"
    static let tryAgain = "Try Again"
    static let close = "Close"
    /// The X on the tag (docs/WRITING.md: the way out is always "Cancel").
    static let cancel = "Cancel"

    /// "Editing", or "Editing 2" while a second edit waits behind the first.
    static func repairing(count: Int) -> String {
        count > 1 ? "\(repairing) \(count)" : repairing
    }

    /// The words the tag shows at a moment: "On it" for the first seconds after this screen's
    /// Send, while the edit is on its way; otherwise the display's own words.
    static func words(for display: RepairTagDisplay, secondsSinceSend: Double?) -> String {
        guard case .repairing(_, let takingLonger) = display, !takingLonger, let secondsSinceSend else {
            return display.words
        }
        if secondsSinceSend >= 0 && secondsSinceSend < RepairTagSpec.onItSeconds {
            return onIt
        }
        return display.words
    }
}

/// What the tag shows on one Sidekick.
enum RepairTagDisplay: Equatable, Sendable {
    /// The three-finger swipe is on: the tag dropped out of the island.
    case repairMode
    /// `count` repairs on their way; `takingLonger` after 10 minutes.
    case repairing(count: Int, takingLonger: Bool)
    /// `onPage`: the fix landed while the user was on the Sidekick, so a tap updates the page.
    /// Otherwise the page already opened with it.
    case fixed(onPage: Bool, summary: String?)
    case alreadyThere(summary: String?)
    case couldntFix
    /// The setting lane made the change (founder, 2026-11-22): "Changed" with Undo.
    case changed
    /// Undo put the old values back.
    case undone
    /// The sort asks one question; a tap opens repair mode again with the card.
    case question
    /// Not a request, or the shell can't: the server's line, for a moment.
    case laneMessage(String)

    var words: String {
        switch self {
        case .repairMode:
            return RepairTagCopy.repairMode
        case .repairing(let count, let takingLonger):
            return takingLonger ? RepairTagCopy.takingLonger : RepairTagCopy.repairing(count: count)
        case .fixed(let onPage, _):
            return onPage ? RepairTagCopy.fixedOnPage : RepairTagCopy.fixedAway
        case .alreadyThere:
            return RepairTagCopy.alreadyThere
        case .couldntFix:
            return RepairTagCopy.couldntFix
        case .changed:
            return RepairLaneCopy.changed
        case .undone:
            return RepairLaneCopy.undone
        case .question:
            return RepairLaneCopy.oneQuestion
        case .laneMessage(let text):
            return text
        }
    }

    /// The one-line summary a tap shows, when there is one.
    var summary: String? {
        switch self {
        case .fixed(_, let summary), .alreadyThere(let summary):
            return summary
        case .repairMode, .repairing, .couldntFix, .changed, .undone, .question, .laneMessage:
            return nil
        }
    }

    /// An X on the tag cancels the repair (founder, 2026-11-22): "Editing…", "1 question" and a
    /// "Couldn't fix" result ("Taking a Deeper Look"). Never on "Edit done. Tap to update": tapping it
    /// updates.
    var cancellable: Bool {
        switch self {
        case .repairing, .question, .couldntFix:
            return true
        case .repairMode, .fixed, .alreadyThere, .changed, .undone, .laneMessage:
            return false
        }
    }

    /// The tag leaves on its own: Already There after 2.4 s, "Fixed" (the fix landed while the
    /// user was away, the page already opened with it) after 1 s. "Taking a Deeper Look" stays
    /// until the founder's fix lands and turns it into a fix; "Tap to update" until tapped
    /// (founder, 2026-10-23, 2026-11-01).
    var leavesOnItsOwn: Bool {
        leavesAfterSeconds != nil
    }

    var leavesAfterSeconds: Double? {
        switch self {
        case .alreadyThere:
            return RepairTagSpec.leaveAfterSeconds
        case .fixed(let onPage, _):
            return onPage ? nil : RepairTagSpec.fixedAwayShowsSeconds
        case .changed:
            return RepairLaneSpec.changedSeconds
        case .undone:
            return RepairLaneSpec.undoneSeconds
        case .laneMessage:
            return RepairLaneSpec.messageSeconds
        case .repairMode, .repairing, .couldntFix, .question:
            return nil
        }
    }
}

/// One repair sent and not answered yet.
struct RepairPending: Codable, Equatable, Sendable {
    let clientReportId: String
    let sidekickId: String
    let transcript: String
    let sentAt: Date
}

/// One answer not yet put away.
struct RepairOutcome: Codable, Equatable, Sendable {
    let clientReportId: String
    let sidekickId: String
    let kind: RepairResultKind
    let summary: String?
    let arrivedAt: Date
    /// The user was on that Sidekick when it came: a fix then needs a tap to update the page.
    let arrivedWhileOpen: Bool
}

/// What is kept across launches, without images (the sent reports sit in their own folder).
struct RepairCenterState: Codable, Equatable, Sendable {
    var pending: [RepairPending] = []
    var outcomes: [RepairOutcome] = []
}

/// The tag's rules, pure so tests can check them.
enum RepairTagRules {
    static func display(state: RepairCenterState, sidekickId: String, repairModeOn: Bool, now: Date) -> RepairTagDisplay? {
        if repairModeOn {
            return .repairMode
        }
        let waiting = state.pending.filter { $0.sidekickId == sidekickId }
        // A deeper look gives way to a newer edit sent on the same Sidekick while it runs: the
        // tag says Editing, then Taking a Deeper Look again once that one is answered
        if let outcome = state.outcomes.first(where: { $0.sidekickId == sidekickId }), !(outcome.kind == .couldntFix && !waiting.isEmpty) {
            switch outcome.kind {
            case .fixed:
                return .fixed(onPage: outcome.arrivedWhileOpen, summary: outcome.summary)
            case .alreadyThere:
                return .alreadyThere(summary: outcome.summary)
            case .couldntFix:
                return .couldntFix
            }
        }
        guard let oldest = waiting.map(\.sentAt).min() else {
            return nil
        }
        let takingLonger = now.timeIntervalSince(oldest) >= RepairTagSpec.takingLongerAfterSeconds
        return .repairing(count: waiting.count, takingLonger: takingLonger)
    }

    /// A summary as the tag shows it: its first line, at most 200 characters.
    static func oneLine(_ summary: String?) -> String? {
        guard let summary else {
            return nil
        }
        let firstLine = summary.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return nil
        }
        return trimmed.count > 200 ? String(trimmed.prefix(199)) + "…" : trimmed
    }
}

/// Keeps the state on disk, so "Repairing" is still there after a relaunch.
struct RepairCenterFile: Sendable {
    let fileURL: URL

    static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDirectory.appending(path: "repair-center.json")
    }

    func load() -> RepairCenterState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL), let state = try? decoder.decode(RepairCenterState.self, from: data) else {
            return RepairCenterState()
        }
        return state
    }

    func save(_ state: RepairCenterState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else {
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Sends a report again (Try Again). The live one is the repair uploader.
@MainActor
protocol RepairResending: AnyObject {
    func send(_ report: RepairReport) async
}

extension RepairUploader: RepairResending {}

/// Tells the uploader a repair was cancelled (X on the tag): it is not sent, or the server hears.
@MainActor
protocol RepairCancelling: AnyObject {
    func cancel(clientReportId: String) async
}

extension RepairUploader: RepairCancelling {}

/// The repairs this phone sent, per Sidekick, and what came of them.
@MainActor
@Observable
final class RepairCenter {
    private(set) var state: RepairCenterState
    /// The Sidekick on screen, nil on home.
    private(set) var openSidekickId: String?

    @ObservationIgnored private let notices: JessRepairNoticesAPI
    @ObservationIgnored private let resender: RepairResending
    /// Each sent report, kept for "what was sent" and Try Again until its result is put away.
    @ObservationIgnored private let sentReports: RepairOutbox
    @ObservationIgnored private let file: RepairCenterFile?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let pollSeconds: Double
    /// How often to ask while only deeper looks wait: the founder's fix takes hours, not seconds.
    @ObservationIgnored private let deeperLookPollSeconds: Double
    /// A fix landed for a Sidekick that is not on screen: the shell refreshes its listing so jess
    /// and the next open get the new version.
    @ObservationIgnored var onFixedAway: ((String) -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isChecking = false

    // MARK: Lanes after Send (founder, 2026-11-22; RepairLaneFollow.swift)

    /// Lane results the tag shows: "Changed", "1 question", a message. Not kept across launches: a
    /// relaunch asks the lane of each pending report again.
    private(set) var laneNotes: [RepairLaneNote] = []
    /// GET /repairs/lanes and Undo. Nil: the tag waits for notices only, as before the lanes.
    @ObservationIgnored private let lanes: RepairLaneAPI?
    /// Reports whose lane is an edit (code, look): no need to ask again.
    @ObservationIgnored private var settledLanes: Set<String> = []
    /// How long each report was listened to, for jess when its lane is jess_command.
    @ObservationIgnored private var listenMsByReport: [String: Int] = [:]
    @ObservationIgnored private let lanePollSeconds: Double
    @ObservationIgnored private let laneWatchSeconds: Double
    @ObservationIgnored private var laneWatch: Task<Void, Never>?
    @ObservationIgnored private var isFollowingLanes = false
    /// The setting lane changed settings:self (or Undo put it back): pull it so the page redraws.
    @ObservationIgnored var onSettingChanged: ((String) -> Void)?
    /// jess_command: the words go to jess as if said to jess.
    @ObservationIgnored var onJessCommand: ((_ transcript: String, _ listenMs: Int) -> Void)?

    // MARK: X on the tag, and questions that open by themselves (founder, 2026-11-22)

    /// The uploader: a cancelled report is not sent, or the server is told. Nil: the phone only.
    @ObservationIgnored private let canceller: RepairCancelling?
    /// Whether the app is in front; a question that arrives in the background waits on the tag.
    @ObservationIgnored private let isAppActive: @MainActor () -> Bool
    /// Questions that open repair mode by themselves: they came back while the person was on that
    /// Sidekick with the app in front. Taken once by `questionToOpen`; dropped when the person leaves
    /// the Sidekick or the app goes to the background (the "1 question" tag stays for a tap).
    private(set) var questionsToOpen: [String] = []

    init(notices: JessRepairNoticesAPI, resender: RepairResending, sentReports: RepairOutbox, file: RepairCenterFile?, now: @escaping () -> Date = Date.init, pollSeconds: Double = 15, deeperLookPollSeconds: Double = 60, lanes: RepairLaneAPI? = nil, lanePollSeconds: Double = RepairLaneSpec.fastPollSeconds, laneWatchSeconds: Double = RepairLaneSpec.fastWatchSeconds, canceller: RepairCancelling? = nil, isAppActive: @escaping @MainActor () -> Bool = RepairCenter.alwaysActive) {
        self.notices = notices
        self.resender = resender
        self.sentReports = sentReports
        self.file = file
        self.now = now
        self.pollSeconds = pollSeconds
        self.deeperLookPollSeconds = deeperLookPollSeconds
        self.lanes = lanes
        self.lanePollSeconds = lanePollSeconds
        self.laneWatchSeconds = laneWatchSeconds
        self.canceller = canceller
        self.isAppActive = isAppActive
        self.state = file?.load() ?? RepairCenterState()
    }

    nonisolated static func alwaysActive() -> Bool {
        true
    }

    static func defaultSentReportsURL() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDirectory.appending(path: "repairs-sent")
    }

    // MARK: Where the user is

    func sidekickOpened(_ sidekickId: String) {
        openSidekickId = sidekickId
    }

    /// Leaving a Sidekick: a "Tap to update" there is done with, the next open loads the new page.
    func sidekickClosed(_ sidekickId: String) {
        if openSidekickId == sidekickId {
            openSidekickId = nil
        }
        // Left before the question could open: it waits on the tag
        dropQuestionsToOpen(on: sidekickId)
        let finishedFixes = state.outcomes.filter { $0.sidekickId == sidekickId && $0.kind == .fixed && $0.arrivedWhileOpen }
        for outcome in finishedFixes {
            putAway(clientReportId: outcome.clientReportId)
        }
    }

    // MARK: Showing

    /// A lane's result comes first (it is the newest thing that happened on that Sidekick); then
    /// the edits on their way and their results.
    func display(for sidekickId: String, repairModeOn: Bool) -> RepairTagDisplay? {
        if !repairModeOn, let note = shownNote(for: sidekickId), let noteDisplay = RepairLaneRules.display(for: note, now: now()) {
            return noteDisplay
        }
        return RepairTagRules.display(state: state, sidekickId: sidekickId, repairModeOn: repairModeOn, now: now())
    }

    /// The newest lane result on that Sidekick that still shows.
    func shownNote(for sidekickId: String) -> RepairLaneNote? {
        let currentTime = now()
        return laneNotes.last { note in
            note.sidekickId == sidekickId && RepairLaneRules.display(for: note, now: currentTime) != nil
        }
    }

    /// The report a "1 question" tag asks about, with its card, for opening repair mode again.
    func waitingQuestion(for sidekickId: String) -> (note: RepairLaneNote, question: RepairQuestion, repairId: String, report: RepairReport?)? {
        guard let note = shownNote(for: sidekickId), case .question(let question, let repairId) = note.kind else {
            return nil
        }
        let report = sentReports.pending().first { $0.clientReportId == note.clientReportId }
        return (note, question, repairId, report)
    }

    /// The repair a tap on "Repairing" shows: the newest one sent on that Sidekick.
    func latestPending(for sidekickId: String) -> RepairPending? {
        state.pending.last { $0.sidekickId == sidekickId }
    }

    /// The outcome the tag is showing on that Sidekick.
    func shownOutcome(for sidekickId: String) -> RepairOutcome? {
        state.outcomes.first { $0.sidekickId == sidekickId }
    }

    /// The circled screenshot that was sent, for "what was sent".
    func sentDrawing(clientReportId: String) -> UIImage? {
        guard let report = sentReports.pending().first(where: { $0.clientReportId == clientReportId }) else {
            return nil
        }
        return UIImage(data: report.drawingPNG)
    }

    // MARK: Sending

    func didSend(_ report: RepairReport) {
        try? sentReports.enqueue(report)
        let pending = RepairPending(clientReportId: report.clientReportId, sidekickId: report.sidekickId, transcript: report.transcript, sentAt: now())
        state.pending.append(pending)
        persist()
        startPolling()
    }

    /// Couldn't Fix → Try Again: the same report again, under a new phone id.
    func tryAgain(clientReportId: String) async {
        guard let report = sentReports.pending().first(where: { $0.clientReportId == clientReportId }) else {
            putAway(clientReportId: clientReportId)
            return
        }
        putAway(clientReportId: clientReportId)
        let resent = report.resent(clientReportId: UUID().uuidString)
        didSend(resent)
        await resender.send(resent)
    }

    /// The tag that left on its own, or was tapped away: a lane's result if one shows, else the
    /// edit's outcome.
    func putAwayShown(for sidekickId: String) {
        if let note = shownNote(for: sidekickId) {
            putAwayNote(clientReportId: note.clientReportId)
            return
        }
        guard let outcome = shownOutcome(for: sidekickId) else {
            return
        }
        putAway(clientReportId: outcome.clientReportId)
    }

    /// A lane's result is done with (it left, or its question was answered). A question's report
    /// leaves the sent reports with it.
    func putAwayNote(clientReportId: String) {
        let wasQuestion = laneNotes.contains { note in
            guard note.clientReportId == clientReportId, case .question = note.kind else {
                return false
            }
            return true
        }
        laneNotes.removeAll { $0.clientReportId == clientReportId }
        questionsToOpen.removeAll { $0 == clientReportId }
        let stillPending = state.pending.contains { $0.clientReportId == clientReportId }
        if wasQuestion && !stillPending {
            sentReports.remove(clientReportId: clientReportId)
        }
    }

    /// Close, a tapped "Tap to update", or a tag that left on its own.
    func putAway(clientReportId: String) {
        state.outcomes.removeAll { $0.clientReportId == clientReportId }
        state.pending.removeAll { $0.clientReportId == clientReportId }
        sentReports.remove(clientReportId: clientReportId)
        persist()
    }

    // MARK: Results

    /// Edits the agent could not make, waiting for the founder's fix (founder, 2026-11-01).
    var deeperLooks: [RepairOutcome] {
        state.outcomes.filter { $0.kind == .couldntFix }
    }

    /// Something is still on its way: a sent edit, or a deeper look.
    private var isWaiting: Bool {
        !state.pending.isEmpty || !deeperLooks.isEmpty
    }

    // MARK: Lanes

    /// The upload went (or did not): a reply that already names the lane is used at once; otherwise
    /// the tag asks the lane route every `lanePollSeconds` for a while.
    func uploaded(report: RepairReport, reply: RepairSortReply?, listenMs: Int) {
        uploaded(clientReportId: report.clientReportId, reply: reply, listenMs: listenMs)
    }

    func uploaded(clientReportId: String, reply: RepairSortReply?, listenMs: Int) {
        listenMsByReport[clientReportId] = listenMs
        if let reply, reply.laneKnown {
            receiveLane(reply, clientReportId: clientReportId)
            return
        }
        startLaneWatch()
    }

    /// Reports sent from this phone whose lane is not known yet.
    private var unsortedPending: [RepairPending] {
        state.pending.filter { !settledLanes.contains($0.clientReportId) }
    }

    private func startLaneWatch() {
        guard laneWatch == nil, lanes != nil else {
            return
        }
        laneWatch = Task { @MainActor [weak self] in
            await self?.watchLanes()
        }
    }

    private func watchLanes() async {
        let deadline = Date().addingTimeInterval(laneWatchSeconds)
        while !unsortedPending.isEmpty && Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(lanePollSeconds))
            await followLanes()
        }
        laneWatch = nil
    }

    /// Asks the lane of every report still waiting for one. Not sent yet or offline: next time.
    /// `includingCode`: also the edits already in the code lane, because the repair agent can turn
    /// one into a question when it cannot tell what to build (founder, 2026-11-23: "unclear code
    /// requests become a question, never a refusal"); the slower notices poll asks with it.
    func followLanes(includingCode: Bool = false) async {
        guard let lanes, !isFollowingLanes else {
            return
        }
        isFollowingLanes = true
        defer {
            isFollowingLanes = false
        }
        let reportsToAsk = includingCode ? state.pending : unsortedPending
        for pending in reportsToAsk {
            let check = await lanes.lane(clientReportId: pending.clientReportId)
            if case .reply(let reply) = check {
                receiveLane(reply, clientReportId: pending.clientReportId)
            }
        }
    }

    /// What the lane came to, on the tag of the report it belongs to. A report no longer pending
    /// (put away, or answered by a notice) is left alone.
    func receiveLane(_ reply: RepairSortReply, clientReportId: String) {
        guard let pending = state.pending.first(where: { $0.clientReportId == clientReportId }) else {
            return
        }
        switch RepairLaneRules.step(for: reply) {
        case .keepWatching:
            return
        case .staysEditing:
            settledLanes.insert(clientReportId)
        case .changed(let repairId):
            finishPending(pending, keepReport: false)
            addNote(pending, kind: .changed(repairId: repairId))
            onSettingChanged?(pending.sidekickId)
        case .toJess:
            let listenMs = listenMsByReport[clientReportId] ?? 0
            finishPending(pending, keepReport: false)
            onJessCommand?(pending.transcript, listenMs)
        case .question(let question, let repairId):
            // The report stays with the sent ones: the card's answer joins it
            finishPending(pending, keepReport: true)
            addNote(pending, kind: .question(question, repairId: repairId))
            // On that Sidekick with the app in front: repair mode opens by itself with the card
            if openSidekickId == pending.sidekickId && isAppActive() {
                questionsToOpen.append(pending.clientReportId)
            }
        case .message(let text):
            finishPending(pending, keepReport: false)
            addNote(pending, kind: .message(text))
        case .gone:
            finishPending(pending, keepReport: false)
        }
    }

    /// No edit is on its way for this report: it leaves the pending ones.
    private func finishPending(_ pending: RepairPending, keepReport: Bool) {
        state.pending.removeAll { $0.clientReportId == pending.clientReportId }
        settledLanes.remove(pending.clientReportId)
        listenMsByReport[pending.clientReportId] = nil
        if !keepReport {
            sentReports.remove(clientReportId: pending.clientReportId)
        }
        persist()
    }

    private func addNote(_ pending: RepairPending, kind: RepairLaneNote.Kind) {
        laneNotes.removeAll { $0.clientReportId == pending.clientReportId }
        laneNotes.append(RepairLaneNote(clientReportId: pending.clientReportId, sidekickId: pending.sidekickId, kind: kind, arrivedAt: now()))
    }

    // MARK: Questions that open by themselves

    /// The question to open now on that Sidekick, taken once; nil when there is none, the person is
    /// not on it, the app is not in front, or a repair layer is open (it waits until that closes).
    func questionToOpen(for sidekickId: String, layerOpen: Bool) -> (note: RepairLaneNote, question: RepairQuestion, repairId: String, report: RepairReport?)? {
        guard !layerOpen, openSidekickId == sidekickId, isAppActive() else {
            return nil
        }
        guard let waiting = waitingQuestion(for: sidekickId), questionsToOpen.contains(waiting.note.clientReportId) else {
            return nil
        }
        questionsToOpen.removeAll { $0 == waiting.note.clientReportId }
        return waiting
    }

    /// The app went to the background: the questions waiting to open stay on the tag instead.
    func appWentToBackground() {
        questionsToOpen.removeAll()
    }

    private func dropQuestionsToOpen(on sidekickId: String) {
        let onThatSidekick = Set(laneNotes.filter { $0.sidekickId == sidekickId }.map(\.clientReportId))
        questionsToOpen.removeAll { onThatSidekick.contains($0) }
    }

    // MARK: X on the tag

    /// X on the tag (founder, 2026-11-22): what the tag shows on that Sidekick goes at once, no
    /// confirm. "1 question": that report; "Editing": every edit on its way there; "Taking a Deeper
    /// Look": that result, cleared from the saved outcomes. Reports still on the phone are not sent;
    /// the server hears of the others (the returned task, for tests; the tag never waits on it).
    @discardableResult
    func cancelShown(for sidekickId: String) -> Task<Void, Never>? {
        guard let display = display(for: sidekickId, repairModeOn: false), display.cancellable else {
            return nil
        }
        var cancelledIds: [String] = []
        switch display {
        case .question:
            if let note = shownNote(for: sidekickId) {
                cancelledIds.append(note.clientReportId)
                laneNotes.removeAll { $0.clientReportId == note.clientReportId }
                questionsToOpen.removeAll { $0 == note.clientReportId }
                state.pending.removeAll { $0.clientReportId == note.clientReportId }
                sentReports.remove(clientReportId: note.clientReportId)
            }
        case .repairing:
            let onItsWay = state.pending.filter { $0.sidekickId == sidekickId }
            for pending in onItsWay {
                cancelledIds.append(pending.clientReportId)
                settledLanes.remove(pending.clientReportId)
                listenMsByReport[pending.clientReportId] = nil
                sentReports.remove(clientReportId: pending.clientReportId)
            }
            state.pending.removeAll { $0.sidekickId == sidekickId }
        case .couldntFix:
            // The edit already ended on the server: only the phone's result is cleared
            let deeperLooksHere = state.outcomes.filter { $0.sidekickId == sidekickId && $0.kind == .couldntFix }
            for outcome in deeperLooksHere {
                sentReports.remove(clientReportId: outcome.clientReportId)
            }
            state.outcomes.removeAll { $0.sidekickId == sidekickId && $0.kind == .couldntFix }
        case .repairMode, .fixed, .alreadyThere, .changed, .undone, .laneMessage:
            return nil
        }
        persist()
        guard let canceller, !cancelledIds.isEmpty else {
            return nil
        }
        return Task { @MainActor in
            for clientReportId in cancelledIds {
                await canceller.cancel(clientReportId: clientReportId)
            }
        }
    }

    /// A card the Worker dropped (unanswered for 2 minutes) leaves with its report.
    func dropExpiredQuestions() {
        let currentTime = now()
        let expired = laneNotes.filter { note in
            guard case .question = note.kind else {
                return false
            }
            return RepairLaneRules.display(for: note, now: currentTime) == nil
        }
        for note in expired {
            putAwayNote(clientReportId: note.clientReportId)
        }
    }

    /// Undo on "Changed": the Worker puts the old values back, the page redraws, the tag says
    /// "Undone". Did not go through: "Changed" stays, so Undo can be tapped again.
    func undoChange(clientReportId: String) async {
        guard let lanes, let note = laneNotes.first(where: { $0.clientReportId == clientReportId }), case .changed(let repairId) = note.kind, let repairId else {
            return
        }
        guard await lanes.undo(repairId: repairId) else {
            return
        }
        laneNotes.removeAll { $0.clientReportId == clientReportId }
        laneNotes.append(RepairLaneNote(clientReportId: clientReportId, sidekickId: note.sidekickId, kind: .undone, arrivedAt: now()))
        onSettingChanged?(note.sidekickId)
    }

    /// One look at the notices: each one for a repair this phone sent becomes its outcome and is
    /// marked seen. Others (a repair jess sent) are left alone. A deeper look keeps listening:
    /// the founder's fix arrives later as a fixed notice for the same report.
    func check() async {
        guard !isChecking, isWaiting else {
            return
        }
        isChecking = true
        defer {
            isChecking = false
        }
        // A report sent while offline, or one the fast watch gave up on, learns its lane here; an
        // edit in the code lane learns here that the repair agent asked a question instead
        await followLanes(includingCode: true)
        dropExpiredQuestions()
        guard let notices = await notices.notices() else {
            return
        }
        for notice in notices {
            guard let clientReportId = notice.clientReportId else {
                continue
            }
            if let pending = state.pending.first(where: { $0.clientReportId == clientReportId }) {
                receive(notice, for: pending)
                await self.notices.markSeen(id: notice.id)
            } else if let deeperLook = deeperLooks.first(where: { $0.clientReportId == clientReportId }) {
                receive(notice, after: deeperLook)
                await self.notices.markSeen(id: notice.id)
            }
        }
    }

    /// The founder's fix for a deeper look: it takes the deeper look's place, as if the edit had
    /// landed now. Another could-not notice for it changes nothing.
    private func receive(_ notice: JessRepairNotice, after deeperLook: RepairOutcome) {
        guard notice.resultKind != .couldntFix else {
            return
        }
        let isOpen = openSidekickId == deeperLook.sidekickId
        let outcome = RepairOutcome(
            clientReportId: deeperLook.clientReportId,
            sidekickId: deeperLook.sidekickId,
            kind: notice.resultKind,
            summary: RepairTagRules.oneLine(notice.summary),
            arrivedAt: now(),
            arrivedWhileOpen: isOpen
        )
        state.outcomes.removeAll { $0.clientReportId == deeperLook.clientReportId }
        state.outcomes.append(outcome)
        sentReports.remove(clientReportId: deeperLook.clientReportId)
        persist()
        if outcome.kind == .fixed && !isOpen {
            onFixedAway?(deeperLook.sidekickId)
        }
    }

    private func receive(_ notice: JessRepairNotice, for pending: RepairPending) {
        let isOpen = openSidekickId == pending.sidekickId
        let outcome = RepairOutcome(
            clientReportId: pending.clientReportId,
            sidekickId: pending.sidekickId,
            kind: notice.resultKind,
            summary: RepairTagRules.oneLine(notice.summary),
            arrivedAt: now(),
            arrivedWhileOpen: isOpen
        )
        state.pending.removeAll { $0.clientReportId == pending.clientReportId }
        state.outcomes.append(outcome)
        // A deeper look keeps the report ("what was sent") until the founder's fix lands
        if outcome.kind != .couldntFix {
            sentReports.remove(clientReportId: pending.clientReportId)
        }
        persist()
        if outcome.kind == .fixed && !isOpen {
            onFixedAway?(pending.sidekickId)
        }
    }

    /// Asks every `pollSeconds` while a repair is on its way, every `deeperLookPollSeconds` while
    /// only deeper looks wait, then stops.
    func startPolling() {
        guard pollTask == nil, isWaiting else {
            return
        }
        pollTask = Task { @MainActor [weak self] in
            await self?.pollUntilAnswered()
        }
    }

    private func pollUntilAnswered() async {
        while isWaiting && !Task.isCancelled {
            let seconds = state.pending.isEmpty ? deeperLookPollSeconds : pollSeconds
            try? await Task.sleep(for: .seconds(seconds))
            await check()
        }
        pollTask = nil
    }

    private func persist() {
        file?.save(state)
    }
}
