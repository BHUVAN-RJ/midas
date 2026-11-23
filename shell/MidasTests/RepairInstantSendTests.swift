import UIKit
import XCTest
@testable import Midas

// Send closes repair mode at once (founder, 2026-11-22: "Send closes repair at once; the lane result
// comes back to the tag"; docs/briefs/repair-lanes.md "Change 2026-11-22"). The layer goes the
// moment Send is tapped, the tag takes the report ("Editing"), the upload asks the Worker to answer
// before it sorts (laneFollow=1), and the tag (`RepairCenter`) follows the lane with
// GET /repairs/lanes/:clientReportId: setting done → "Changed" with Undo, code → "Editing" stays,
// jess_command → the words go to jess, ask_back → "1 question" that reopens the card, not a request
// → the message for a moment.

// MARK: - Stand-ins

@MainActor
private final class InstantQuietTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {}

    func stop() {}
}

/// The Worker as a stub: every upload gets `reply` (after `holdSeconds`), every answer `answerReply`.
private final class InstantUploadStub: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReports: [RepairReport] = []
    private var storedAnswers: [(String, RepairSortAnswer)] = []
    let reply: RepairSortReply?
    let answerReply: RepairSortReply?
    let holdSeconds: Double

    init(reply: RepairSortReply?, answerReply: RepairSortReply? = nil, holdSeconds: Double = 0) {
        self.reply = reply
        self.answerReply = answerReply
        self.holdSeconds = holdSeconds
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
        .accepted
    }

    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        recordReport(report)
        if holdSeconds > 0 {
            try await Task.sleep(for: .seconds(holdSeconds))
        }
        return RepairSortedUpload(outcome: .accepted, reply: reply)
    }

    func answerOutcome(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome {
        recordAnswer(repairId, answer)
        guard let answerReply else {
            return .failed
        }
        return .sorted(answerReply)
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

/// The lane route and Undo as a stub: each report's answers are played in turn (the last repeats).
private final class InstantLaneStub: RepairLaneAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [String: [RepairLaneCheck]] = [:]
    private var storedAsked: [String] = []
    private var storedUndos: [String] = []
    var undoWorks = true

    func plan(_ clientReportId: String, _ checks: [RepairLaneCheck]) {
        lock.lock()
        plans[clientReportId] = checks
        lock.unlock()
    }

    var asked: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedAsked
    }

    var undos: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedUndos
    }

    func lane(clientReportId: String) async -> RepairLaneCheck {
        nextCheck(clientReportId)
    }

    func undo(repairId: String) async -> Bool {
        recordUndo(repairId)
    }

    private func nextCheck(_ clientReportId: String) -> RepairLaneCheck {
        lock.lock()
        defer { lock.unlock() }
        storedAsked.append(clientReportId)
        guard var checks = plans[clientReportId], let first = checks.first else {
            return .notFound
        }
        if checks.count > 1 {
            checks.removeFirst()
            plans[clientReportId] = checks
        }
        return first
    }

    private func recordUndo(_ repairId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storedUndos.append(repairId)
        return undoWorks
    }
}

private struct InstantNoNotices: JessRepairNoticesAPI {
    func notices() async -> [JessRepairNotice]? {
        []
    }

    func markSeen(id: String) async {}
}

@MainActor
private final class InstantNoResend: RepairResending {
    func send(_ report: RepairReport) async {}
}

/// A clock the test moves.
private final class InstantClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func read() -> Date {
        now
    }
}

private let instantGuesses = [
    RepairQuestionOption(id: "other_colour", label: "Other colour", icon: "paintpalette"),
    RepairQuestionOption(id: "bigger", label: "Bigger", icon: "arrow.up.left.and.arrow.down.right"),
    RepairQuestionOption(id: "remove", label: "Remove", icon: "eye.slash")
]
private let instantQuestion = RepairQuestion(text: "What should it be?", options: instantGuesses)
private let redChange = RepairSettingResult(changes: [RepairSettingChange(key: "accent.colour", label: "Main colour (buttons and links)")])

private func stillSorting(_ id: String) -> RepairSortReply {
    RepairSortReply(id: id, lane: .code, question: nil, message: nil, laneKnown: false, sortStatus: "sorting")
}

private func laneReply(_ id: String, _ lane: RepairLane, question: RepairQuestion? = nil, message: String? = nil, setting: RepairSettingResult? = nil, status: String = "sorted") -> RepairSortReply {
    RepairSortReply(id: id, lane: lane, question: question, message: message, setting: setting, laneKnown: true, sortStatus: status)
}

private func instantImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format)
    return renderer.image(actions: fillInstantWhite)
}

private func fillInstantWhite(_ context: UIGraphicsImageRendererContext) {
    UIColor.white.setFill()
    context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
}

private func instantReport(_ clientReportId: String, sidekickId: String = "reminders", transcript: String = "can you change the color to red") -> RepairReport {
    let drawing = instantImage().pngData() ?? Data([1])
    return RepairReport(
        clientReportId: clientReportId,
        sidekickId: sidekickId,
        kind: "change",
        bundleVersion: "v1",
        bundleScope: "base",
        transcript: transcript,
        spokenText: transcript,
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

/// Waits on the main actor until the condition holds, at most `seconds`.
@MainActor
private func waitForInstant(_ seconds: Double = 3, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - The contract

final class RepairInstantSendContractTests: XCTestCase {
    func testTheImmediateReplyIsStillSorting() {
        let json = #"{"id":"r1","status":"received","sortStatus":"sorting","lane":null}"#
        let reply = RepairSortReply.decode(Data(json.utf8))
        XCTAssertEqual(reply?.id, "r1")
        XCTAssertEqual(reply?.laneKnown, false)
        XCTAssertEqual(reply?.sortStatus, "sorting")
    }

    func testALaneRouteReplyNamesTheLane() {
        let json = ##"{"id":"r1","status":"received","sortStatus":"sorted","lane":"setting","message":"Changed","setting":{"changes":[{"key":"accent.colour","label":"Main colour (buttons and links)","value":"#E53935"}]}}"##
        let reply = RepairSortReply.decode(Data(json.utf8))
        XCTAssertEqual(reply?.laneKnown, true)
        XCTAssertEqual(reply?.setting, redChange)
        XCTAssertTrue(RepairSortRules.settingDone(reply))
    }

    func testAReplyWithNoLaneIsNotKnownYetAndAnOldStyleLaneIs() {
        XCTAssertEqual(RepairSortReply.decode(Data(#"{"id":"r1","status":"received"}"#.utf8))?.laneKnown, false)
        XCTAssertEqual(RepairSortReply.decode(Data(#"{"id":"r1","lane":"code"}"#.utf8))?.laneKnown, true)
    }

    func testTheUploadAsksTheWorkerToAnswerBeforeItSorts() throws {
        let report = instantReport("c1")
        let request = try RemoteRepairUploadAPI.request(platformOrigin: URL(string: "https://example.invalid")!, report: report, token: "tok")
        let text = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"laneFollow\"\r\n\r\n1\r\n"))
        let plain = try RepairMultipart.body(for: report, boundary: "b")
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("laneFollow"), "only the live upload asks")
    }

    func testLaneAndUndoRequests() {
        let origin = URL(string: "https://example.invalid")!
        let lane = RemoteRepairLaneAPI.laneRequest(platformOrigin: origin, clientReportId: "c1", token: "tok")
        XCTAssertEqual(lane.url?.absoluteString, "https://example.invalid/repairs/lanes/c1")
        XCTAssertEqual(lane.httpMethod, "GET")
        XCTAssertEqual(lane.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let undo = RemoteRepairLaneAPI.undoRequest(platformOrigin: origin, repairId: "srv-1", token: "tok")
        XCTAssertEqual(undo.url?.absoluteString, "https://example.invalid/repairs/srv-1/undo")
        XCTAssertEqual(undo.httpMethod, "POST")
    }

    func testLaneRouteStatusCodes() {
        XCTAssertEqual(RemoteRepairLaneAPI.laneCheck(statusCode: 404, body: Data()), .notFound)
        XCTAssertEqual(RemoteRepairLaneAPI.laneCheck(statusCode: 500, body: Data()), .failed)
        let body = Data(#"{"id":"r1","lane":"code","sortStatus":"sorted"}"#.utf8)
        guard case .reply(let reply) = RemoteRepairLaneAPI.laneCheck(statusCode: 200, body: body) else {
            return XCTFail("a 200 is the lane")
        }
        XCTAssertEqual(reply.lane, .code)
        XCTAssertTrue(reply.laneKnown)
    }
}

// MARK: - The rules

final class RepairLaneRulesTests: XCTestCase {
    func testEachLaneOnTheTag() {
        XCTAssertEqual(RepairLaneRules.step(for: stillSorting("r1")), .keepWatching)
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .code)), .staysEditing)
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .look)), .staysEditing)
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .setting)), .staysEditing, "a setting the Worker sent up to code is an edit")
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .setting, message: "Changed", setting: redChange)), .changed(repairId: "r1"))
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .jessCommand)), .toJess)
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .askBack, question: instantQuestion, status: "asking")), .question(instantQuestion, repairId: "r1"))
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .askBack, status: "dropped")), .gone)
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .notARequest, message: "Say or draw what to change.")), .message("Say or draw what to change."))
        XCTAssertEqual(RepairLaneRules.step(for: laneReply("r1", .shellCant, message: "Water can't do that yet. Sent to Midas.")), .message("Water can't do that yet. Sent to Midas."))
    }

    func testTheTagsWordsAndHowLongEachStays() {
        XCTAssertEqual(RepairTagDisplay.changed.words, "Changed")
        XCTAssertEqual(RepairTagDisplay.undone.words, "Undone")
        XCTAssertEqual(RepairTagDisplay.question.words, "1 question")
        XCTAssertEqual(RepairTagDisplay.laneMessage("Say or draw what to change.").words, "Say or draw what to change.")
        XCTAssertEqual(RepairLaneCopy.undo, "Undo")
        XCTAssertEqual(RepairTagDisplay.changed.leavesAfterSeconds, RepairLaneSpec.changedSeconds)
        XCTAssertGreaterThanOrEqual(RepairLaneSpec.changedSeconds, 4, "time to reach Undo")
        XCTAssertNotNil(RepairTagDisplay.laneMessage("x").leavesAfterSeconds, "a message goes by itself")
        XCTAssertNil(RepairTagDisplay.question.leavesAfterSeconds, "1 question waits for the tap")
    }

    func testAQuestionShowsUntilTheWorkerDropsTheCard() {
        let arrived = Date(timeIntervalSince1970: 1_800_000_000)
        let note = RepairLaneNote(clientReportId: "c1", sidekickId: "reminders", kind: .question(instantQuestion, repairId: "r1"), arrivedAt: arrived)
        XCTAssertEqual(RepairLaneRules.display(for: note, now: arrived.addingTimeInterval(119)), .question)
        XCTAssertNil(RepairLaneRules.display(for: note, now: arrived.addingTimeInterval(120)))
    }
}

// MARK: - The layer closes at once

@MainActor
final class RepairInstantSendSessionTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-instant-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private func makeSession(api: RepairUploadAPI) -> RepairSession {
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: outboxURL))
        return RepairSession(sidekickId: "reminders", snapshot: instantImage(), viewSize: CGSize(width: 20, height: 30), transcriber: InstantQuietTranscriber(), uploader: uploader)
    }

    func testSendClosesBeforeTheWorkerAnswersAndTheTagTakesTheReport() async {
        let api = InstantUploadStub(reply: stillSorting("srv-1"), holdSeconds: 0.5)
        let session = makeSession(api: api)
        var finishedAs: RepairFinish?
        var sent: [RepairReport] = []
        var uploaded: [(String, RepairSortReply?)] = []
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { report, _ in sent.append(report) }
        session.onUploaded = { report, reply, _ in uploaded.append((report.clientReportId, reply)) }
        session.typedText = "Can you change the color to red"
        session.send()
        XCTAssertEqual(finishedAs, .sent, "the layer goes at once, like an edit")
        XCTAssertEqual(sent.count, 1, "the tag takes the report at once")
        XCTAssertEqual(session.askStage, .open, "no waiting for the lane in the layer")
        XCTAssertTrue(uploaded.isEmpty, "the Worker has not answered yet")
        await waitForInstant { !uploaded.isEmpty }
        XCTAssertEqual(uploaded.first?.0, sent.first?.clientReportId)
        XCTAssertEqual(uploaded.first?.1?.laneKnown, false)
    }

    func testEveryLaneClosesAtOnceAndTheReplyGoesToTheTag() async {
        let replies = [
            laneReply("s1", .setting, message: "Changed", setting: redChange),
            laneReply("s2", .jessCommand),
            laneReply("s3", .askBack, question: instantQuestion, status: "asking"),
            laneReply("s4", .notARequest, message: "Say or draw what to change."),
            laneReply("s5", .shellCant, message: "Reminders can't do that yet. Sent to Midas.")
        ]
        for reply in replies {
            let session = makeSession(api: InstantUploadStub(reply: reply))
            var finishedAs: RepairFinish?
            var sentCount = 0
            var jessCount = 0
            var pulled = 0
            var heard: RepairSortReply?
            session.onFinish = { finishedAs = session.finish }
            session.onSent = { _, _ in sentCount += 1 }
            session.onJessCommand = { _, _ in jessCount += 1 }
            session.onSettingChanged = { pulled += 1 }
            session.onUploaded = { _, uploadReply, _ in heard = uploadReply }
            session.typedText = "words"
            session.send()
            XCTAssertEqual(finishedAs, .sent, reply.lane.rawValue)
            XCTAssertEqual(sentCount, 1, reply.lane.rawValue)
            await waitForInstant { heard != nil }
            XCTAssertEqual(heard, reply, "the tag decides, not the closed layer: \(reply.lane.rawValue)")
            XCTAssertEqual(jessCount, 0, "jess hears it from the tag")
            XCTAssertEqual(pulled, 0, "the tag pulls the record")
        }
    }

    func testAnEmptySendIsStillCaughtOnThePhone() {
        let api = InstantUploadStub(reply: stillSorting("srv-1"))
        let session = makeSession(api: api)
        var finishCount = 0
        session.onFinish = { finishCount += 1 }
        session.send()
        XCTAssertFalse(session.canSend)
        XCTAssertNil(session.finish)
        XCTAssertEqual(finishCount, 0)
        XCTAssertTrue(api.reports.isEmpty)
    }

    func testTheReopenedQuestionAnswersTheSameReportAndHandsItBackToTheTag() async {
        let api = InstantUploadStub(reply: nil, answerReply: laneReply("srv-3", .code))
        let session = makeSession(api: api)
        let original = instantReport("phone-3", transcript: "change this")
        var finishedAs: RepairFinish?
        var sent: [RepairReport] = []
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { report, _ in sent.append(report) }
        session.resumeQuestion(instantQuestion, repairId: "srv-3", report: original)
        XCTAssertEqual(session.askStage, .asking(instantQuestion))
        XCTAssertEqual(session.resumedClientReportId, "phone-3")
        XCTAssertEqual(session.pillPlaceholder, "Or say it…")
        session.pick(instantGuesses[1])
        session.send()
        await waitForInstant { finishedAs != nil }
        XCTAssertEqual(api.answers.first?.0, "srv-3", "the answer joins the same report")
        XCTAssertEqual(api.answers.first?.1, .option("bigger"))
        XCTAssertTrue(api.reports.isEmpty, "an answer is not a new report")
        XCTAssertEqual(finishedAs, .sent)
        XCTAssertEqual(sent.map(\.clientReportId), ["phone-3"], "the edit goes back on the tag under its own id")
    }
}

// MARK: - The tag follows the lane

@MainActor
final class RepairInstantSendTagTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "repair-instant-tag-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeCenter(lanes: RepairLaneAPI?, clock: InstantClock) -> RepairCenter {
        let sent = RepairOutbox(directoryURL: folder.appending(path: "sent"))
        return RepairCenter(notices: InstantNoNotices(), resender: InstantNoResend(), sentReports: sent, file: nil, now: clock.read, pollSeconds: 3600, deeperLookPollSeconds: 3600, lanes: lanes, lanePollSeconds: 0.01, laneWatchSeconds: 3)
    }

    func testASettingDoneSaysChangedPullsTheRecordAndUndoPutsItBack() async {
        let lanes = InstantLaneStub()
        lanes.plan("c1", [.notFound, .reply(stillSorting("srv-1")), .reply(laneReply("srv-1", .setting, message: "Changed", setting: redChange))])
        let clock = InstantClock()
        let center = makeCenter(lanes: lanes, clock: clock)
        var pulledFor: [String] = []
        center.onSettingChanged = { sidekickId in pulledFor.append(sidekickId) }
        center.didSend(instantReport("c1"))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false), "Editing while the lane is on its way")
        center.uploaded(clientReportId: "c1", reply: stillSorting("srv-1"), listenMs: 1200)
        await waitForInstant { center.display(for: "reminders", repairModeOn: false) == .changed }
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .changed)
        XCTAssertEqual(pulledFor, ["reminders"], "the page gets the new settings:self")
        XCTAssertTrue(center.state.pending.isEmpty, "no edit on its way")
        XCTAssertNil(center.display(for: "todo", repairModeOn: false), "only on its own Sidekick")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: true), .repairMode)

        await center.undoChange(clientReportId: "c1")
        XCTAssertEqual(lanes.undos, ["srv-1"])
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .undone)
        XCTAssertEqual(pulledFor, ["reminders", "reminders"], "the page gets the old values back")
        center.putAwayShown(for: "reminders")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false))
    }

    func testAnUndoThatDidNotGoThroughKeepsChanged() async {
        let lanes = InstantLaneStub()
        lanes.undoWorks = false
        let center = makeCenter(lanes: lanes, clock: InstantClock())
        center.didSend(instantReport("c1"))
        center.uploaded(clientReportId: "c1", reply: laneReply("srv-1", .setting, message: "Changed", setting: redChange), listenMs: 0)
        await center.undoChange(clientReportId: "c1")
        XCTAssertEqual(lanes.undos, ["srv-1"])
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .changed, "Undo can be tapped again")
    }

    func testACodeLaneStaysEditingAndIsNotAskedAgain() async {
        let lanes = InstantLaneStub()
        lanes.plan("c1", [.reply(laneReply("srv-1", .code))])
        let center = makeCenter(lanes: lanes, clock: InstantClock())
        center.didSend(instantReport("c1"))
        center.uploaded(clientReportId: "c1", reply: stillSorting("srv-1"), listenMs: 0)
        await waitForInstant { !lanes.asked.isEmpty }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
        let askedSoFar = lanes.asked.count
        await center.followLanes()
        XCTAssertEqual(lanes.asked.count, askedSoFar, "an edit's lane is known: the notices say the rest")
    }

    func testJessCommandHandsTheWordsToJessAndTheTagGoes() async {
        let lanes = InstantLaneStub()
        lanes.plan("c1", [.reply(laneReply("srv-1", .jessCommand))])
        let center = makeCenter(lanes: lanes, clock: InstantClock())
        var handed: [(String, Int)] = []
        center.onJessCommand = { words, listenMs in handed.append((words, listenMs)) }
        center.didSend(instantReport("c1", transcript: "remind me to call mum at 6"))
        center.uploaded(clientReportId: "c1", reply: stillSorting("srv-1"), listenMs: 2300)
        await waitForInstant { !handed.isEmpty }
        XCTAssertEqual(handed.first?.0, "remind me to call mum at 6")
        XCTAssertEqual(handed.first?.1, 2300)
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false), "no tag: nothing is being edited")
    }

    func testAskBackSaysOneQuestionAndKeepsTheReportForTheCard() async {
        let lanes = InstantLaneStub()
        lanes.plan("c1", [.reply(laneReply("srv-1", .askBack, question: instantQuestion, status: "asking"))])
        let clock = InstantClock()
        let center = makeCenter(lanes: lanes, clock: clock)
        center.didSend(instantReport("c1", transcript: "change this"))
        center.uploaded(clientReportId: "c1", reply: stillSorting("srv-1"), listenMs: 0)
        await waitForInstant { center.display(for: "reminders", repairModeOn: false) == .question }
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false)?.words, "1 question")
        let waiting = center.waitingQuestion(for: "reminders")
        XCTAssertEqual(waiting?.question, instantQuestion)
        XCTAssertEqual(waiting?.repairId, "srv-1")
        XCTAssertEqual(waiting?.report?.clientReportId, "c1", "the sent report stays for the card")
        XCTAssertEqual(waiting?.report?.transcript, "change this")

        clock.now = clock.now.addingTimeInterval(RepairLaneSpec.questionWindowSeconds)
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false), "the card was dropped: the tag goes")
        XCTAssertNil(center.waitingQuestion(for: "reminders"))
    }

    func testAnsweringTheReopenedQuestionPutsTheQuestionAway() async {
        let lanes = InstantLaneStub()
        let center = makeCenter(lanes: lanes, clock: InstantClock())
        center.didSend(instantReport("c1"))
        center.uploaded(clientReportId: "c1", reply: laneReply("srv-1", .askBack, question: instantQuestion, status: "asking"), listenMs: 0)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question)
        // The answer made it an edit: the layer hands the report back, then the question goes
        center.didSend(instantReport("c1"))
        center.putAwayNote(clientReportId: "c1")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }

    func testNotARequestShowsTheMessageThenGoes() async {
        let lanes = InstantLaneStub()
        lanes.plan("c1", [.reply(laneReply("srv-1", .notARequest, message: "Say or draw what to change."))])
        let center = makeCenter(lanes: lanes, clock: InstantClock())
        center.didSend(instantReport("c1", transcript: "how are you"))
        center.uploaded(clientReportId: "c1", reply: nil, listenMs: 0)
        await waitForInstant { center.display(for: "reminders", repairModeOn: false) != .repairing(count: 1, takingLonger: false) }
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .laneMessage("Say or draw what to change."))
        XCTAssertTrue(center.state.pending.isEmpty, "no job, nothing on its way")
        center.putAwayShown(for: "reminders")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false))
    }

    func testAReplyThatAlreadyNamesTheLaneIsUsedWithoutAsking() {
        let lanes = InstantLaneStub()
        let center = makeCenter(lanes: lanes, clock: InstantClock())
        var pulled = 0
        center.onSettingChanged = { _ in pulled += 1 }
        center.didSend(instantReport("c1"))
        center.uploaded(clientReportId: "c1", reply: laneReply("srv-1", .setting, message: "Changed", setting: redChange), listenMs: 0)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .changed)
        XCTAssertEqual(pulled, 1)
        XCTAssertTrue(lanes.asked.isEmpty)
    }

    func testAReportSentOfflineLearnsItsLaneOnTheNextCheck() async {
        let lanes = InstantLaneStub()
        let center = makeCenter(lanes: lanes, clock: InstantClock())
        center.didSend(instantReport("c1"))
        await center.followLanes()
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false), "not uploaded yet: still Editing")
        lanes.plan("c1", [.reply(laneReply("srv-1", .setting, message: "Changed", setting: redChange))])
        await center.check()
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .changed)
    }

    func testWithoutTheLaneRouteTheTagWaitsForNoticesAsBefore() async {
        let center = makeCenter(lanes: nil, clock: InstantClock())
        center.didSend(instantReport("c1"))
        center.uploaded(clientReportId: "c1", reply: stillSorting("srv-1"), listenMs: 0)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }
}
