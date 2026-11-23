import SwiftUI
import UIKit
import XCTest
@testable import Midas

// An X on the repair tag cancels the repair (founder, 2026-11-22; docs/PRODUCT.md "An X on the
// repair tag cancels the repair", commit f2e047f): "Editing…", "1 question" and a "Couldn't fix"
// result ("Taking a Deeper Look") have an X; "Edit done. Tap to update" has none. Tapping it, the
// tag goes at once: a report still queued on the phone is never sent, one going now is cancelled
// when it lands, one on the server gets POST /repairs/:clientReportId/cancel (retried when
// offline), and a cleared result leaves the saved outcomes.
//
// A question opens by itself (founder, 2026-11-22, "question opens by itself, card in Midas design
// language"): when the lane comes back ask_back while the person is on that Sidekick with the app in
// front, repair mode opens with the card; away or in the background it waits on "1 question"; an
// open layer finishes first. The card takes the repair pill's own surface and type.

// MARK: - Stand-ins

/// The Worker: uploads wait on a gate the test opens; cancels answer `cancelOutcome`.
private final class CancelUploadStub: RepairUploadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedUploads: [String] = []
    private var storedCancels: [String] = []
    private var gateOpen = true
    var uploadOutcome: RepairUploadOutcome = .accepted
    var cancelOutcome: RepairCancelOutcome = .done

    var sortsReports: Bool {
        true
    }

    var uploads: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedUploads
    }

    var cancels: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedCancels
    }

    func holdUploads() {
        setGate(false)
    }

    func releaseUploads() {
        setGate(true)
    }

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        let sorted = try await uploadSorted(report)
        return sorted.outcome
    }

    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        recordUpload(report.clientReportId)
        while !isGateOpen() {
            try await Task.sleep(for: .milliseconds(10))
        }
        let reply = RepairSortReply(id: "srv-\(report.clientReportId)", lane: .code, question: nil, message: nil, laneKnown: false, sortStatus: "sorting")
        return RepairSortedUpload(outcome: uploadOutcome, reply: reply)
    }

    func cancel(clientReportId: String) async -> RepairCancelOutcome {
        recordCancel(clientReportId)
        return currentCancelOutcome()
    }

    private func setGate(_ open: Bool) {
        lock.lock()
        gateOpen = open
        lock.unlock()
    }

    private func isGateOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gateOpen
    }

    private func recordUpload(_ id: String) {
        lock.lock()
        storedUploads.append(id)
        lock.unlock()
    }

    private func recordCancel(_ id: String) {
        lock.lock()
        storedCancels.append(id)
        lock.unlock()
    }

    private func currentCancelOutcome() -> RepairCancelOutcome {
        lock.lock()
        defer { lock.unlock() }
        return cancelOutcome
    }
}

/// The uploader as the center sees it: records each cancel.
@MainActor
private final class RecordingCanceller: RepairCancelling {
    var cancelled: [String] = []

    func cancel(clientReportId: String) async {
        cancelled.append(clientReportId)
    }
}

/// Notices the test fills.
private final class CancelNotices: JessRepairNoticesAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [JessRepairNotice] = []

    func add(_ notice: JessRepairNotice) {
        lock.lock()
        waiting.append(notice)
        lock.unlock()
    }

    func notices() async -> [JessRepairNotice]? {
        currentNotices()
    }

    func markSeen(id: String) async {
        removeNotice(id)
    }

    private func currentNotices() -> [JessRepairNotice] {
        lock.lock()
        defer { lock.unlock() }
        return waiting
    }

    private func removeNotice(_ id: String) {
        lock.lock()
        waiting.removeAll { $0.id == id }
        lock.unlock()
    }
}

/// The lane route: every report answers `reply`, or not found when there is none.
private final class CancelLaneStub: RepairLaneAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String: RepairSortReply] = [:]

    func answer(_ clientReportId: String, with reply: RepairSortReply) {
        lock.lock()
        replies[clientReportId] = reply
        lock.unlock()
    }

    func lane(clientReportId: String) async -> RepairLaneCheck {
        guard let reply = storedReply(clientReportId) else {
            return .notFound
        }
        return .reply(reply)
    }

    func undo(repairId: String) async -> Bool {
        true
    }

    private func storedReply(_ clientReportId: String) -> RepairSortReply? {
        lock.lock()
        defer { lock.unlock() }
        return replies[clientReportId]
    }
}

@MainActor
private final class CancelNoResend: RepairResending {
    func send(_ report: RepairReport) async {}
}

/// Whether the app is in front, as the test sets it.
@MainActor
private final class CancelAppState {
    var active = true

    func isActive() -> Bool {
        active
    }
}

private let cancelGuesses = [
    RepairQuestionOption(id: "other_colour", label: "Other colour", icon: "paintpalette"),
    RepairQuestionOption(id: "bigger", label: "Bigger", icon: "arrow.up.left.and.arrow.down.right"),
    RepairQuestionOption(id: "remove", label: "Remove", icon: "eye.slash")
]
private let cancelQuestion = RepairQuestion(text: "What should it be?", options: cancelGuesses)

private func askBackReply(_ id: String) -> RepairSortReply {
    RepairSortReply(id: id, lane: .askBack, question: cancelQuestion, message: nil, laneKnown: true, sortStatus: "asking")
}

private func cancelReport(_ clientReportId: String, sidekickId: String = "reminders") -> RepairReport {
    RepairReport(
        clientReportId: clientReportId,
        sidekickId: sidekickId,
        kind: "change",
        bundleVersion: "v1",
        bundleScope: "base",
        transcript: "make it blue",
        spokenText: "make it blue",
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

/// Waits on the main actor until the condition holds, at most `seconds`.
@MainActor
private func waitForCancel(_ seconds: Double = 3, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Which tags have the X

@MainActor
final class RepairCancelTagTests: XCTestCase {
    func testTheXIsOnEditingOneQuestionAndCouldntFixOnly() {
        XCTAssertTrue(RepairTagDisplay.repairing(count: 1, takingLonger: false).cancellable)
        XCTAssertTrue(RepairTagDisplay.repairing(count: 2, takingLonger: true).cancellable, "Taking longer is still an edit on its way")
        XCTAssertTrue(RepairTagDisplay.question.cancellable)
        XCTAssertTrue(RepairTagDisplay.couldntFix.cancellable)
        XCTAssertFalse(RepairTagDisplay.fixed(onPage: true, summary: nil).cancellable, "Edit done. Tap to update stays as it is")
        XCTAssertFalse(RepairTagDisplay.fixed(onPage: false, summary: nil).cancellable)
        XCTAssertFalse(RepairTagDisplay.repairMode.cancellable)
        XCTAssertFalse(RepairTagDisplay.alreadyThere(summary: nil).cancellable)
        XCTAssertFalse(RepairTagDisplay.changed.cancellable)
        XCTAssertFalse(RepairTagDisplay.undone.cancellable)
        XCTAssertFalse(RepairTagDisplay.laneMessage("Say or draw what to change.").cancellable)
    }

    func testTheTagShowsTheXOnlyWhenItCanCancel() {
        XCTAssertTrue(RepairTagView(display: .repairing(count: 1, takingLonger: false), onTap: Self.ignoreTap, onCancel: Self.ignoreTap).showsCancel)
        XCTAssertFalse(RepairTagView(display: .repairing(count: 1, takingLonger: false), onTap: Self.ignoreTap).showsCancel, "no X while a repair layer is open")
        XCTAssertFalse(RepairTagView(display: .fixed(onPage: true, summary: nil), onTap: Self.ignoreTap, onCancel: Self.ignoreTap).showsCancel)
    }

    func testTheXIsSmallButTappedThroughAFullSquareAndSaysCancel() {
        XCTAssertGreaterThanOrEqual(RepairTagCancelSpec.hitSize, 44)
        XCTAssertLessThan(RepairTagCancelSpec.circleSize, RepairTagSpec.height, "drawn inside the 28 pt tag")
        XCTAssertEqual(RepairTagCopy.cancel, "Cancel")
    }

    func testTheTagWithTheXDrawsInLightAndDark() {
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            let withX = RepairTagView(display: .repairing(count: 1, takingLonger: false), onTap: Self.ignoreTap, onCancel: Self.ignoreTap).environment(\.colorScheme, scheme)
            let withoutX = RepairTagView(display: .repairing(count: 1, takingLonger: false), onTap: Self.ignoreTap).environment(\.colorScheme, scheme)
            let widthWith = Self.renderedWidth(withX)
            let widthWithout = Self.renderedWidth(withoutX)
            XCTAssertGreaterThan(widthWith, widthWithout, "the X takes room on the tag (\(scheme))")
            XCTAssertLessThan(widthWith - widthWithout, RepairTagCancelSpec.hitSize, "drawn small (\(scheme))")
        }
    }

    private static func renderedWidth<Content: View>(_ view: Content) -> CGFloat {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = 1
        return renderer.uiImage?.size.width ?? 0
    }

    private static func ignoreTap() {}
}

// MARK: - The uploader

@MainActor
final class RepairCancelUploaderTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "repair-cancel-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private var outbox: RepairOutbox {
        RepairOutbox(directoryURL: folder.appending(path: "outbox"))
    }

    private var cancelFile: URL {
        folder.appending(path: "repair-cancels.json")
    }

    func testAReportStillQueuedOnThePhoneIsRemovedAndNeverSent() async throws {
        let api = CancelUploadStub()
        let uploader = RepairUploader(api: api, outbox: outbox, cancelQueue: RepairCancelQueue(fileURL: cancelFile))
        try outbox.enqueue(cancelReport("c1"))
        XCTAssertTrue(outbox.contains(clientReportId: "c1"))
        await uploader.cancel(clientReportId: "c1")
        XCTAssertFalse(outbox.contains(clientReportId: "c1"), "out of the queue")
        await uploader.retryQueued()
        XCTAssertTrue(api.uploads.isEmpty, "never sent")
        XCTAssertTrue(api.cancels.isEmpty, "the server never had it")
    }

    func testAReportGoingNowIsCancelledTheMomentItLands() async {
        let api = CancelUploadStub()
        api.holdUploads()
        let uploader = RepairUploader(api: api, outbox: outbox)
        var reply: RepairSortReply? = RepairSortReply(id: "x", lane: .code, question: nil, message: nil)
        var finished = false
        let report = cancelReport("c2")
        Task { @MainActor in
            reply = await uploader.sendSorted(report)
            finished = true
        }
        await waitForCancel { !api.uploads.isEmpty }
        await uploader.cancel(clientReportId: "c2")
        XCTAssertTrue(api.cancels.isEmpty, "not on the server yet")
        api.releaseUploads()
        await waitForCancel { finished }
        XCTAssertEqual(api.cancels, ["c2"], "cancelled once it landed")
        XCTAssertNil(reply, "the tag hears nothing more of it")
        XCTAssertFalse(outbox.contains(clientReportId: "c2"))
    }

    func testASentReportGetsTheCancelRouteAndOfflineItIsRetried() async {
        let api = CancelUploadStub()
        let uploader = RepairUploader(api: api, outbox: outbox, cancelQueue: RepairCancelQueue(fileURL: cancelFile))
        _ = await uploader.sendSorted(cancelReport("c3"))
        XCTAssertFalse(outbox.contains(clientReportId: "c3"), "uploaded")
        api.cancelOutcome = .retryLater
        await uploader.cancel(clientReportId: "c3")
        XCTAssertEqual(api.cancels, ["c3"])
        XCTAssertEqual(uploader.queuedCancels, ["c3"], "kept for later")

        // A relaunch still knows it
        let relaunched = RepairUploader(api: api, outbox: outbox, cancelQueue: RepairCancelQueue(fileURL: cancelFile))
        XCTAssertEqual(relaunched.queuedCancels, ["c3"])
        api.cancelOutcome = .done
        await relaunched.retryQueued()
        XCTAssertEqual(api.cancels, ["c3", "c3"], "sent again when back")
        XCTAssertTrue(relaunched.queuedCancels.isEmpty)
        XCTAssertTrue(RepairCancelQueue(fileURL: cancelFile).load().isEmpty)
    }

    func testAReportTriedOfflineIsRemovedAndTheServerIsToldInCaseItArrived() async {
        let api = CancelUploadStub()
        api.uploadOutcome = .retryLater
        let uploader = RepairUploader(api: api, outbox: outbox)
        _ = await uploader.sendSorted(cancelReport("c4"))
        XCTAssertTrue(outbox.contains(clientReportId: "c4"), "still queued")
        await uploader.cancel(clientReportId: "c4")
        XCTAssertFalse(outbox.contains(clientReportId: "c4"))
        XCTAssertEqual(api.cancels, ["c4"], "a reply may have been lost: the server is told")
        api.uploadOutcome = .accepted
        await uploader.retryQueued()
        XCTAssertEqual(api.uploads, ["c4"], "not uploaded again")
    }

    func testTheCancelRequestAndItsAnswers() {
        let request = RemoteRepairUploadAPI.cancelRequest(platformOrigin: URL(string: "https://example.invalid")!, clientReportId: "c1", token: "tok")
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/repairs/c1/cancel")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(RemoteRepairUploadAPI.cancelOutcome(statusCode: 200), .done)
        XCTAssertEqual(RemoteRepairUploadAPI.cancelOutcome(statusCode: 404), .done, "the server never got it")
        XCTAssertEqual(RemoteRepairUploadAPI.cancelOutcome(statusCode: 500), .retryLater)
        XCTAssertEqual(RemoteRepairUploadAPI.cancelOutcome(statusCode: 401), .retryLater)
        XCTAssertEqual(RemoteRepairUploadAPI.cancelOutcome(statusCode: 0), .retryLater, "offline")
    }
}

// MARK: - The tag goes at once

@MainActor
final class RepairCancelCenterTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "repair-cancel-center-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private var sent: RepairOutbox {
        RepairOutbox(directoryURL: folder.appending(path: "sent"))
    }

    private var centerFile: RepairCenterFile {
        RepairCenterFile(fileURL: folder.appending(path: "center.json"))
    }

    private func makeCenter(canceller: RepairCancelling?, notices: JessRepairNoticesAPI = CancelNotices(), lanes: RepairLaneAPI? = nil, appState: CancelAppState = CancelAppState()) -> RepairCenter {
        RepairCenter(notices: notices, resender: CancelNoResend(), sentReports: sent, file: centerFile, pollSeconds: 3600, deeperLookPollSeconds: 3600, lanes: lanes, lanePollSeconds: 0.01, laneWatchSeconds: 2, canceller: canceller, isAppActive: appState.isActive)
    }

    func testXOnEditingCancelsEveryEditOnItsWayThereAndTheTagGoes() async {
        let canceller = RecordingCanceller()
        let center = makeCenter(canceller: canceller)
        center.didSend(cancelReport("c1"))
        center.didSend(cancelReport("c2"))
        center.didSend(cancelReport("other", sidekickId: "todo"))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 2, takingLonger: false))
        let task = center.cancelShown(for: "reminders")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false), "the tag goes at once")
        XCTAssertFalse(sent.contains(clientReportId: "c1"))
        XCTAssertEqual(center.display(for: "todo", repairModeOn: false), .repairing(count: 1, takingLonger: false), "other Sidekicks keep theirs")
        await task?.value
        XCTAssertEqual(canceller.cancelled, ["c1", "c2"])
        XCTAssertEqual(centerFile.load().pending.map(\.clientReportId), ["other"], "saved without them")
    }

    func testXOnOneQuestionCancelsThatReport() async {
        let canceller = RecordingCanceller()
        let center = makeCenter(canceller: canceller)
        center.didSend(cancelReport("q1"))
        center.uploaded(clientReportId: "q1", reply: askBackReply("srv-q1"), listenMs: 0)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question)
        let task = center.cancelShown(for: "reminders")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false))
        XCTAssertNil(center.waitingQuestion(for: "reminders"))
        XCTAssertFalse(sent.contains(clientReportId: "q1"), "the kept report goes with it")
        await task?.value
        XCTAssertEqual(canceller.cancelled, ["q1"])
    }

    func testXOnCouldntFixClearsTheSavedResultWithoutAskingTheServer() async {
        let canceller = RecordingCanceller()
        let notices = CancelNotices()
        let center = makeCenter(canceller: canceller, notices: notices)
        center.didSend(cancelReport("d1"))
        notices.add(JessRepairNotice(id: "n1", reportId: "srv-d1", text: "Check back in some time.", kind: .couldntFix, summary: nil, clientReportId: "d1"))
        await center.check()
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .couldntFix)
        XCTAssertEqual(centerFile.load().outcomes.count, 1)
        let task = center.cancelShown(for: "reminders")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false))
        XCTAssertTrue(center.state.outcomes.isEmpty)
        XCTAssertTrue(centerFile.load().outcomes.isEmpty, "removed from the saved outcomes")
        XCTAssertFalse(sent.contains(clientReportId: "d1"))
        await task?.value
        XCTAssertTrue(canceller.cancelled.isEmpty, "the edit already ended on the server")
    }

    func testEditDoneTapToUpdateHasNoXAndStays() async {
        let canceller = RecordingCanceller()
        let notices = CancelNotices()
        let center = makeCenter(canceller: canceller, notices: notices)
        center.sidekickOpened("reminders")
        center.didSend(cancelReport("f1"))
        notices.add(JessRepairNotice(id: "n2", reportId: "srv-f1", text: "The update you requested is done.", kind: .fixed, summary: nil, clientReportId: "f1"))
        await center.check()
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false)?.words, "Edit done. Tap to update")
        XCTAssertNil(center.cancelShown(for: "reminders"))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false)?.words, "Edit done. Tap to update")
        XCTAssertTrue(canceller.cancelled.isEmpty)
    }

    func testTheCenterHandsTheCancelToTheRealUploader() async {
        let api = CancelUploadStub()
        let uploader = RepairUploader(api: api, outbox: RepairOutbox(directoryURL: folder.appending(path: "outbox")))
        let center = makeCenter(canceller: uploader)
        let report = cancelReport("u1")
        center.didSend(report)
        _ = await uploader.sendSorted(report)
        let task = center.cancelShown(for: "reminders")
        await task?.value
        XCTAssertEqual(api.cancels, ["u1"])
    }
}

// MARK: - A question opens by itself

@MainActor
final class RepairQuestionOpensByItselfTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "repair-question-open-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeCenter(appState: CancelAppState, lanes: RepairLaneAPI? = nil) -> RepairCenter {
        let sent = RepairOutbox(directoryURL: folder.appending(path: "sent"))
        return RepairCenter(notices: CancelNotices(), resender: CancelNoResend(), sentReports: sent, file: nil, pollSeconds: 3600, deeperLookPollSeconds: 3600, lanes: lanes, lanePollSeconds: 0.01, laneWatchSeconds: 2, canceller: RecordingCanceller(), isAppActive: appState.isActive)
    }

    func testOnTheSidekickTheQuestionOpensOnceWithItsCard() {
        let center = makeCenter(appState: CancelAppState())
        center.sidekickOpened("reminders")
        center.didSend(cancelReport("q1"))
        center.uploaded(clientReportId: "q1", reply: askBackReply("srv-q1"), listenMs: 0)
        XCTAssertEqual(center.questionsToOpen, ["q1"])
        let opened = center.questionToOpen(for: "reminders", layerOpen: false)
        XCTAssertEqual(opened?.question, cancelQuestion)
        XCTAssertEqual(opened?.repairId, "srv-q1")
        XCTAssertEqual(opened?.report?.clientReportId, "q1", "the card's answer joins the same report")
        XCTAssertNil(center.questionToOpen(for: "reminders", layerOpen: false), "opens once")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question, "the tag still has it if the layer is cancelled")
    }

    func testTheLaneFollowedFromTheServerOpensItToo() async {
        let lanes = CancelLaneStub()
        lanes.answer("q2", with: askBackReply("srv-q2"))
        let center = makeCenter(appState: CancelAppState(), lanes: lanes)
        center.sidekickOpened("reminders")
        center.didSend(cancelReport("q2"))
        center.uploaded(clientReportId: "q2", reply: nil, listenMs: 0)
        await waitForCancel { !center.questionsToOpen.isEmpty }
        XCTAssertNotNil(center.questionToOpen(for: "reminders", layerOpen: false))
    }

    func testAnOpenLayerFinishesFirst() {
        let center = makeCenter(appState: CancelAppState())
        center.sidekickOpened("reminders")
        center.didSend(cancelReport("q3"))
        center.uploaded(clientReportId: "q3", reply: askBackReply("srv-q3"), listenMs: 0)
        XCTAssertNil(center.questionToOpen(for: "reminders", layerOpen: true), "mid-repair on another request: wait")
        XCTAssertEqual(center.questionsToOpen, ["q3"], "still waiting to open")
        XCTAssertNotNil(center.questionToOpen(for: "reminders", layerOpen: false), "opens once that layer closed")
    }

    func testAwayFromTheSidekickItWaitsOnTheTag() {
        let center = makeCenter(appState: CancelAppState())
        center.sidekickOpened("todo")
        center.didSend(cancelReport("q4"))
        center.uploaded(clientReportId: "q4", reply: askBackReply("srv-q4"), listenMs: 0)
        XCTAssertTrue(center.questionsToOpen.isEmpty)
        center.sidekickClosed("todo")
        center.sidekickOpened("reminders")
        XCTAssertNil(center.questionToOpen(for: "reminders", layerOpen: false), "coming back later does not open it")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question, "the 1 question tag waits for a tap")
        XCTAssertNotNil(center.waitingQuestion(for: "reminders"), "a tap opens it")
    }

    func testInTheBackgroundItWaitsOnTheTag() {
        let appState = CancelAppState()
        appState.active = false
        let center = makeCenter(appState: appState)
        center.sidekickOpened("reminders")
        center.didSend(cancelReport("q5"))
        center.uploaded(clientReportId: "q5", reply: askBackReply("srv-q5"), listenMs: 0)
        appState.active = true
        XCTAssertNil(center.questionToOpen(for: "reminders", layerOpen: false))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .question)
    }

    func testLeavingOrGoingToTheBackgroundBeforeItOpensLeavesItOnTheTag() {
        let center = makeCenter(appState: CancelAppState())
        center.sidekickOpened("reminders")
        center.didSend(cancelReport("q6"))
        center.uploaded(clientReportId: "q6", reply: askBackReply("srv-q6"), listenMs: 0)
        center.sidekickClosed("reminders")
        center.sidekickOpened("reminders")
        XCTAssertNil(center.questionToOpen(for: "reminders", layerOpen: false), "left before it could open")

        center.didSend(cancelReport("q7"))
        center.uploaded(clientReportId: "q7", reply: askBackReply("srv-q7"), listenMs: 0)
        XCTAssertEqual(center.questionsToOpen, ["q7"])
        center.appWentToBackground()
        XCTAssertNil(center.questionToOpen(for: "reminders", layerOpen: false))
    }

    func testTheXStopsAQuestionFromOpening() {
        let center = makeCenter(appState: CancelAppState())
        center.sidekickOpened("reminders")
        center.didSend(cancelReport("q8"))
        center.uploaded(clientReportId: "q8", reply: askBackReply("srv-q8"), listenMs: 0)
        center.cancelShown(for: "reminders")
        XCTAssertTrue(center.questionsToOpen.isEmpty)
        XCTAssertNil(center.questionToOpen(for: "reminders", layerOpen: false))
    }

    func testRepairModeOpensWithoutASwipeTheWayTheSwipeOpensIt() {
        let chrome = RepairChrome()
        var taps = 0
        chrome.lockHaptic = { taps += 1 }
        chrome.reduceMotion = { false }
        chrome.traceInWithoutSwipe()
        XCTAssertEqual(chrome.rimPhase, .tracing, "the rim draws in from the top")
        XCTAssertTrue(chrome.isRimShown)
        XCTAssertFalse(chrome.repairModeOn)
        chrome.swipeLocked()
        XCTAssertEqual(chrome.rimPhase, .on)
        XCTAssertTrue(chrome.repairModeOn)
        XCTAssertEqual(taps, 1, "the same tap of the phone as the swipe's lock")
        XCTAssertGreaterThan(RepairRimSpec.traceWithoutSwipe, 0)
    }
}

// MARK: - The card in Midas's design language

final class RepairQuestionCardLookTests: XCTestCase {
    func testTheCardTakesThePillsSurfaceAndType() {
        XCTAssertEqual(RepairQuestionCardSpec.cornerRadius, RepairPillSpec.cornerRadius)
        XCTAssertEqual(RepairQuestionCardSpec.questionSize, RepairPillSpec.fontSize)
        XCTAssertEqual(RepairQuestionCardSpec.backgroundOpacity, 1, "solid paper, as the pill")
        XCTAssertEqual(RepairQuestionCardSpec.shadowRadius, 15)
        XCTAssertEqual(RepairQuestionCardSpec.shadowY, 10)
    }

    func testGuessesAreTheRaisedSurfaceAndThePickedOneIsInk() {
        for tokens in [RepairTokens.light, RepairTokens.dark] {
            let plain = RepairQuestionCardSpec.optionColors(picked: false, tokens: tokens)
            XCTAssertEqual(plain.fill, tokens.paper2)
            XCTAssertEqual(plain.words, tokens.ink)
            let picked = RepairQuestionCardSpec.optionColors(picked: true, tokens: tokens)
            XCTAssertEqual(picked.fill, tokens.ink)
            XCTAssertEqual(picked.words, tokens.paper)
            XCTAssertNotEqual(picked.fill, RepairVolt.color, "no Volt on the card")
        }
    }
}
