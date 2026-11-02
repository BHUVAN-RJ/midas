import Foundation
import Observation
import UIKit

// jess in the background, one result card (founder, 2026-10-22; docs/PRODUCT.md "jess in the
// background, one result card, jess for everyone"). Once speech ends, the request is finished in
// the background: iOS background time covers the round trip, and leaving the Listening screen,
// going home or locking the phone does not cancel it. Every result is one card at the top of the
// home page (done: green core and the Sidekick's own line; not done: red core, what was said and
// Try Again; Sent to Repair), kept until dismissed, newest first. No iOS notification is sent.
//
// Exactly once: the request is written to disk before it is sent, and marked applied in the same
// main-actor turn that writes its ops (JessRouter's `onApplied`), so a request iOS stopped is
// finished on the next open: an applied one only shows its card, any other is sent again. Cards
// and requests share one file, so a request and its card change together.
//
// The queue and the Workdesk (founder, 2026-10-22; docs/PRODUCT.md "jess queue, instant
// acknowledgement and the Workdesk"): every send carries the request's id, and the server keeps
// its answer under it, so a request sent again is never run twice. A request that got no answer
// (cut off) stays queued with a "Waiting for Connection" card and is sent again when Midas opens,
// the network comes back, the jess screen opens, and every few seconds while Midas is on screen;
// after 1 hour from when it was said it gives up as Not Done. A request sent to repair waits on
// its card until the repair is live: the same card then turns done or not done and moves to the
// top. The Workdesk log keeps every task, newest first (the last 200), apart from the home cards:
// dismissing a home card leaves its task in the log.

/// One result card at the top of the home page.
struct JessResultCard: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        /// Sent; the answer is not in yet.
        case working
        /// The Sidekick's own line and the time it set, if any.
        case done(text: String, at: String?, allDay: Bool, timeZone: String?)
        case notDone
        /// `link`: the repair the Workdesk card waits for; nil from an older server.
        case sentToRepair(sidekickName: String, link: JessRepairLink? = nil)
        /// Cut off: no answer yet, sent again by itself.
        case waitingForConnection
    }

    let id: UUID
    var kind: Kind
    /// What was said; empty for a result the backend finished (jess grows the Sidekick).
    let transcript: String
    var createdAt: Date
    /// The Sidekick jess chose, for the Workdesk card's second line; nil until it is known.
    var sidekickName: String? = nil
    /// The records a done task changed: the Workdesk card opens its Sidekick there (founder,
    /// 2026-10-31, JessChangeLink.swift). Nil for every other result and on older cards.
    var link: JessChangeLink? = nil
    /// A repair this card waits on could not be made by the agent; the founder is making it by
    /// hand (founder, 2026-11-01). Nil on older cards and once the card settles.
    var takingDeeperLook: Bool? = nil

    var orbState: JessOrbState {
        switch kind {
        case .working:
            return .thinking
        case .done, .sentToRepair:
            return .added
        case .notDone:
            return .failed
        case .waitingForConnection:
            return .idle
        }
    }

    static func kind(for result: JessResult) -> Kind {
        switch result {
        case .done(let text, let at, let allDay, let timeZone):
            return .done(text: text, at: at, allDay: allDay ?? false, timeZone: timeZone)
        case .sentToRepair(let sidekickName, let link):
            return .sentToRepair(sidekickName: sidekickName, link: link)
        case .notDone:
            return .notDone
        case .cutOff:
            return .waitingForConnection
        }
    }
}

/// A request sent to jess and not finished yet.
struct JessPendingRequest: Codable, Equatable, Sendable {
    /// The same id as its card.
    let id: UUID
    let transcript: String
    let listenMs: Int
    /// When and where it was said: a request finished later keeps its own time.
    let saidAt: Date
    let timeZone: String
    /// Set in the turn its ops were written: the result to show, never to run again.
    var applied: JessResultCard.Kind?
    /// The id the server keeps its answer under; nil means `id`. Try Again sends the same words
    /// under a new one, so the server runs them again instead of giving the kept answer.
    var serverRequestId: String? = nil
    /// The records the applied ops changed, written in the same turn as `applied`, so a request
    /// finished after iOS stopped Midas still links to its change.
    var appliedLink: JessChangeLink? = nil

    var sentRequestId: String {
        serverRequestId ?? id.uuidString.lowercased()
    }
}

/// A card swiped off the Workdesk (founder, 2026-11-02, build 22 small fixes): once deleted it stays
/// deleted. Its request may still finish, and a grow result may still come for it, but no card shows
/// again for either.
struct JessDeletedCard: Codable, Equatable, Sendable {
    let cardId: UUID
    /// The grow request the card waited on, if any (its result settles nothing and shows nothing).
    let pendingId: String?
}

/// The cards, the unfinished requests and the Workdesk log, in one file per server.
struct JessResultsState: Codable, Equatable, Sendable {
    var cards: [JessResultCard] = []
    var requests: [JessPendingRequest] = []
    /// Every task, newest first; a file from before the Workdesk starts it from its cards.
    var log: [JessResultCard] = []
    /// Cards deleted from the Workdesk, newest last; a file from before this has none.
    var deleted: [JessDeletedCard] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case cards
        case requests
        case log
        case deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cards = try container.decode([JessResultCard].self, forKey: .cards)
        requests = try container.decode([JessPendingRequest].self, forKey: .requests)
        log = try container.decodeIfPresent([JessResultCard].self, forKey: .log) ?? cards
        deleted = try container.decodeIfPresent([JessDeletedCard].self, forKey: .deleted) ?? []
    }
}

/// Where the cards and requests are kept. Tests use a temporary file.
@MainActor
final class JessResultsFile {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// One file per server, like the Sidekick directory.
    static func defaultFileURL(platformOrigin: URL = PlatformConfig.platformOrigin) -> URL {
        let host = platformOrigin.host() ?? "unknown"
        return URL.applicationSupportDirectory.appending(path: "midas-jess-results-\(host).json")
    }

    func load() -> JessResultsState {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return JessResultsState()
        }
        let decodedState = try? JSONDecoder().decode(JessResultsState.self, from: fileData)
        return decodedState ?? JessResultsState()
    }

    func save(_ state: JessResultsState) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let encodedState = try? JSONEncoder().encode(state) else {
            return
        }
        // Atomic and with complete file protection off until first unlock, so a request written
        // just before the phone locks can still be finished in the background
        try? encodedState.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// iOS background time for one request. Tests pass a stand-in that can end the time early.
@MainActor
protocol JessBackgroundTime {
    /// `expired` runs when iOS ends the time early; the time is ended by the caller either way.
    func begin(expired: @escaping @MainActor () -> Void) -> Int
    func end(_ token: Int)
}

/// `UIApplication.beginBackgroundTask`: about 30 seconds after Midas leaves the screen, enough for
/// jess's round trip (about 14 s on the server, 2026-10-22).
@MainActor
struct SystemJessBackgroundTime: JessBackgroundTime {
    static let taskName = "jess request"

    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        let identifier = UIApplication.shared.beginBackgroundTask(withName: Self.taskName) {
            MainActor.assumeIsolated {
                expired()
            }
        }
        return identifier.rawValue
    }

    func end(_ token: Int) {
        let identifier = UIBackgroundTaskIdentifier(rawValue: token)
        if identifier != .invalid {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }
}

/// JessRouter.route with a request's own time and zone, and the hook that runs once its ops are
/// written.
typealias JessRouteCall = @MainActor (_ transcript: String, _ listenMs: Int, _ saidAt: Date, _ timeZone: TimeZone, _ onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult

/// What the cards need from the rest of the shell; tests pass stand-ins.
struct JessResultsDependencies {
    var route: JessRouteCall
    var backgroundTime: JessBackgroundTime
    var isSignedIn: @MainActor () -> Bool
    /// Midas is on screen (an answer lost while away is sent again at once).
    var isInForeground: @MainActor () -> Bool
    var now: @MainActor () -> Date
    var timeZone: @MainActor () -> TimeZone
    /// A cut-off request gives up as Not Done this long after it was said (founder, 2026-10-22).
    var giveUpAfter: TimeInterval = 60 * 60
    /// How soon a cut-off request is sent again while Midas is on screen; nil: only on the
    /// triggers (open, network back, jess screen).
    var foregroundRetryDelay: Duration? = .seconds(15)
}

@MainActor
@Observable
final class JessResults {
    /// The Workdesk keeps this many tasks on the phone (founder default, 2026-10-22).
    static let logLimit = 200

    /// Newest first.
    private(set) var cards: [JessResultCard]
    /// The Workdesk: every task, newest first, the last `logLimit`.
    private(set) var log: [JessResultCard]

    @ObservationIgnored private var state: JessResultsState
    @ObservationIgnored private let file: JessResultsFile
    @ObservationIgnored private let dependencies: JessResultsDependencies
    /// Requests being sent by this process; the others on disk are finished by `resume()`.
    @ObservationIgnored private var runningIds: Set<UUID> = []
    /// Requests whose background time iOS ended before the answer came.
    @ObservationIgnored private var expiredIds: Set<UUID> = []
    @ObservationIgnored private var isRetryScheduled = false

    init(file: JessResultsFile, dependencies: JessResultsDependencies) {
        self.file = file
        self.dependencies = dependencies
        let loaded = file.load()
        self.state = loaded
        self.cards = loaded.cards
        self.log = loaded.log
    }

    /// The cards the home page shows: Not Done only, until swiped away. Done, Working, Sent to
    /// Edit and Waiting for Connection are on the Workdesk only (founder, 2026-10-31,
    /// docs/briefs/build-22-2026-10-31.md).
    var homeCards: [JessResultCard] {
        var shown: [JessResultCard] = []
        for card in cards where Self.showsOnHome(card) {
            shown.append(card)
        }
        return shown
    }

    static func showsOnHome(_ card: JessResultCard) -> Bool {
        card.kind == .notDone
    }

    /// Swiped away on the Workdesk: the task leaves the log, and its home card with it, for good
    /// (founder, 2026-11-02). A request still on its way finishes, but shows no card.
    func removeFromLog(cardId: UUID) {
        var removed: JessResultCard?
        if let index = logIndex(cardId) {
            removed = state.log.remove(at: index)
        }
        if let index = cardIndex(cardId) {
            let homeCard = state.cards.remove(at: index)
            removed = removed ?? homeCard
        }
        guard let removed else {
            return
        }
        // Kept so a late answer or grow result for this card is dropped, not shown as a new card
        var pendingId: String?
        if case .sentToRepair(_, let link) = removed.kind {
            pendingId = link?.pendingId
        }
        state.deleted.append(JessDeletedCard(cardId: cardId, pendingId: pendingId))
        if state.deleted.count > Self.deletedLimit {
            state.deleted.removeFirst(state.deleted.count - Self.deletedLimit)
        }
        persist()
    }

    /// How many deleted cards are remembered: more than the Workdesk ever shows.
    static let deletedLimit = 400

    private func isDeleted(cardId: UUID) -> Bool {
        for deletedCard in state.deleted where deletedCard.cardId == cardId {
            return true
        }
        return false
    }

    private func isDeleted(pendingId: String) -> Bool {
        for deletedCard in state.deleted where deletedCard.pendingId == pendingId {
            return true
        }
        return false
    }

    /// Requests not finished yet, on disk.
    var pendingRequests: [JessPendingRequest] {
        state.requests
    }

    /// Speech ended: the request is kept on disk, then sent under background time. Returns once
    /// it is finished or left for the next open.
    @discardableResult
    func submit(transcript: String, listenMs: Int) async -> JessResultCard? {
        let request = JessPendingRequest(id: UUID(), transcript: transcript, listenMs: listenMs, saidAt: dependencies.now(), timeZone: dependencies.timeZone().identifier, applied: nil)
        let card = JessResultCard(id: request.id, kind: .working, transcript: transcript, createdAt: request.saidAt)
        state.requests.append(request)
        state.cards.insert(card, at: 0)
        recordInLog(card)
        persist()
        return await run(request)
    }

    /// Opening Midas: every request a stopped process left unfinished. An applied one only shows
    /// its card; any other is sent again with its own time.
    func resume() async {
        guard dependencies.isSignedIn() else {
            return
        }
        var waiting: [JessPendingRequest] = []
        for request in state.requests where !runningIds.contains(request.id) {
            waiting.append(request)
        }
        for request in waiting {
            _ = await run(request)
        }
    }

    /// Try Again on a Not Done card, on the home page or the Workdesk: the same words, sent again
    /// now under a new server id; the card shows it working.
    func retry(cardId: UUID) {
        guard !runningIds.contains(cardId), requestIndex(cardId) == nil else {
            return
        }
        guard let shown = notDoneCard(cardId) else {
            return
        }
        let request = JessPendingRequest(id: cardId, transcript: shown.transcript, listenMs: 0, saidAt: dependencies.now(), timeZone: dependencies.timeZone().identifier, applied: nil, serverRequestId: UUID().uuidString.lowercased())
        var working = shown
        working.kind = .working
        if let index = cardIndex(cardId) {
            state.cards[index].kind = .working
        }
        recordInLog(working)
        state.requests.append(request)
        persist()
        Task { @MainActor [weak self] in
            _ = await self?.run(request)
        }
    }

    /// A home card leaves only when dismissed; one still working or waiting stays. The task stays
    /// in the Workdesk log.
    func dismiss(cardId: UUID) {
        guard let index = cardIndex(cardId) else {
            return
        }
        let kind = state.cards[index].kind
        guard kind != .working, kind != .waitingForConnection else {
            return
        }
        state.cards.remove(at: index)
        persist()
    }

    /// The backend finished a request jess grew a Sidekick for: the card waiting on that pending
    /// request shows the result and moves to the top. False when no card waits on it (a request
    /// from before the Workdesk), so the caller shows it as a new card.
    func settleGrow(pendingId: String, result: JessResult) -> Bool {
        // The card that waited on it was deleted: taken, and nothing shows
        if isDeleted(pendingId: pendingId) {
            return true
        }
        func waitsOnPending(_ link: JessRepairLink) -> Bool {
            link.pendingId == pendingId
        }
        func growResult(_ card: JessResultCard) -> JessResultCard.Kind {
            JessResultCard.kind(for: result)
        }
        return settleWaitingCard(matching: waitsOnPending, kind: growResult)
    }

    /// A plain repair (not a grow) is live: the card waiting on its report turns done and moves to
    /// the top. Its line is the task as said; `text` (the repair's notice) only when nothing was.
    func settleRepair(reportId: String, text: String) -> Bool {
        func waitsOnReport(_ link: JessRepairLink) -> Bool {
            link.reportId == reportId && link.pendingId == nil
        }
        func repairDone(_ card: JessResultCard) -> JessResultCard.Kind {
            let line = card.transcript.isEmpty ? text : VoiceReminderCopy.workdeskTask(card.transcript)
            return .done(text: line, at: nil, allDay: false, timeZone: nil)
        }
        return settleWaitingCard(matching: waitsOnReport, kind: repairDone)
    }

    /// The agent could not make a plain repair jess sent: the founder takes a deeper look and makes
    /// it by hand (founder, 2026-11-01). The card keeps waiting and says so; the founder's fix later
    /// settles it as done. False when no card waits on it or it already says so.
    func markDeeperLook(reportId: String) -> Bool {
        func waitsOnReport(_ card: JessResultCard) -> Bool {
            guard case .sentToRepair(_, let link) = card.kind, let link else {
                return false
            }
            return link.reportId == reportId && link.pendingId == nil && card.takingDeeperLook != true
        }
        var changed = false
        for index in state.log.indices where waitsOnReport(state.log[index]) {
            state.log[index].takingDeeperLook = true
            changed = true
        }
        for index in state.cards.indices where waitsOnReport(state.cards[index]) {
            state.cards[index].takingDeeperLook = true
            changed = true
        }
        if changed {
            persist()
        }
        return changed
    }

    /// Report ids of plain repairs a card still waits on, for the notices check.
    var waitingReportIds: Set<String> {
        var reportIds: Set<String> = []
        for card in state.log {
            if case .sentToRepair(_, let link) = card.kind, let link, link.pendingId == nil, let reportId = link.reportId {
                reportIds.insert(reportId)
            }
        }
        return reportIds
    }

    /// A result that did not come from the Listening screen: a request jess grew a Sidekick for,
    /// finished by the backend (JessGrowFollowUp).
    func present(_ result: JessResult) {
        var transcript = ""
        if case .notDone(let saidText) = result {
            transcript = saidText
        }
        let card = JessResultCard(id: UUID(), kind: JessResultCard.kind(for: result), transcript: transcript, createdAt: dependencies.now())
        state.cards.insert(card, at: 0)
        recordInLog(card)
        persist()
    }

    /// How one attempt at a request ended.
    private enum Attempt {
        case finished(JessResultCard?)
        /// iOS ended the background time and no answer came: kept for later.
        case stopped
        /// Cut off: kept, its card waiting for a connection, sent again later.
        case waiting(JessResultCard?)
    }

    /// Sends a request until it has a result, or leaves it on disk when iOS stopped Midas while it
    /// was away. Already back on screen when the lost answer is noticed: sent again at once.
    private func run(_ waitingRequest: JessPendingRequest) async -> JessResultCard? {
        // Read again: an open that overlapped this one may have finished it already
        guard let index = requestIndex(waitingRequest.id) else {
            return nil
        }
        let request = state.requests[index]
        if let applied = request.applied {
            return finish(request.id, kind: applied)
        }
        guard !runningIds.contains(request.id) else {
            return nil
        }
        while true {
            let attempt = await send(request)
            switch attempt {
            case .finished(let card):
                return card
            case .stopped:
                guard dependencies.isInForeground() else {
                    return nil
                }
            case .waiting(let card):
                scheduleForegroundRetry()
                return card
            }
        }
    }

    private func send(_ request: JessPendingRequest) async -> Attempt {
        runningIds.insert(request.id)
        expiredIds.remove(request.id)
        var backgroundToken: Int?
        // iOS ending the time early leaves the request on disk for the next open
        func timeExpired() {
            expiredIds.insert(request.id)
            if let token = backgroundToken {
                backgroundToken = nil
                dependencies.backgroundTime.end(token)
            }
        }
        backgroundToken = dependencies.backgroundTime.begin(expired: timeExpired)
        defer {
            runningIds.remove(request.id)
            if let token = backgroundToken {
                backgroundToken = nil
                dependencies.backgroundTime.end(token)
            }
        }
        let routeContext = JessRouteContext(requestId: request.sentRequestId)
        // Written in the same turn as the ops, so this request is never applied twice
        func markApplied(_ result: JessResult) {
            guard let index = requestIndex(request.id) else {
                return
            }
            state.requests[index].applied = JessResultCard.kind(for: result)
            state.requests[index].appliedLink = routeContext.changeLink
            persist()
        }
        let zone = TimeZone(identifier: request.timeZone) ?? dependencies.timeZone()
        func routeRequest() async -> JessResult {
            await dependencies.route(request.transcript, request.listenMs, request.saidAt, zone, markApplied)
        }
        let result = await JessRouteContext.$current.withValue(routeContext, operation: routeRequest)
        let sidekickName = routeContext.sidekickName
        if let index = requestIndex(request.id), let applied = state.requests[index].applied {
            return .finished(finish(request.id, kind: applied, sidekickName: sidekickName, link: routeContext.changeLink))
        }
        // No answer because iOS stopped Midas mid-request: not "Not Done", only not finished yet
        if expiredIds.contains(request.id) {
            switch result {
            case .notDone, .cutOff:
                return .stopped
            case .done, .sentToRepair:
                break
            }
        }
        if case .cutOff = result {
            // Past the give-up time: Not Done with Try Again; otherwise kept and sent again
            let waited = dependencies.now().timeIntervalSince(request.saidAt)
            if waited >= dependencies.giveUpAfter {
                return .finished(finish(request.id, kind: .notDone, sidekickName: sidekickName))
            }
            return .waiting(showWaiting(request.id))
        }
        return .finished(finish(request.id, kind: JessResultCard.kind(for: result), sidekickName: sidekickName, link: routeContext.changeLink))
    }

    /// The request leaves the disk and its card shows the result, at the top, in one write.
    private func finish(_ requestId: UUID, kind: JessResultCard.Kind, sidekickName: String? = nil, link: JessChangeLink? = nil) -> JessResultCard? {
        guard let requestPosition = requestIndex(requestId) else {
            return nil
        }
        let request = state.requests.remove(at: requestPosition)
        // Deleted while on its way: the request is finished, its card stays gone
        if isDeleted(cardId: requestId) {
            persist()
            return nil
        }
        var card = JessResultCard(id: request.id, kind: kind, transcript: request.transcript, createdAt: dependencies.now())
        card.sidekickName = sidekickName ?? logCard(requestId)?.sidekickName
        // Only a done card links to its change
        if case .done = kind {
            card.link = link ?? request.appliedLink
        }
        if let index = cardIndex(requestId) {
            state.cards.remove(at: index)
        }
        state.cards.insert(card, at: 0)
        recordInLog(card)
        persist()
        return card
    }

    /// A cut-off request stays on disk; its card, where it is, waits for a connection.
    private func showWaiting(_ requestId: UUID) -> JessResultCard? {
        var waitingCard: JessResultCard?
        if let index = cardIndex(requestId) {
            state.cards[index].kind = .waitingForConnection
            waitingCard = state.cards[index]
        }
        if var logged = logCard(requestId) {
            logged.kind = .waitingForConnection
            recordInLog(logged)
            waitingCard = waitingCard ?? logged
        }
        persist()
        return waitingCard
    }

    /// While Midas is on screen a cut-off request is sent again every few seconds; one timer at a
    /// time.
    private func scheduleForegroundRetry() {
        guard let delay = dependencies.foregroundRetryDelay, !isRetryScheduled, dependencies.isInForeground() else {
            return
        }
        isRetryScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else {
                return
            }
            self.isRetryScheduled = false
            guard self.dependencies.isInForeground() else {
                return
            }
            await self.resume()
        }
    }

    private func settleWaitingCard(matching waitsOn: (JessRepairLink) -> Bool, kind settledKind: (JessResultCard) -> JessResultCard.Kind) -> Bool {
        var settled = false
        for card in state.log {
            guard case .sentToRepair(_, let link) = card.kind, let link, waitsOn(link) else {
                continue
            }
            var updated = card
            updated.kind = settledKind(card)
            updated.createdAt = dependencies.now()
            updated.takingDeeperLook = nil
            // The same card, now with the result, at the top of the home page and the Workdesk; an
            // edit that turned Not Done comes back to home even if its card had left it
            if let index = cardIndex(card.id) {
                state.cards.remove(at: index)
                state.cards.insert(updated, at: 0)
            } else if Self.showsOnHome(updated) {
                state.cards.insert(updated, at: 0)
            }
            recordInLog(updated)
            settled = true
        }
        if settled {
            persist()
        }
        return settled
    }

    /// The Not Done card to send again, from the home page or, once dismissed there, the Workdesk.
    private func notDoneCard(_ cardId: UUID) -> JessResultCard? {
        if let index = cardIndex(cardId), state.cards[index].kind == .notDone {
            return state.cards[index]
        }
        if let logged = logCard(cardId), logged.kind == .notDone {
            return logged
        }
        return nil
    }

    private func logCard(_ cardId: UUID) -> JessResultCard? {
        for card in state.log where card.id == cardId {
            return card
        }
        return nil
    }

    /// One task in the Workdesk log: a new one, or one whose result changed, goes to the top; the
    /// same result again stays where it is. Only the last `logLimit` are kept.
    private func recordInLog(_ card: JessResultCard) {
        var entry = card
        var existingIndex: Int?
        for (index, logged) in state.log.enumerated() where logged.id == card.id {
            existingIndex = index
        }
        if let existingIndex {
            let existing = state.log[existingIndex]
            if entry.sidekickName == nil {
                entry.sidekickName = existing.sidekickName
            }
            if entry.link == nil {
                entry.link = existing.link
            }
            if existing.kind == entry.kind {
                state.log[existingIndex] = entry
                return
            }
            state.log.remove(at: existingIndex)
        }
        state.log.insert(entry, at: 0)
        if state.log.count > Self.logLimit {
            state.log.removeLast(state.log.count - Self.logLimit)
        }
    }

    private func logIndex(_ cardId: UUID) -> Int? {
        for (index, card) in state.log.enumerated() where card.id == cardId {
            return index
        }
        return nil
    }

    private func cardIndex(_ cardId: UUID) -> Int? {
        for (index, card) in state.cards.enumerated() where card.id == cardId {
            return index
        }
        return nil
    }

    private func requestIndex(_ requestId: UUID) -> Int? {
        for (index, request) in state.requests.enumerated() where request.id == requestId {
            return index
        }
        return nil
    }

    private func persist() {
        file.save(state)
        cards = state.cards
        log = state.log
    }
}
