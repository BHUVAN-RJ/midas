import UIKit
import XCTest
@testable import Midas

// Answering the question card also closes repair mode at once (founder, 2026-11-22, the lead's
// answer to open question 2: "as soon as I click send it should send"; docs/PRODUCT.md 2cfa700).
// Send on the reopened card closes the layer like a first Send, the tag takes the report back
// ("Editing"), the answer uploads after the close, and the tag follows the answer's lane. The answer
// route's reply has no report id: the card's id is put in so Undo finds it. A card dropped before
// the answer (410) leaves the tag quietly.

@MainActor
private final class AnswerQuietTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {}

    func stop() {}
}

/// The answer route as a stub: every answer gets `outcome`, after `holdSeconds`.
private final class AnswerRouteStub: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAnswers: [(String, RepairSortAnswer)] = []
    private var storedReportCount = 0
    let outcome: RepairAnswerOutcome
    let holdSeconds: Double

    init(outcome: RepairAnswerOutcome, holdSeconds: Double = 0) {
        self.outcome = outcome
        self.holdSeconds = holdSeconds
    }

    var sortsReports: Bool {
        true
    }

    var answers: [(String, RepairSortAnswer)] {
        lock.lock()
        defer { lock.unlock() }
        return storedAnswers
    }

    var reportCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReportCount
    }

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        countReport()
        return .accepted
    }

    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        countReport()
        return RepairSortedUpload(outcome: .accepted, reply: nil)
    }

    func answerOutcome(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome {
        recordAnswer(repairId, answer)
        if holdSeconds > 0 {
            try? await Task.sleep(for: .seconds(holdSeconds))
        }
        return outcome
    }

    // NSLock cannot be taken inside an async function under Swift 6; these helpers are synchronous
    private func recordAnswer(_ repairId: String, _ answer: RepairSortAnswer) {
        lock.lock()
        storedAnswers.append((repairId, answer))
        lock.unlock()
    }

    private func countReport() {
        lock.lock()
        storedReportCount += 1
        lock.unlock()
    }
}

/// Undo and the lane route as a stub: the lane is never known; Undo always works.
private final class AnswerLaneStub: RepairLaneAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedUndos: [String] = []
    private var storedAsked = 0

    var undos: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedUndos
    }

    var askedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAsked
    }

    func lane(clientReportId: String) async -> RepairLaneCheck {
        countAsk()
        return .notFound
    }

    func undo(repairId: String) async -> Bool {
        recordUndo(repairId)
        return true
    }

    private func countAsk() {
        lock.lock()
        storedAsked += 1
        lock.unlock()
    }

    private func recordUndo(_ repairId: String) {
        lock.lock()
        storedUndos.append(repairId)
        lock.unlock()
    }
}

private struct AnswerNoNotices: JessRepairNoticesAPI {
    func notices() async -> [JessRepairNotice]? {
        []
    }

    func markSeen(id: String) async {}
}

@MainActor
private final class AnswerNoResend: RepairResending {
    func send(_ report: RepairReport) async {}
}

private let answerGuesses = [
    RepairQuestionOption(id: "other_colour", label: "Other colour", icon: "paintpalette"),
    RepairQuestionOption(id: "bigger", label: "Bigger", icon: "arrow.up.left.and.arrow.down.right"),
    RepairQuestionOption(id: "remove", label: "Remove", icon: "eye.slash")
]
private let answerQuestion = RepairQuestion(text: "What should it be?", options: answerGuesses)
private let biggerChange = RepairSettingResult(changes: [RepairSettingChange(key: "page.size", label: "Size of the reminder list")])

private func answerImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
    return renderer.image(actions: fillAnswerWhite)
}

private func fillAnswerWhite(_ context: UIGraphicsImageRendererContext) {
    UIColor.white.setFill()
    context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
}

private func answerReport(_ clientReportId: String) -> RepairReport {
    let drawing = answerImage().pngData() ?? Data([1])
    return RepairReport(
        clientReportId: clientReportId,
        sidekickId: "reminders",
        kind: "change",
        bundleVersion: "v1",
        bundleScope: "base",
        transcript: "change this",
        spokenText: "change this",
        typedText: "",
        words: [],
        strokesJSON: Data("[]".utf8),
        screenshotJPEG: Data([0xFF, 0xD8]),
        drawingPNG: drawing,
        device: "iPhone",
        iosVersion: "27.0",
        appVersion: "1.0",
        appBuild: "43"
    )
}

@MainActor
private func waitForAnswer(_ seconds: Double = 3, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

final class RepairAnswerReplyRulesTests: XCTestCase {
    func testTheCardsIdIsPutInWhenTheAnswerRouteSendsNone() {
        let routeReply = RepairSortReply(id: nil, lane: .setting, question: nil, message: "Changed", setting: biggerChange)
        let reply = RepairSortRules.answerReply(.sorted(routeReply), repairId: "srv-7")
        XCTAssertEqual(reply?.id, "srv-7")
        XCTAssertEqual(reply?.lane, .setting)
        XCTAssertEqual(reply?.setting, biggerChange)
        XCTAssertEqual(RepairLaneRules.step(for: reply!), .changed(repairId: "srv-7"))
    }

    func testAnIdTheRouteSentIsKept() {
        let routeReply = RepairSortReply(id: "srv-8", lane: .code, question: nil, message: nil)
        XCTAssertEqual(RepairSortRules.answerReply(.sorted(routeReply), repairId: "srv-7")?.id, "srv-8")
    }

    func testADroppedCardLeavesTheTagAndAFailureAsksTheLaneRoute() {
        let dropped = RepairSortRules.answerReply(.dropped, repairId: "srv-7")
        XCTAssertEqual(dropped.map(RepairLaneRules.step(for:)), .gone)
        XCTAssertNil(RepairSortRules.answerReply(.failed, repairId: "srv-7"))
        XCTAssertNil(RepairSortRules.answerReply(.sorted(nil), repairId: "srv-7"))
    }
}

@MainActor
final class RepairInstantAnswerTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "repair-instant-answer-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeSession(api: RepairUploadAPI) -> RepairSession {
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: folder.appending(path: "outbox")))
        return RepairSession(sidekickId: "reminders", snapshot: answerImage(), viewSize: CGSize(width: 20, height: 30), transcriber: AnswerQuietTranscriber(), uploader: uploader)
    }

    private func makeCenter(lanes: RepairLaneAPI) -> RepairCenter {
        let sent = RepairOutbox(directoryURL: folder.appending(path: "sent"))
        return RepairCenter(notices: AnswerNoNotices(), resender: AnswerNoResend(), sentReports: sent, file: nil, pollSeconds: 3600, deeperLookPollSeconds: 3600, lanes: lanes, lanePollSeconds: 0.01, laneWatchSeconds: 0.2)
    }

    /// The layer and the tag wired as the live app wires them (`SidekickScreen.showRepair`).
    private func wire(_ session: RepairSession, to center: RepairCenter) {
        session.onSent = { report, _ in center.didSend(report) }
        session.onUploaded = center.uploaded(report:reply:listenMs:)
    }

    func testSendOnTheCardClosesBeforeTheAnswerIsSorted() async {
        let api = AnswerRouteStub(outcome: .sorted(RepairSortReply(id: nil, lane: .code, question: nil, message: nil)), holdSeconds: 0.5)
        let session = makeSession(api: api)
        var finishedAs: RepairFinish?
        var sent: [RepairReport] = []
        var uploaded: [(String, RepairSortReply?)] = []
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { report, _ in sent.append(report) }
        session.onUploaded = { report, reply, _ in uploaded.append((report.clientReportId, reply)) }
        session.resumeQuestion(answerQuestion, repairId: "srv-7", report: answerReport("phone-7"))
        session.pick(answerGuesses[1])
        session.send()
        XCTAssertEqual(finishedAs, .sent, "the layer goes at once, before the answer is sorted")
        XCTAssertEqual(sent.map(\.clientReportId), ["phone-7"], "the tag takes the report back at once")
        XCTAssertTrue(uploaded.isEmpty)
        await waitForAnswer { !uploaded.isEmpty }
        XCTAssertEqual(api.answers.first?.0, "srv-7", "the answer joins the same report")
        XCTAssertEqual(api.answers.first?.1, .option("bigger"))
        XCTAssertEqual(api.reportCount, 0, "an answer is not a new report")
        XCTAssertEqual(uploaded.first?.0, "phone-7")
        XCTAssertEqual(uploaded.first?.1?.lane, .code)
        XCTAssertEqual(uploaded.first?.1?.id, "srv-7")
    }

    func testAnAnsweredSettingSaysChangedOnTheTagAndUndoFindsTheReport() async {
        let routeReply = RepairSortReply(id: nil, lane: .setting, question: nil, message: "Changed", setting: biggerChange)
        let api = AnswerRouteStub(outcome: .sorted(routeReply))
        let lanes = AnswerLaneStub()
        let center = makeCenter(lanes: lanes)
        var pulled = 0
        center.onSettingChanged = { _ in pulled += 1 }
        let session = makeSession(api: api)
        wire(session, to: center)
        session.resumeQuestion(answerQuestion, repairId: "srv-7", report: answerReport("phone-7"))
        session.typedText = "make the list bigger"
        session.send()
        XCTAssertEqual(session.finish, .sent)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false), "Editing while the answer is sorted")
        await waitForAnswer { center.display(for: "reminders", repairModeOn: false) == .changed }
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .changed)
        XCTAssertEqual(pulled, 1, "the page gets the new settings:self")
        XCTAssertEqual(api.answers.first?.1, .text("make the list bigger"))
        await center.undoChange(clientReportId: "phone-7")
        XCTAssertEqual(lanes.undos, ["srv-7"], "Undo goes to the card's report")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .undone)
    }

    func testAnAnswerAfterTheCardWasDroppedLeavesTheTagQuietly() async {
        let api = AnswerRouteStub(outcome: .dropped)
        let center = makeCenter(lanes: AnswerLaneStub())
        let session = makeSession(api: api)
        wire(session, to: center)
        session.resumeQuestion(answerQuestion, repairId: "srv-7", report: answerReport("phone-7"))
        session.pick(answerGuesses[0])
        session.send()
        XCTAssertEqual(session.finish, .sent, "no error: the layer closed at once")
        await waitForAnswer { center.state.pending.isEmpty }
        XCTAssertTrue(center.state.pending.isEmpty, "nothing is on its way")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false), "the tag goes quietly")
    }

    func testAnAnswerThatDidNotGoThroughAsksTheLaneRoute() async {
        let api = AnswerRouteStub(outcome: .failed)
        let lanes = AnswerLaneStub()
        let center = makeCenter(lanes: lanes)
        let session = makeSession(api: api)
        wire(session, to: center)
        session.resumeQuestion(answerQuestion, repairId: "srv-7", report: answerReport("phone-7"))
        session.pick(answerGuesses[2])
        session.send()
        await waitForAnswer { lanes.askedCount > 0 }
        XCTAssertGreaterThan(lanes.askedCount, 0, "the tag follows the lane by the phone's id")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }

    func testAnAnswerWithNoReportOnThePhoneStillSendsAndCloses() async {
        let api = AnswerRouteStub(outcome: .sorted(RepairSortReply(id: nil, lane: .code, question: nil, message: nil)))
        let session = makeSession(api: api)
        var sentCount = 0
        session.onSent = { _, _ in sentCount += 1 }
        session.resumeQuestion(answerQuestion, repairId: "srv-7", report: nil)
        session.pick(answerGuesses[1])
        session.send()
        XCTAssertEqual(session.finish, .sent)
        XCTAssertEqual(sentCount, 0, "no report to put on the tag")
        await waitForAnswer { !api.answers.isEmpty }
        XCTAssertEqual(api.answers.first?.0, "srv-7")
    }
}
