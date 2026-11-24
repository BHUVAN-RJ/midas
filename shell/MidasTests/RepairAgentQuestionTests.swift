import XCTest
@testable import Midas

// Unclear code requests become a question, never a refusal (founder, 2026-11-23; docs/PRODUCT.md
// main 130a76a; job 08b4244b). The repair agent can turn an edit already in the code lane ("Editing…")
// into a question; the Worker then answers GET /repairs/lanes/:clientReportId with lane ask_back and
// the agent's card. The tag's notices poll keeps asking the lane of code-lane edits, so the tag shows
// "1 question" and, on that Sidekick with the app in front, the card opens by itself exactly like a
// sort-time ask_back (questionsToOpen).

// MARK: - Stand-ins

/// The lane route: each report answers the reply the test set last, or not found.
private final class AgentQuestionLaneStub: RepairLaneAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String: RepairSortReply] = [:]
    private var storedAsked: [String] = []

    var asked: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedAsked
    }

    func answer(_ clientReportId: String, with reply: RepairSortReply) {
        lock.lock()
        replies[clientReportId] = reply
        lock.unlock()
    }

    func lane(clientReportId: String) async -> RepairLaneCheck {
        guard let reply = recordAndRead(clientReportId) else {
            return .notFound
        }
        return .reply(reply)
    }

    func undo(repairId: String) async -> Bool {
        true
    }

    private func recordAndRead(_ clientReportId: String) -> RepairSortReply? {
        lock.lock()
        defer { lock.unlock() }
        storedAsked.append(clientReportId)
        return replies[clientReportId]
    }
}

/// No notices: the edit is still on its way.
private final class AgentQuestionNoNotices: JessRepairNoticesAPI, @unchecked Sendable {
    func notices() async -> [JessRepairNotice]? {
        []
    }

    func markSeen(id: String) async {}
}

@MainActor
private final class AgentQuestionNoResend: RepairResending {
    func send(_ report: RepairReport) async {}
}

@MainActor
private final class AgentQuestionAppState {
    var active = true

    func isActive() -> Bool {
        active
    }
}

/// The Worker's own JSON for the lane after the agent asked (backend repair-sort.ts handleGetLane
/// with the stored card, askedBy included).
private let agentLaneJSON = """
{"id":"srv-a1","status":"received","sortStatus":"asking","lane":"ask_back","question":{"text":"What should move?","options":[{"id":"option-1","label":"Drag to Reorder","icon":"arrow.up.and.down.and.arrow.left.and.right"},{"id":"option-2","label":"Move to Another Day","icon":"arrow.up.and.down.and.arrow.left.and.right"}],"askedBy":"agent"}}
"""

private let codeLaneJSON = """
{"id":"srv-a1","status":"running","sortStatus":"sorted","lane":"code"}
"""

private func agentReply(_ json: String) -> RepairSortReply {
    guard case .reply(let reply) = RemoteRepairLaneAPI.laneCheck(statusCode: 200, body: Data(json.utf8)) else {
        XCTFail("the Worker's lane reply did not decode")
        return RepairSortReply(id: nil, lane: .code, question: nil, message: nil)
    }
    return reply
}

private func agentQuestionReport(_ clientReportId: String) -> RepairReport {
    RepairReport(
        clientReportId: clientReportId,
        sidekickId: "reminders",
        kind: "unknown",
        bundleVersion: "v1",
        bundleScope: "base",
        transcript: "That I can move around everywhere",
        spokenText: "That I can move around everywhere",
        typedText: "",
        words: [],
        strokesJSON: Data("[]".utf8),
        screenshotJPEG: Data([0xFF, 0xD8]),
        drawingPNG: Data([1]),
        device: "iPhone",
        iosVersion: "27.0",
        appVersion: "1.0",
        appBuild: "44"
    )
}

// MARK: - Tests

@MainActor
final class RepairAgentQuestionTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "repair-agent-question-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeCenter(lanes: AgentQuestionLaneStub, appState: AgentQuestionAppState) -> RepairCenter {
        let sent = RepairOutbox(directoryURL: folder.appending(path: "sent"))
        return RepairCenter(notices: AgentQuestionNoNotices(), resender: AgentQuestionNoResend(), sentReports: sent, file: nil, pollSeconds: 3600, deeperLookPollSeconds: 3600, lanes: lanes, lanePollSeconds: 3600, laneWatchSeconds: 0, canceller: nil, isAppActive: appState.isActive)
    }

    /// Sent, sorted to code: the tag says "Editing".
    private func editingInCode(_ center: RepairCenter, lanes: AgentQuestionLaneStub, clientReportId: String) {
        center.didSend(agentQuestionReport(clientReportId))
        lanes.answer(clientReportId, with: agentReply(codeLaneJSON))
        center.uploaded(clientReportId: clientReportId, reply: agentReply(codeLaneJSON), listenMs: 0)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }

    func testTheWorkersAgentQuestionDecodesAsAnAskBackCard() {
        let reply = agentReply(agentLaneJSON)
        XCTAssertEqual(reply.lane, .askBack)
        XCTAssertEqual(reply.question?.text, "What should move?")
        XCTAssertEqual(reply.question?.options.map(\.label), ["Drag to Reorder", "Move to Another Day"])
        XCTAssertEqual(RepairLaneRules.step(for: reply), .question(reply.question!, repairId: "srv-a1"))
    }

    func testOnTheSidekickTheAgentsQuestionOpensByItselfWithItsCard() async {
        let lanes = AgentQuestionLaneStub()
        let center = makeCenter(lanes: lanes, appState: AgentQuestionAppState())
        center.sidekickOpened("reminders")
        editingInCode(center, lanes: lanes, clientReportId: "a1")

        // The agent asks while the edit runs; the next poll asks the lane of the code-lane edit
        lanes.answer("a1", with: agentReply(agentLaneJSON))
        await center.check()

        XCTAssertTrue(lanes.asked.contains("a1"), "the poll asks the lane of an edit already in code")
        XCTAssertEqual(center.questionsToOpen, ["a1"])
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question)
        XCTAssertEqual(RepairTagDisplay.question.words, RepairLaneCopy.oneQuestion)
        let opened = center.questionToOpen(for: "reminders", layerOpen: false)
        XCTAssertEqual(opened?.question.text, "What should move?")
        XCTAssertEqual(opened?.repairId, "srv-a1")
        XCTAssertEqual(opened?.report?.clientReportId, "a1", "the answer joins the same report")
        XCTAssertNil(center.latestPending(for: "reminders"), "no longer Editing")
    }

    func testAwayFromTheSidekickTheTagSaysOneQuestion() async {
        let lanes = AgentQuestionLaneStub()
        let center = makeCenter(lanes: lanes, appState: AgentQuestionAppState())
        center.sidekickOpened("todo")
        editingInCode(center, lanes: lanes, clientReportId: "a2")
        lanes.answer("a2", with: agentReply(agentLaneJSON.replacingOccurrences(of: "srv-a1", with: "srv-a2")))

        await center.check()

        XCTAssertTrue(center.questionsToOpen.isEmpty)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question)
        XCTAssertNotNil(center.waitingQuestion(for: "reminders"), "a tap opens it")
    }

    func testAnEditStillInCodeStaysEditing() async {
        let lanes = AgentQuestionLaneStub()
        let center = makeCenter(lanes: lanes, appState: AgentQuestionAppState())
        center.sidekickOpened("reminders")
        editingInCode(center, lanes: lanes, clientReportId: "a3")

        await center.check()

        XCTAssertTrue(center.questionsToOpen.isEmpty)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }

    func testTheAnswerGoesBackToEditing() async {
        let lanes = AgentQuestionLaneStub()
        let center = makeCenter(lanes: lanes, appState: AgentQuestionAppState())
        center.sidekickOpened("reminders")
        editingInCode(center, lanes: lanes, clientReportId: "a4")
        lanes.answer("a4", with: agentReply(agentLaneJSON))
        await center.check()
        guard let report = center.questionToOpen(for: "reminders", layerOpen: false)?.report else {
            XCTFail("the agent's question did not open with its report")
            return
        }

        // The card's Send: the tag takes the report back and the Worker answers { lane: code }
        center.putAwayNote(clientReportId: "a4")
        center.didSend(report)
        center.uploaded(clientReportId: "a4", reply: RepairSortRules.answerReply(.sorted(RepairSortReply(id: nil, lane: .code, question: nil, message: nil)), repairId: "srv-a1"), listenMs: 0)

        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }
}
