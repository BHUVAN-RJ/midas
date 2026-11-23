import SwiftUI
import UIKit
import XCTest
@testable import Midas

// Repair lanes on the phone (founder, 2026-11-13, D4 = A; docs/briefs/repair-lanes.md W3;
// docs/mockups/repair-ask-back-2026-11-08.html, "A · Cards", "Not a request", "Shell can't").
// The session runs against a stub of the W2 contract: POST /repairs → { id, lane, question?,
// message? }, POST /repairs/:id/answer { optionId } | { text } → { lane }.

/// A transcriber that hears nothing and never ends by itself.
@MainActor
private final class AskBackQuietTranscriber: RepairTranscribing {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

/// The W2 contract, played by the test: each report gets `reply`; each answer is recorded and
/// gets `answerReply`. `holdsReports` keeps the upload waiting forever (a sort that never answers).
private final class AskBackSortStub: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReports: [RepairReport] = []
    private var storedAnswers: [(String, RepairSortAnswer)] = []
    let reply: RepairSortReply?
    let answerReply: RepairSortReply?
    let holdsReports: Bool

    init(reply: RepairSortReply?, answerReply: RepairSortReply? = nil, holdsReports: Bool = false) {
        self.reply = reply
        self.answerReply = answerReply
        self.holdsReports = holdsReports
    }

    var sortsReports: Bool {
        true
    }

    var reports: [RepairReport] {
        lock.lock()
        defer { lock.unlock() }
        return storedReports
    }

    var answers: [(String, RepairSortAnswer)] {
        lock.lock()
        defer { lock.unlock() }
        return storedAnswers
    }

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        let sorted = try await uploadSorted(report)
        return sorted.outcome
    }

    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        recordReport(report)
        if holdsReports {
            try await Task.sleep(for: .seconds(60))
        }
        return RepairSortedUpload(outcome: .accepted, reply: reply)
    }

    func answer(repairId: String, answer: RepairSortAnswer) async throws -> RepairSortReply? {
        recordAnswer(repairId, answer)
        return answerReply
    }

    // NSLock cannot be taken inside an async function under Swift 6; these helpers are synchronous
    private func recordReport(_ report: RepairReport) {
        lock.lock()
        storedReports.append(report)
        lock.unlock()
    }

    private func recordAnswer(_ repairId: String, _ answer: RepairSortAnswer) {
        lock.lock()
        storedAnswers.append((repairId, answer))
        lock.unlock()
    }
}

/// An upload API from before the lanes: no sort.
private struct AskBackPlainUpload: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .accepted
    }
}

private let waterGuesses = [
    RepairQuestionOption(id: "glass", label: "Other icon", icon: "photo"),
    RepairQuestionOption(id: "smaller", label: "Smaller", icon: "arrow.down.right.and.arrow.up.left"),
    RepairQuestionOption(id: "remove", label: "Remove", icon: "nosign")
]

private let askBackReply = RepairSortReply(id: "srv-1", lane: .askBack, question: RepairQuestion(text: "What should it be?", options: waterGuesses), message: nil)
private let codeReply = RepairSortReply(id: nil, lane: .code, question: nil, message: nil)

// MARK: - The contract's words

final class RepairSortReplyTests: XCTestCase {
    private func decode(_ json: String) -> RepairSortReply? {
        RepairSortReply.decode(Data(json.utf8))
    }

    func testTodaysWorkerReplyWithNoLaneIsTheEditLane() {
        let reply = decode(#"{"id":"r1","status":"queued"}"#)
        XCTAssertEqual(reply?.lane, .code)
        XCTAssertEqual(reply?.id, "r1")
        XCTAssertEqual(RepairSortRules.decision(for: reply, knownRepairId: nil), .close)
    }

    func testAnUnknownLaneGoesUpToCode() {
        XCTAssertEqual(decode(#"{"id":"r1","lane":"teleport"}"#)?.lane, .code)
    }

    func testEverySevenLanesReadByTheirServerNames() {
        let names = ["ask_back", "not_a_request", "shell_cant", "jess_command", "setting", "look", "code"]
        let lanes = names.map(RepairLane.init(serverValue:))
        XCTAssertEqual(lanes, [.askBack, .notARequest, .shellCant, .jessCommand, .setting, .look, .code])
    }

    func testAskBackReplyDecodesTheQuestionAndGuesses() {
        let json = #"{"id":"r9","lane":"ask_back","question":{"text":"What should it be?","options":[{"id":"a","label":"Other icon","icon":"photo"},{"id":"b","label":"Smaller","icon":"minus"}]}}"#
        let reply = decode(json)
        XCTAssertEqual(reply?.lane, .askBack)
        XCTAssertEqual(reply?.question?.options.map(\.label), ["Other icon", "Smaller"])
        XCTAssertEqual(reply?.question?.options.first?.icon, "photo")
    }

    func testAnswerBodiesAreTheContractsTwoShapes() throws {
        let optionBody = try RepairSortAnswer.option("glass").jsonBody()
        let textBody = try RepairSortAnswer.text("a glass").jsonBody()
        XCTAssertEqual(String(decoding: optionBody, as: UTF8.self), #"{"optionId":"glass"}"#)
        XCTAssertEqual(String(decoding: textBody, as: UTF8.self), #"{"text":"a glass"}"#)
    }

    func testAnswerRequestPostsToTheReportsAnswerPathWithTheSession() throws {
        let origin = URL(string: "https://example.invalid")!
        let request = try RemoteRepairUploadAPI.answerRequest(platformOrigin: origin, repairId: "srv-1", answer: .option("glass"), token: "tok")
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/repairs/srv-1/answer")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody.map { String(decoding: $0, as: UTF8.self) }, #"{"optionId":"glass"}"#)
    }

    func testTheLiveUploadSortsAndOldOnesDoNot() {
        let live = RemoteRepairUploadAPI(platformOrigin: URL(string: "https://example.invalid")!, session: .shared, sessionToken: { nil })
        XCTAssertTrue(live.sortsReports)
        XCTAssertFalse(AskBackPlainUpload().sortsReports)
    }
}

// MARK: - The rules

final class RepairSortRulesTests: XCTestCase {
    func testAskBackShowsAtMostThreeGuesses() {
        let four = waterGuesses + [RepairQuestionOption(id: "bigger", label: "Bigger", icon: nil)]
        let reply = RepairSortReply(id: "r1", lane: .askBack, question: RepairQuestion(text: "What should it be?", options: four), message: nil)
        guard case .ask(let question, let repairId) = RepairSortRules.decision(for: reply, knownRepairId: nil) else {
            return XCTFail("ask_back with guesses must ask")
        }
        XCTAssertEqual(question.options.map(\.id), ["glass", "smaller", "remove"])
        XCTAssertEqual(repairId, "r1")
    }

    func testAskBackWithNoGuessesOrNoIdGoesUpToTheEditLane() {
        let empty = RepairSortReply(id: "r1", lane: .askBack, question: RepairQuestion(text: "What?", options: []), message: nil)
        let noQuestion = RepairSortReply(id: "r1", lane: .askBack, question: nil, message: nil)
        let noId = RepairSortReply(id: nil, lane: .askBack, question: RepairQuestion(text: "What?", options: waterGuesses), message: nil)
        XCTAssertEqual(RepairSortRules.decision(for: empty, knownRepairId: nil), .close)
        XCTAssertEqual(RepairSortRules.decision(for: noQuestion, knownRepairId: nil), .close)
        XCTAssertEqual(RepairSortRules.decision(for: noId, knownRepairId: nil), .close)
    }

    func testAnAnswerAskedAgainKeepsTheSameReport() {
        let again = RepairSortReply(id: nil, lane: .askBack, question: RepairQuestion(text: "Which one?", options: waterGuesses), message: nil)
        guard case .ask(_, let repairId) = RepairSortRules.decision(for: again, knownRepairId: "srv-1") else {
            return XCTFail("a second question must still ask")
        }
        XCTAssertEqual(repairId, "srv-1")
    }

    func testNoReplyAndEveryJobLaneClose() {
        XCTAssertEqual(RepairSortRules.decision(for: nil, knownRepairId: nil), .close)
        for lane in [RepairLane.jessCommand, .setting, .look, .code] {
            let reply = RepairSortReply(id: "r1", lane: lane, question: nil, message: nil)
            XCTAssertEqual(RepairSortRules.decision(for: reply, knownRepairId: nil), .close, lane.rawValue)
        }
    }

    func testNotARequestListensWithTheServersLineOrTheFoundersWords() {
        let withLine = RepairSortReply(id: "r1", lane: .notARequest, question: nil, message: "Say what to change.")
        let without = RepairSortReply(id: "r1", lane: .notARequest, question: nil, message: nil)
        XCTAssertEqual(RepairSortRules.decision(for: withLine, knownRepairId: nil), .listen(message: "Say what to change."))
        XCTAssertEqual(RepairSortRules.decision(for: without, knownRepairId: nil), .listen(message: "Say or draw what to change."))
    }

    func testShellCantSplitsSentToMidasOntoItsOwnLine() {
        let both = RepairSortRules.shellCantMessage("Water can’t remind every hour yet. Sent to Midas.")
        let titleOnly = RepairSortRules.shellCantMessage("Water can’t remind every hour yet.")
        XCTAssertEqual(both, RepairShellCantMessage(title: "Water can’t remind every hour yet.", detail: "Sent to Midas."))
        XCTAssertEqual(titleOnly, both)
    }

    func testATappedGuessAnswersByIdUntilTheWordsChange() {
        let tapped = RepairSortRules.answer(pickedOptionId: "glass", options: waterGuesses, words: "Other icon")
        let changed = RepairSortRules.answer(pickedOptionId: "glass", options: waterGuesses, words: "Other icon, a glass")
        let spoken = RepairSortRules.answer(pickedOptionId: nil, options: waterGuesses, words: "a glass")
        let nothing = RepairSortRules.answer(pickedOptionId: "glass", options: waterGuesses, words: "  ")
        XCTAssertEqual(tapped, .option("glass"))
        XCTAssertEqual(changed, .text("Other icon, a glass"))
        XCTAssertEqual(spoken, .text("a glass"))
        XCTAssertNil(nothing)
    }

    func testTheTagSaysEditingWhileSortingAndOneQuestionWhileAsking() {
        let question = RepairQuestion(text: "What should it be?", options: waterGuesses)
        let sorting = RepairAskBackTag.shown(stage: .sorting, base: .repairMode)
        let asking = RepairAskBackTag.shown(stage: .asking(question), base: .repairMode)
        let notARequest = RepairAskBackTag.shown(stage: .notARequest("Say or draw what to change."), base: .repairMode)
        let closed = RepairAskBackTag.shown(stage: nil, base: .couldntFix)
        XCTAssertEqual(sorting?.display, .repairing(count: 1, takingLonger: false))
        XCTAssertEqual(asking?.display, .repairMode)
        XCTAssertEqual(asking?.words, "One question")
        XCTAssertEqual(notARequest?.words, nil, "not a request: no tag change")
        XCTAssertEqual(notARequest?.display, .repairMode)
        XCTAssertEqual(closed?.display, .couldntFix)
    }

    func testTheMockupsWords() {
        XCTAssertEqual(RepairAskBackCopy.oneQuestion, "One question")
        XCTAssertEqual(RepairAskBackCopy.orSayIt, "Or say it…")
        XCTAssertEqual(RepairAskBackCopy.question, "What should it be?")
        XCTAssertEqual(RepairAskBackCopy.notARequest, "Say or draw what to change.")
        XCTAssertEqual(RepairAskBackCopy.sentToMidas, "Sent to Midas.")
    }

    func testAGuessPictureIsASymbolAShortTextOrAPlainMark() {
        func onlyPhoto(_ name: String) -> Bool {
            name == "photo"
        }
        XCTAssertEqual(RepairOptionPicture.forIcon("photo", symbolExists: onlyPhoto), .symbol("photo"))
        XCTAssertEqual(RepairOptionPicture.forIcon("∅", symbolExists: onlyPhoto), .text("∅"))
        XCTAssertEqual(RepairOptionPicture.forIcon("not.a.real.symbol", symbolExists: onlyPhoto), .blank)
        XCTAssertEqual(RepairOptionPicture.forIcon(nil, symbolExists: onlyPhoto), .blank)
        XCTAssertEqual(RepairOptionPicture.forIcon("photo"), .symbol("photo"), "iOS has the photo symbol")
    }
}

// MARK: - The session against the W2 stub

@MainActor
final class RepairAskBackSessionTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-askback-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private static func snapshot() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
        return renderer.image(actions: fillWhite)
    }

    private static func fillWhite(_ context: UIGraphicsImageRendererContext) {
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
    }

    private func makeSession(api: RepairUploadAPI, transcriber: AskBackQuietTranscriber = AskBackQuietTranscriber()) -> RepairSession {
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: outboxURL))
        let session = RepairSession(sidekickId: "water", snapshot: Self.snapshot(), viewSize: CGSize(width: 20, height: 30), transcriber: transcriber, uploader: uploader)
        session.beginStroke(at: CGPoint(x: 4, y: 4))
        session.extendStroke(to: CGPoint(x: 12, y: 18))
        session.endStroke()
        return session
    }

    /// Waits on the main actor until the condition holds, at most `seconds`.
    private func waitUntil(_ seconds: Double = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isAsking(_ session: RepairSession) -> Bool {
        session.askStage.question != nil
    }

    /// The report a first Send on its own layer handed to the tag: what the tag's "1 question"
    /// reopens the card with.
    private func firstSentReport(api: RepairUploadAPI) -> RepairReport? {
        let session = makeSession(api: api)
        var sent: RepairReport?
        session.onSent = { report, _ in sent = report }
        session.typedText = "I hate this can you change this"
        session.send()
        return sent
    }

    // Founder, 2026-11-22 (docs/PRODUCT.md, "Send closes at once", amends D4): a first Send closes
    // repair mode at once whatever the lane; the question goes to the tag ("1 question"), and the
    // card is reached only by reopening it from there (`resumeQuestion`).
    func testUnclearRequestClosesAtOnceAndTheQuestionGoesToTheTagWhichReopensTheCard() async {
        let api = AskBackSortStub(reply: askBackReply, answerReply: codeReply)
        let session = makeSession(api: api)
        var sentCount = 0
        var finishCount = 0
        var heard: RepairSortReply?
        session.onSent = { _, _ in sentCount += 1 }
        session.onFinish = { finishCount += 1 }
        session.onUploaded = { _, reply, _ in heard = reply }
        session.typedText = "I hate this can you change this"
        session.send()
        XCTAssertEqual(session.finish, .sent, "Send closes at once, before the lane is known")
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(sentCount, 1, "the tag takes the report at once")
        XCTAssertEqual(session.askStage, .open, "the layer does not wait for the lane")
        await waitUntil { heard != nil }
        XCTAssertEqual(heard, askBackReply, "the question reaches the tag")
        XCTAssertEqual(heard.map(RepairLaneRules.step), .question(RepairQuestion(text: "What should it be?", options: waterGuesses), repairId: "srv-1"))
        XCTAssertEqual(session.askStage, .open, "no card on the closed layer")
        XCTAssertEqual(finishCount, 1)

        let reopened = makeSession(api: api)
        reopened.resumeQuestion(RepairQuestion(text: "What should it be?", options: waterGuesses), repairId: "srv-1", report: nil)
        XCTAssertEqual(reopened.askStage.question?.options.map(\.label), ["Other icon", "Smaller", "Remove"])
        XCTAssertNil(reopened.finish, "the reopened card stays up until Send")
        XCTAssertEqual(reopened.typedText, "", "the pill is empty for the answer")
        XCTAssertFalse(reopened.canSend, "no answer yet, Send is off")
        XCTAssertEqual(reopened.pillPlaceholder, "Or say it…")
        XCTAssertEqual(reopened.strokes.count, 1, "the drawing stays")
    }

    func testATapFillsThePillAndSendAnswersTheSameRequestThenCloses() async {
        let api = AskBackSortStub(reply: askBackReply, answerReply: codeReply)
        guard let original = firstSentReport(api: api) else {
            return XCTFail("the first Send must hand a report to the tag")
        }
        let session = makeSession(api: api)
        var sent: [RepairReport] = []
        var finishCount = 0
        var heard: RepairSortReply?
        var heardFor: RepairReport?
        session.onSent = { report, _ in sent.append(report) }
        session.onFinish = { finishCount += 1 }
        session.onUploaded = { report, reply, _ in
            heardFor = report
            heard = reply
        }
        session.resumeQuestion(RepairQuestion(text: "What should it be?", options: waterGuesses), repairId: "srv-1", report: original)
        session.pick(waterGuesses[0])
        XCTAssertEqual(session.typedText, "Other icon", "a tap fills the pill")
        XCTAssertEqual(session.pickedOptionId, "glass")
        XCTAssertTrue(session.canSend)
        session.send()
        XCTAssertEqual(session.finish, .sent, "the answer's Send closes at once too")
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(sent.map(\.clientReportId), [original.clientReportId], "the tag takes the same report back, once")
        await waitUntil { heard != nil }
        XCTAssertEqual(api.answers.count, 1)
        XCTAssertEqual(api.answers.first?.0, "srv-1", "the answer joins the same report")
        XCTAssertEqual(api.answers.first?.1, .option("glass"))
        XCTAssertEqual(api.reports.count, 1, "an answer is not a new report")
        XCTAssertEqual(heardFor?.clientReportId, original.clientReportId)
        XCTAssertEqual(heard?.id, "srv-1", "the answer's lane reaches the tag under the card's id")
        XCTAssertEqual(heard?.lane, .code)
    }

    func testSpokenOrChangedWordsAnswerAsText() async {
        let api = AskBackSortStub(reply: askBackReply, answerReply: codeReply)
        let session = makeSession(api: api)
        session.resumeQuestion(RepairQuestion(text: "What should it be?", options: waterGuesses), repairId: "srv-1", report: nil)
        session.pick(waterGuesses[0])
        session.typedText = "Other icon: a glass"
        session.send()
        await waitUntil { !api.answers.isEmpty }
        XCTAssertEqual(api.answers.first?.0, "srv-1")
        XCTAssertEqual(api.answers.first?.1, .text("Other icon: a glass"))
    }

    func testNotARequestClosesAtOnceAndTheLineGoesToTheTag() async {
        let reply = RepairSortReply(id: "srv-2", lane: .notARequest, question: nil, message: "Say or draw what to change.")
        let api = AskBackSortStub(reply: reply)
        let session = makeSession(api: api)
        var finishCount = 0
        var sentCount = 0
        var heard: RepairSortReply?
        session.onFinish = { finishCount += 1 }
        session.onSent = { _, _ in sentCount += 1 }
        session.onUploaded = { _, uploadReply, _ in heard = uploadReply }
        session.typedText = "How are you"
        session.send()
        XCTAssertEqual(session.finish, .sent, "Send closes at once")
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(sentCount, 1)
        await waitUntil { heard != nil }
        XCTAssertEqual(heard, reply)
        XCTAssertEqual(heard.map(RepairLaneRules.step), .message("Say or draw what to change."), "the tag says the line")
        XCTAssertNil(session.pillMessage, "no line on the closed layer")
        XCTAssertEqual(session.askStage, .open)
        XCTAssertEqual(finishCount, 1)
    }

    func testShellCantClosesAtOnceAndTheMessageGoesToTheTag() async {
        let reply = RepairSortReply(id: "srv-3", lane: .shellCant, question: nil, message: "Water can’t remind every hour yet. Sent to Midas.")
        let api = AskBackSortStub(reply: reply)
        let session = makeSession(api: api)
        var finishCount = 0
        var sentCount = 0
        var heard: RepairSortReply?
        session.onFinish = { finishCount += 1 }
        session.onSent = { _, _ in sentCount += 1 }
        session.onUploaded = { _, uploadReply, _ in heard = uploadReply }
        session.typedText = "Can you add every one hour as an option"
        session.send()
        XCTAssertEqual(session.finish, .sent, "Send closes at once")
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(sentCount, 1)
        await waitUntil { heard != nil }
        XCTAssertEqual(heard, reply)
        XCTAssertEqual(heard.map(RepairLaneRules.step), .message("Water can’t remind every hour yet. Sent to Midas."), "the tag says both lines")
        XCTAssertEqual(session.askStage, .open, "no dark sheet on the closed layer")
        XCTAssertEqual(finishCount, 1)
    }

    func testAnEditLaneClosesAsSendAlwaysDid() async {
        let api = AskBackSortStub(reply: RepairSortReply(id: "srv-4", lane: .setting, question: nil, message: nil))
        let session = makeSession(api: api)
        var finishedAs: RepairFinish?
        var sentCount = 0
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { _, _ in sentCount += 1 }
        session.typedText = "make this blue"
        session.send()
        await waitUntil { finishedAs != nil }
        XCTAssertEqual(finishedAs, .sent)
        XCTAssertEqual(sentCount, 1)
    }

    func testASortThatNeverAnswersClosesAsAnEdit() async {
        let api = AskBackSortStub(reply: askBackReply, holdsReports: true)
        let session = makeSession(api: api)
        var finishedAs: RepairFinish?
        var sentCount = 0
        var uploadedCount = 0
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { _, _ in sentCount += 1 }
        session.onUploaded = { _, _, _ in uploadedCount += 1 }
        session.typedText = "change this"
        session.send()
        XCTAssertEqual(finishedAs, .sent, "closes at once, without waiting for the sort")
        XCTAssertEqual(sentCount, 1, "the tag takes it as an edit")
        await waitUntil(0.3) { uploadedCount > 0 }
        XCTAssertEqual(uploadedCount, 0, "the sort has not answered")
        XCTAssertEqual(session.finish, .sent)
    }

    func testCancelWhileAskingSendsNoAnswer() async {
        let api = AskBackSortStub(reply: askBackReply, answerReply: codeReply)
        guard let original = firstSentReport(api: api) else {
            return XCTFail("the first Send must hand a report to the tag")
        }
        let session = makeSession(api: api)
        var sentCount = 0
        session.onSent = { _, _ in sentCount += 1 }
        session.resumeQuestion(RepairQuestion(text: "What should it be?", options: waterGuesses), repairId: "srv-1", report: original)
        session.pick(waterGuesses[0])
        session.cancel()
        XCTAssertEqual(session.finish, .cancelled)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(api.answers.isEmpty)
        XCTAssertEqual(sentCount, 0, "Cancel hands nothing to the tag")
    }

    func testWithoutASortSendClosesAtOnce() {
        let session = makeSession(api: AskBackPlainUpload())
        session.typedText = "move it"
        session.send()
        XCTAssertEqual(session.finish, .sent)
        XCTAssertEqual(session.askStage, .open)
    }
}

// MARK: - The card and the sheet draw

@MainActor
final class RepairQuestionCardLayoutTests: XCTestCase {
    private func renderedSize<Content: View>(_ view: Content, width: CGFloat) -> CGSize {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        return renderer.uiImage?.size ?? .zero
    }

    func testThreeGuessesSitSideBySideInOneRow() {
        let question = RepairQuestion(text: "What should it be?", options: waterGuesses)
        let card = RepairQuestionCard(question: question, pickedOptionId: "glass", onPick: Self.ignorePick)
        let size = renderedSize(card, width: 378)
        // Question (≈23) + gap 12 + one row of guesses (12 + 44 + 6 + ≈18 + 12) + padding 32: about
        // 160 pt. Guesses stacked in a column would be over 300.
        XCTAssertEqual(size.width, 378)
        XCTAssertGreaterThan(size.height, 130)
        XCTAssertLessThan(size.height, 200)
    }

    func testTheSheetHoldsBothLines() {
        let sheet = RepairShellCantSheet(message: RepairShellCantMessage(title: "Water can’t remind every hour yet.", detail: "Sent to Midas."))
        let size = renderedSize(sheet, width: 378)
        let detailOnly = renderedSize(RepairShellCantSheet(message: RepairShellCantMessage(title: "", detail: "Sent to Midas.")), width: 378)
        XCTAssertGreaterThan(size.height, detailOnly.height + 15, "the bold line sits above Sent to Midas.")
    }

    private static func ignorePick(_ option: RepairQuestionOption) {}
}
