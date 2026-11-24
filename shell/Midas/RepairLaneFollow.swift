import Foundation

// Send closes repair mode at once (founder, 2026-11-22; docs/briefs/repair-lanes.md "Change
// 2026-11-22"). The layer goes the moment Send is tapped, exactly as an edit always did: the tag
// takes the report and says "Editing". The Worker answers the upload before it sorts; the tag
// (`RepairCenter`) follows the lane with GET /repairs/lanes/:clientReportId and shows what came of it:
//
//   setting done    the record is pulled, the page redraws, the tag says "Changed" with Undo
//   code, look      the tag stays "Editing", as today; the notices poll keeps asking the lane,
//                   because the repair agent turns an edit it cannot tell how to build into a
//                   question (founder, 2026-11-23), which then comes up as ask_back below
//   jess_command    the tag goes; the words go to jess
//   ask_back        the tag says "1 question"; a tap opens repair mode again with the card
//   not a request,  the tag shows the message for a moment, then goes
//   shell can't

/// Words on the tag for a lane's result (docs/WRITING.md: say the action, stop).
enum RepairLaneCopy {
    static let changed = "Changed"
    static let undo = "Undo"
    static let undone = "Undone"
    static let oneQuestion = "1 question"
}

/// Times for the lane's result on the tag.
enum RepairLaneSpec {
    /// The tag asks for the lane this often right after an upload...
    static let fastPollSeconds: Double = 1
    /// ...for this long; after that the slower notices poll asks too.
    static let fastWatchSeconds: Double = 40
    /// "Changed" stays long enough to reach Undo.
    static let changedSeconds: Double = 6
    static let undoneSeconds: Double = 1.5
    /// A message ("Say or draw what to change.") is read, then goes.
    static let messageSeconds: Double = 3
    /// The Worker drops a card unanswered this long (backend ANSWER_WINDOW_MS); "1 question" goes then.
    static let questionWindowSeconds: Double = 120
}

/// What the lane route said about one report.
enum RepairLaneCheck: Equatable, Sendable {
    case reply(RepairSortReply)
    /// The Worker has no such report yet (the upload has not gone through).
    case notFound
    /// Offline or another error: ask again later.
    case failed
}

/// The two routes the tag uses after Send.
protocol RepairLaneAPI: Sendable {
    /// GET /repairs/lanes/:clientReportId
    func lane(clientReportId: String) async -> RepairLaneCheck
    /// POST /repairs/:id/undo: true when the old values are back.
    func undo(repairId: String) async -> Bool
}

struct RemoteRepairLaneAPI: RepairLaneAPI {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func lane(clientReportId: String) async -> RepairLaneCheck {
        guard let token = sessionToken() else {
            return .failed
        }
        let request = Self.laneRequest(platformOrigin: platformOrigin, clientReportId: clientReportId, token: token)
        guard let (body, response) = try? await session.data(for: request) else {
            return .failed
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Self.laneCheck(statusCode: statusCode, body: body)
    }

    func undo(repairId: String) async -> Bool {
        guard let token = sessionToken() else {
            return false
        }
        let request = Self.undoRequest(platformOrigin: platformOrigin, repairId: repairId, token: token)
        guard let (_, response) = try? await session.data(for: request) else {
            return false
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (200...299).contains(statusCode)
    }

    static func laneRequest(platformOrigin: URL, clientReportId: String, token: String) -> URLRequest {
        let url = platformOrigin.appending(path: "repairs").appending(path: "lanes").appending(path: clientReportId)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    static func undoRequest(platformOrigin: URL, repairId: String, token: String) -> URLRequest {
        let url = platformOrigin.appending(path: "repairs").appending(path: repairId).appending(path: "undo")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    /// 2xx with a body is the lane, 404 not uploaded yet, anything else a failure.
    static func laneCheck(statusCode: Int, body: Data) -> RepairLaneCheck {
        if statusCode == 404 {
            return .notFound
        }
        guard (200...299).contains(statusCode), let reply = RepairSortReply.decode(body) else {
            return .failed
        }
        return .reply(reply)
    }
}

/// A lane's result waiting on the tag (kept while the app runs; a relaunch asks the lane again).
struct RepairLaneNote: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The setting lane made the change; Undo puts it back through the report `repairId`.
        case changed(repairId: String?)
        case undone
        /// The card waits for an answer; a tap opens repair mode again with it.
        case question(RepairQuestion, repairId: String)
        case message(String)
    }

    let clientReportId: String
    let sidekickId: String
    let kind: Kind
    let arrivedAt: Date
}

/// What the tag does with a lane, pure so the tests read it.
enum RepairLaneRules {
    enum Step: Equatable, Sendable {
        /// Not sorted yet: ask again.
        case keepWatching
        /// An edit is on its way: "Editing" stays until the notice.
        case staysEditing
        case changed(repairId: String?)
        case toJess
        case question(RepairQuestion, repairId: String)
        case message(String)
        /// The card was dropped before it was answered: the tag goes, nothing more.
        case gone
    }

    static func step(for reply: RepairSortReply) -> Step {
        guard reply.laneKnown else {
            return .keepWatching
        }
        if RepairSortRules.settingDone(reply) {
            return .changed(repairId: reply.id)
        }
        if RepairSortRules.handsToJess(reply) {
            return .toJess
        }
        if reply.lane == .askBack && reply.sortStatus == RepairSortStatus.dropped {
            return .gone
        }
        switch RepairSortRules.decision(for: reply, knownRepairId: nil) {
        case .close:
            return .staysEditing
        case .ask(let question, let repairId):
            return .question(question, repairId: repairId)
        case .listen(let message):
            return .message(message)
        case .shellCant(let message):
            return .message(shellCantLine(message))
        }
    }

    /// The dark sheet's two lines, on the tag as one.
    private static func shellCantLine(_ message: RepairShellCantMessage) -> String {
        if message.title.isEmpty {
            return message.detail
        }
        return "\(message.title) \(message.detail)"
    }

    /// What the tag shows for a note at `now`; nil once a question's card has been dropped.
    static func display(for note: RepairLaneNote, now: Date) -> RepairTagDisplay? {
        switch note.kind {
        case .changed:
            return .changed
        case .undone:
            return .undone
        case .question:
            let waited = now.timeIntervalSince(note.arrivedAt)
            return waited < RepairLaneSpec.questionWindowSeconds ? .question : nil
        case .message(let text):
            return .laneMessage(text)
        }
    }
}
