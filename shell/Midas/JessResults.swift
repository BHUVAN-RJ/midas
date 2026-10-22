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

/// One result card at the top of the home page.
struct JessResultCard: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        /// Sent; the answer is not in yet.
        case working
        /// The Sidekick's own line and the time it set, if any.
        case done(text: String, at: String?, allDay: Bool, timeZone: String?)
        case notDone
        case sentToRepair(sidekickName: String)
    }

    let id: UUID
    var kind: Kind
    /// What was said; empty for a result the backend finished (jess grows the Sidekick).
    let transcript: String
    var createdAt: Date

    var orbState: JessOrbState {
        switch kind {
        case .working:
            return .thinking
        case .done, .sentToRepair:
            return .added
        case .notDone:
            return .failed
        }
    }

    static func kind(for result: JessResult) -> Kind {
        switch result {
        case .done(let text, let at, let allDay, let timeZone):
            return .done(text: text, at: at, allDay: allDay ?? false, timeZone: timeZone)
        case .sentToRepair(let sidekickName):
            return .sentToRepair(sidekickName: sidekickName)
        case .notDone:
            return .notDone
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
}

/// The cards and the unfinished requests, in one file per server.
struct JessResultsState: Codable, Equatable, Sendable {
    var cards: [JessResultCard] = []
    var requests: [JessPendingRequest] = []
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
}

@MainActor
@Observable
final class JessResults {
    /// Newest first.
    private(set) var cards: [JessResultCard]

    @ObservationIgnored private var state: JessResultsState
    @ObservationIgnored private let file: JessResultsFile
    @ObservationIgnored private let dependencies: JessResultsDependencies
    /// Requests being sent by this process; the others on disk are finished by `resume()`.
    @ObservationIgnored private var runningIds: Set<UUID> = []
    /// Requests whose background time iOS ended before the answer came.
    @ObservationIgnored private var expiredIds: Set<UUID> = []

    init(file: JessResultsFile, dependencies: JessResultsDependencies) {
        self.file = file
        self.dependencies = dependencies
        let loaded = file.load()
        self.state = loaded
        self.cards = loaded.cards
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

    /// Try Again on a Not Done card: the same words, sent again now; the card shows it working.
    func retry(cardId: UUID) {
        guard let index = cardIndex(cardId), state.cards[index].kind == .notDone, !runningIds.contains(cardId) else {
            return
        }
        let transcript = state.cards[index].transcript
        let request = JessPendingRequest(id: cardId, transcript: transcript, listenMs: 0, saidAt: dependencies.now(), timeZone: dependencies.timeZone().identifier, applied: nil)
        state.cards[index].kind = .working
        state.requests.append(request)
        persist()
        Task { @MainActor [weak self] in
            _ = await self?.run(request)
        }
    }

    /// A card leaves only when dismissed; one still working stays.
    func dismiss(cardId: UUID) {
        guard let index = cardIndex(cardId), state.cards[index].kind != .working else {
            return
        }
        state.cards.remove(at: index)
        persist()
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
        persist()
    }

    /// How one attempt at a request ended.
    private enum Attempt {
        case finished(JessResultCard?)
        /// iOS ended the background time and no answer came: kept for later.
        case stopped
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
        // Written in the same turn as the ops, so this request is never applied twice
        func markApplied(_ result: JessResult) {
            guard let index = requestIndex(request.id) else {
                return
            }
            state.requests[index].applied = JessResultCard.kind(for: result)
            persist()
        }
        let zone = TimeZone(identifier: request.timeZone) ?? dependencies.timeZone()
        let result = await dependencies.route(request.transcript, request.listenMs, request.saidAt, zone, markApplied)
        if let index = requestIndex(request.id), let applied = state.requests[index].applied {
            return .finished(finish(request.id, kind: applied))
        }
        // No answer because iOS stopped Midas mid-request: not "Not Done", only not finished yet
        if expiredIds.contains(request.id), case .notDone = result {
            return .stopped
        }
        return .finished(finish(request.id, kind: JessResultCard.kind(for: result)))
    }

    /// The request leaves the disk and its card shows the result, at the top, in one write.
    private func finish(_ requestId: UUID, kind: JessResultCard.Kind) -> JessResultCard? {
        guard let requestPosition = requestIndex(requestId) else {
            return nil
        }
        let request = state.requests.remove(at: requestPosition)
        let card = JessResultCard(id: request.id, kind: kind, transcript: request.transcript, createdAt: dependencies.now())
        if let index = cardIndex(requestId) {
            state.cards.remove(at: index)
        }
        state.cards.insert(card, at: 0)
        persist()
        return card
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
    }
}
