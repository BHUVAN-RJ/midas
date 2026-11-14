import Foundation

// Repair lanes on the phone (founder, 2026-11-13, docs/PRODUCT.md "Plan additions, 2026-11-13:
// repair lanes", D4 = A; brief docs/briefs/repair-lanes.md W3). The Worker sorts every report
// before a runner can claim it and answers Send with a lane. Three lanes change what the phone
// shows; every other lane closes the layer as Send always did:
//
//   ask_back       one question card ("What should it be?") with 2–3 picture guesses over the pill;
//                  repair mode stays on; the answer joins the same request (POST /repairs/:id/answer)
//   not_a_request  the pill says the message ("Say or draw what to change.") and keeps listening
//   shell_cant     the dark sheet with the message, then repair mode closes
//
// The W2 contract (brief, W2):
//   POST /repairs             → { id, lane, question?, message? }
//   POST /repairs/:id/answer  { optionId } | { text }  →  { lane }   (same request, sorted again)

/// The lane the sort put a report in. A lane this shell does not know reads as `code`: when
/// unsure, up a lane, never down.
enum RepairLane: String, Codable, Equatable, Sendable, CaseIterable {
    case askBack = "ask_back"
    case notARequest = "not_a_request"
    case shellCant = "shell_cant"
    case jessCommand = "jess_command"
    case setting
    case look
    case code

    init(serverValue: String?) {
        guard let serverValue, let known = RepairLane(rawValue: serverValue) else {
            self = .code
            return
        }
        self = known
    }
}

/// One guess on the question card: a picture and a word or two.
struct RepairQuestionOption: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    /// An SF Symbol name; a short text (an emoji) is drawn as text; nil or unknown draws a plain mark.
    let icon: String?
}

/// "What should it be?" and its guesses.
struct RepairQuestion: Codable, Equatable, Sendable {
    let text: String
    let options: [RepairQuestionOption]
}

/// The Worker's answer to a report or to an answer.
struct RepairSortReply: Equatable, Sendable {
    /// The server's report id; missing on the answer's reply (the same request).
    let id: String?
    let lane: RepairLane
    let question: RepairQuestion?
    let message: String?
}

extension RepairSortReply: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case lane
        case question
        case message
    }

    // Lenient: today's Worker answers { id, status } with no lane, which reads as `code`; a
    // question that does not decode is left out (and the rules then send the report up to code)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLane = try? container.decodeIfPresent(String.self, forKey: .lane)
        self.init(
            id: try? container.decodeIfPresent(String.self, forKey: .id),
            lane: RepairLane(serverValue: rawLane ?? nil),
            question: try? container.decodeIfPresent(RepairQuestion.self, forKey: .question),
            message: try? container.decodeIfPresent(String.self, forKey: .message)
        )
    }

    /// Reads a reply body; nil when it is not JSON at all.
    static func decode(_ data: Data) -> RepairSortReply? {
        try? JSONDecoder().decode(RepairSortReply.self, from: data)
    }
}

/// What came of an answer to the card.
enum RepairAnswerOutcome: Equatable, Sendable {
    /// The same request, sorted again.
    case sorted(RepairSortReply?)
    /// 410: the card was dropped (unanswered for 2 minutes). The card closes quietly.
    case dropped
    /// Did not go through (offline, another error).
    case failed
}

/// What the person answers: a tapped guess, or their own words.
enum RepairSortAnswer: Equatable, Sendable {
    case option(String)
    case text(String)

    /// `{ "optionId": … }` or `{ "text": … }`.
    func jsonBody() throws -> Data {
        var body: [String: String] = [:]
        switch self {
        case .option(let optionId):
            body["optionId"] = optionId
        case .text(let text):
            body["text"] = text
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

/// Where the repair layer is between Send and closing.
enum RepairAskStage: Equatable, Sendable {
    /// Drawing and speaking, as before any Send.
    case open
    /// Sent; waiting for the lane. The tag says "Editing" and the orb in it spins.
    case sorting
    /// The question card is up over the pill.
    case asking(RepairQuestion)
    /// Not a request: the pill says the message and jess listens again.
    case notARequest(String)
    /// The shell can't: the dark sheet, then the layer closes.
    case shellCant(RepairShellCantMessage)

    var question: RepairQuestion? {
        if case .asking(let question) = self {
            return question
        }
        return nil
    }

    var isWaiting: Bool {
        self == .sorting
    }
}

/// The dark sheet's two lines: the message in bold, then "Sent to Midas." in grey.
struct RepairShellCantMessage: Equatable, Sendable {
    let title: String
    let detail: String
}

/// What the layer does with a reply.
enum RepairSortDecision: Equatable, Sendable {
    /// Every lane with a job: the layer closes as Send always did, the tag says "Editing".
    case close
    case ask(RepairQuestion, repairId: String)
    case listen(message: String)
    case shellCant(RepairShellCantMessage)
}

/// The words of the three new lanes (docs/WRITING.md; founder's words, mockup
/// docs/mockups/repair-ask-back-2026-11-08.html, columns "A · Cards", "Not a request", "Shell can't").
enum RepairAskBackCopy {
    static let oneQuestion = "One question"
    static let orSayIt = "Or say it…"
    static let question = "What should it be?"
    static let notARequest = "Say or draw what to change."
    static let sentToMidas = "Sent to Midas."
}

/// Times for the three lanes.
enum RepairAskBackSpec {
    /// The sort answers in about 3 s; the Worker's worst case is about 12 s (Jev 6 s, then Haiku
    /// 6 s; W2 hand-back, 2026-11-13). Past this the phone stops waiting and closes as an edit (up
    /// a lane). The upload goes on by itself.
    static let sortWaitSeconds: Double = 15
    /// The upload and the answer's own network time-out, above the phone's wait.
    static let requestTimeoutSeconds: Double = 30
    /// The dark sheet stays this long, then repair mode closes (mockup: 6.4 s → 10.5 s).
    static let shellCantSeconds: Double = 4
    /// At most three guesses on the card.
    static let maxOptions = 3
    /// The card and the sheet rise 40 pt and fade in over 350 ms (mockup `.qcard`, `.sheet`).
    static let enter: Double = 0.35
    static let enterRise: Double = 40
}

/// The lane rules, pure so the tests read them.
enum RepairSortRules {
    /// What the layer shows for a reply. No reply (offline, an error, too slow), an unknown lane,
    /// or a question with no guesses or no report id goes up to the edit lane.
    static func decision(for reply: RepairSortReply?, knownRepairId: String?) -> RepairSortDecision {
        guard let reply else {
            return .close
        }
        switch reply.lane {
        case .askBack:
            return askDecision(reply: reply, knownRepairId: knownRepairId)
        case .notARequest:
            let message = trimmedOrNil(reply.message) ?? RepairAskBackCopy.notARequest
            return .listen(message: message)
        case .shellCant:
            return .shellCant(shellCantMessage(reply.message))
        case .jessCommand, .setting, .look, .code:
            return .close
        }
    }

    private static func askDecision(reply: RepairSortReply, knownRepairId: String?) -> RepairSortDecision {
        guard let question = reply.question, let repairId = reply.id ?? knownRepairId else {
            return .close
        }
        let usable = question.options.filter(isUsable)
        guard !usable.isEmpty else {
            return .close
        }
        let shown = Array(usable.prefix(RepairAskBackSpec.maxOptions))
        let text = trimmedOrNil(question.text) ?? RepairAskBackCopy.question
        return .ask(RepairQuestion(text: text, options: shown), repairId: repairId)
    }

    private static func isUsable(_ option: RepairQuestionOption) -> Bool {
        trimmedOrNil(option.id) != nil && trimmedOrNil(option.label) != nil
    }

    /// The server's line is the bold title; "Sent to Midas." goes under it in grey, once, whether
    /// or not the server wrote it at the end of its line.
    static func shellCantMessage(_ message: String?) -> RepairShellCantMessage {
        let suffix = RepairAskBackCopy.sentToMidas
        var title = trimmedOrNil(message) ?? ""
        if title.hasSuffix(suffix) {
            let withoutSuffix = title.dropLast(suffix.count)
            title = String(withoutSuffix).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return RepairShellCantMessage(title: title, detail: suffix)
    }

    /// A tapped guess answers by its id while the pill still says just its words; once the person
    /// changes or adds words, the words are the answer. Nil when there is nothing to send.
    static func answer(pickedOptionId: String?, options: [RepairQuestionOption], words: String) -> RepairSortAnswer? {
        guard let trimmedWords = trimmedOrNil(words) else {
            return nil
        }
        let picked = options.first { $0.id == pickedOptionId }
        if let picked, picked.label == trimmedWords {
            return .option(picked.id)
        }
        return .text(trimmedWords)
    }

    /// jess_command (the lead's default, 2026-11-13): the person's words go to jess exactly as if
    /// they had said them to jess, and repair mode closes. No edit is on its way.
    static func handsToJess(_ reply: RepairSortReply?) -> Bool {
        reply?.lane == .jessCommand
    }

    private static func trimmedOrNil(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The tag while the layer is open: "Editing" with the spinning orb while the lane is on its way,
/// "One question" while the card is up, "Edit" otherwise (founder's tag words, `RepairTagCopy`).
enum RepairAskBackTag {
    struct Shown: Equatable {
        let display: RepairTagDisplay
        /// Words in place of the display's own; nil keeps them.
        let words: String?
    }

    static func shown(stage: RepairAskStage?, base: RepairTagDisplay?) -> Shown? {
        guard let stage else {
            return base.map(plain)
        }
        switch stage {
        case .sorting:
            return Shown(display: .repairing(count: 1, takingLonger: false), words: nil)
        case .asking:
            return Shown(display: .repairMode, words: RepairAskBackCopy.oneQuestion)
        case .open, .notARequest, .shellCant:
            return base.map(plain)
        }
    }

    private static func plain(_ display: RepairTagDisplay) -> Shown {
        Shown(display: display, words: nil)
    }
}

/// Local stand-in for the W2 sort, for trying the cards on a simulator before W2 is on staging
/// (Debug builds only, `MIDAS_REPAIR_SORT_STUB=1` in the app's environment). Nothing is uploaded
/// while it is on. Words pick the lane the way the mockup's examples do.
enum RepairSortStub {
    static let environmentKey = "MIDAS_REPAIR_SORT_STUB"

    static var isOn: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment[environmentKey] == "1"
        #else
        return false
        #endif
    }

    static let guesses = [
        RepairQuestionOption(id: "other-icon", label: "Other icon", icon: "photo"),
        RepairQuestionOption(id: "smaller", label: "Smaller", icon: "arrow.down.right.and.arrow.up.left"),
        RepairQuestionOption(id: "remove", label: "Remove", icon: "nosign")
    ]

    /// The report's lane from its words: "how are you" is not a request, "every hour" is
    /// something the shell can't do, "change this" / "fix this" asks back; anything else is code.
    static func reply(transcript: String, sidekickId: String, reportId: String) -> RepairSortReply {
        let words = transcript.lowercased()
        if words.contains("how are you") {
            return RepairSortReply(id: reportId, lane: .notARequest, question: nil, message: RepairAskBackCopy.notARequest)
        }
        if words.contains("every hour") || words.contains("every one hour") {
            let name = sidekickId.prefix(1).uppercased() + sidekickId.dropFirst()
            let message = "\(name) can’t remind every hour yet. \(RepairAskBackCopy.sentToMidas)"
            return RepairSortReply(id: reportId, lane: .shellCant, question: nil, message: message)
        }
        if words.contains("change this") || words.contains("fix this") {
            let question = RepairQuestion(text: RepairAskBackCopy.question, options: guesses)
            return RepairSortReply(id: reportId, lane: .askBack, question: question, message: nil)
        }
        return RepairSortReply(id: reportId, lane: .code, question: nil, message: nil)
    }

    /// An answer always goes to the code lane.
    static func answerReply() -> RepairSortReply {
        RepairSortReply(id: nil, lane: .code, question: nil, message: nil)
    }
}
