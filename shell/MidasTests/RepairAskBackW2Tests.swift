import UIKit
import XCTest
@testable import Midas

// The phone against W2 as built (W2 hand-back docs/handbacks/agent-repair-sort.md, lead's three
// points, 2026-11-13): POST /repairs replies { id, status, lane, question?, message? }; the answer
// route returns message for shell_cant; 410 on an answer = the card was dropped (close it quietly);
// POST /repairs can take about 12 s; jess_command hands the words to jess and closes repair mode.
// Since 2026-11-22 (founder, docs/PRODUCT.md "Send closes at once", amends D4) every Send, the
// card's answer too, closes repair mode at once and the reply goes to the tag (`RepairLaneRules`).

@MainActor
private final class W2QuietTranscriber: RepairTranscribing {
    private(set) var startCount = 0

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        startCount += 1
    }

    func stop() {}
}

/// W2 as a stub: every report gets `reply`; every answer gets `answerOutcome`.
private final class W2SortStub: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReports: [RepairReport] = []
    private var storedAnswerCount = 0
    let reply: RepairSortReply
    let answerResult: RepairAnswerOutcome

    init(reply: RepairSortReply, answerResult: RepairAnswerOutcome = .failed) {
        self.reply = reply
        self.answerResult = answerResult
    }

    var sortsReports: Bool {
        true
    }

    var reports: [RepairReport] {
        lock.lock()
        defer { lock.unlock() }
        return storedReports
    }

    var answerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAnswerCount
    }

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .accepted
    }

    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        recordReport(report)
        return RepairSortedUpload(outcome: .accepted, reply: reply)
    }

    func answerOutcome(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome {
        countAnswer()
        return answerResult
    }

    // NSLock cannot be taken inside an async function under Swift 6; these helpers are synchronous
    private func recordReport(_ report: RepairReport) {
        lock.lock()
        storedReports.append(report)
        lock.unlock()
    }

    private func countAnswer() {
        lock.lock()
        storedAnswerCount += 1
        lock.unlock()
    }
}

/// W2's card guesses: the three it always fills from, as its hand-back's table names them.
private let w2Guesses = [
    RepairQuestionOption(id: "other_icon", label: "Other icon", icon: "photo"),
    RepairQuestionOption(id: "smaller", label: "Smaller", icon: "arrow.down.right.and.arrow.up.left"),
    RepairQuestionOption(id: "remove", label: "Remove", icon: "eye.slash")
]
private let w2AskBack = RepairSortReply(id: "srv-9", lane: .askBack, question: RepairQuestion(text: "What should it be?", options: w2Guesses), message: nil)

final class RepairW2ContractTests: XCTestCase {
    func testW2sFullReplyDecodes() {
        let json = #"{"id":"r1","status":"received","lane":"ask_back","question":{"text":"What should it be?","options":[{"id":"other_icon","label":"Other icon","icon":"photo"},{"id":"smaller","label":"Smaller","icon":"arrow.down.right.and.arrow.up.left"},{"id":"remove","label":"Remove","icon":"eye.slash"}]}}"#
        let reply = RepairSortReply.decode(Data(json.utf8))
        XCTAssertEqual(reply?.lane, .askBack)
        XCTAssertEqual(reply?.question?.options.map(\.id), ["other_icon", "smaller", "remove"])
    }

    func testEveryW2GuessIconIsAnSFSymbolOnThisPhone() {
        let icons = ["photo", "arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right", "paintpalette", "eye.slash", "arrow.up.and.down.and.arrow.left.and.right", "textformat", "square.grid.2x2"]
        for icon in icons {
            XCTAssertEqual(RepairOptionPicture.forIcon(icon), .symbol(icon), icon)
        }
    }

    func testAnswerRoute410IsADroppedCard() {
        XCTAssertEqual(RemoteRepairUploadAPI.answerOutcome(statusCode: 410, body: Data()), .dropped)
        XCTAssertEqual(RemoteRepairUploadAPI.answerOutcome(statusCode: 409, body: Data()), .failed)
        XCTAssertEqual(RemoteRepairUploadAPI.answerOutcome(statusCode: 500, body: Data()), .failed)
    }

    func testAnswerRouteShellCantCarriesItsMessage() {
        let body = Data(#"{"lane":"shell_cant","message":"Water can't do that yet. Sent to Midas."}"#.utf8)
        let outcome = RemoteRepairUploadAPI.answerOutcome(statusCode: 200, body: body)
        let expected = RepairSortReply(id: nil, lane: .shellCant, question: nil, message: "Water can't do that yet. Sent to Midas.")
        XCTAssertEqual(outcome, .sorted(expected))
    }

    func testThePhoneWaitsLongerThanTheSortsWorstCase() throws {
        // W2: Jev 6 s, then Haiku 6 s, about 12 s at worst
        XCTAssertGreaterThan(RepairAskBackSpec.sortWaitSeconds, 12)
        XCTAssertGreaterThan(RepairAskBackSpec.requestTimeoutSeconds, RepairAskBackSpec.sortWaitSeconds)
        let request = try RemoteRepairUploadAPI.answerRequest(platformOrigin: URL(string: "https://example.invalid")!, repairId: "r1", answer: .text("a glass"), token: "tok")
        XCTAssertEqual(request.timeoutInterval, RepairAskBackSpec.requestTimeoutSeconds)
    }

    func testOnlyTheJessLaneGoesToJess() {
        for lane in RepairLane.allCases {
            let reply = RepairSortReply(id: "r1", lane: lane, question: nil, message: nil)
            XCTAssertEqual(RepairSortRules.handsToJess(reply), lane == .jessCommand, lane.rawValue)
        }
        XCTAssertFalse(RepairSortRules.handsToJess(nil))
    }
}

@MainActor
final class RepairW2SessionTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-w2-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private func makeSession(api: RepairUploadAPI, transcriber: W2QuietTranscriber = W2QuietTranscriber()) -> RepairSession {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format).image(actions: Self.fillWhite)
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: outboxURL))
        return RepairSession(sidekickId: "water", snapshot: snapshot, viewSize: CGSize(width: 20, height: 30), transcriber: transcriber, uploader: uploader)
    }

    private static func fillWhite(_ context: UIGraphicsImageRendererContext) {
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
    }

    private func waitUntil(_ seconds: Double = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The report a first Send on its own layer handed to the tag: what the tag's "1 question"
    /// reopens the card with.
    private func firstSentReport(api: RepairUploadAPI) -> RepairReport? {
        let session = makeSession(api: api)
        var sent: RepairReport?
        session.onSent = { report, _ in sent = report }
        session.typedText = "change this"
        session.send()
        return sent
    }

    func testJessCommandClosesAtOnceAndTheTagHandsItToJess() async {
        let reply = RepairSortReply(id: "srv-5", lane: .jessCommand, question: nil, message: nil)
        let api = W2SortStub(reply: reply)
        let session = makeSession(api: api)
        var finishCount = 0
        var sentCount = 0
        var heard: RepairSortReply?
        var heardFor: RepairReport?
        session.onFinish = { finishCount += 1 }
        session.onSent = { _, _ in sentCount += 1 }
        session.onUploaded = { report, uploadReply, _ in
            heardFor = report
            heard = uploadReply
        }
        session.typedText = "Create a reminder for medicine"
        session.send()
        XCTAssertEqual(session.finish, .sent, "Send closes at once, before the lane is known")
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(sentCount, 1)
        await waitUntil { heard != nil }
        XCTAssertEqual(heard, reply)
        XCTAssertEqual(heard.map(RepairLaneRules.step), .toJess, "the tag hands it to jess")
        XCTAssertEqual(heardFor?.transcript, "Create a reminder for medicine", "the words go with it, as said")
    }

    func testADroppedCardClosesAtOnceAndTheTagGoesQuietly() async {
        let api = W2SortStub(reply: w2AskBack, answerResult: .dropped)
        guard let original = firstSentReport(api: api) else {
            return XCTFail("the first Send must hand a report to the tag")
        }
        let session = makeSession(api: api)
        var finishCount = 0
        var sentCount = 0
        var heard: RepairSortReply?
        session.onFinish = { finishCount += 1 }
        session.onSent = { _, _ in sentCount += 1 }
        session.onUploaded = { _, uploadReply, _ in heard = uploadReply }
        session.resumeQuestion(RepairQuestion(text: "What should it be?", options: w2Guesses), repairId: "srv-9", report: original)
        session.pick(w2Guesses[2])
        session.send()
        XCTAssertEqual(session.finish, .sent, "the answer's Send closes at once")
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(sentCount, 1)
        await waitUntil { heard != nil }
        XCTAssertEqual(api.answerCount, 1)
        XCTAssertEqual(api.reports.count, 1, "an answer is not a new report")
        XCTAssertEqual(heard?.id, "srv-9")
        XCTAssertEqual(heard?.sortStatus, RepairSortStatus.dropped)
        XCTAssertEqual(heard.map(RepairLaneRules.step), .gone, "the tag goes quietly")
    }

    func testAnAnswerSortedShellCantReachesTheTagWithTheRoutesMessage() async {
        let shellCant = RepairSortReply(id: nil, lane: .shellCant, question: nil, message: "Water can't do that yet. Sent to Midas.")
        let api = W2SortStub(reply: w2AskBack, answerResult: .sorted(shellCant))
        guard let original = firstSentReport(api: api) else {
            return XCTFail("the first Send must hand a report to the tag")
        }
        let session = makeSession(api: api)
        var heard: RepairSortReply?
        session.onUploaded = { _, uploadReply, _ in heard = uploadReply }
        session.resumeQuestion(RepairQuestion(text: "What should it be?", options: w2Guesses), repairId: "srv-9", report: original)
        session.typedText = "every hour"
        session.send()
        XCTAssertEqual(session.finish, .sent, "the answer's Send closes at once")
        await waitUntil { heard != nil }
        XCTAssertEqual(heard?.lane, .shellCant)
        XCTAssertEqual(heard?.id, "srv-9", "the card's id, the route sent none")
        XCTAssertEqual(heard.map(RepairLaneRules.step), .message("Water can't do that yet. Sent to Midas."))
        if case .shellCant = session.askStage {
            XCTFail("no dark sheet on the closed layer")
        }
    }
}
