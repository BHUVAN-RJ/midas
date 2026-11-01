import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import Midas

// The repair UX upgrade (founder, 2026-10-23, docs/briefs/repair-ux-upgrade.md and
// docs/mockups/repair-feedback-2026-10-23.html section 1): the V1 rim, the Repair tag on the
// Sidekick being repaired only, results with their own words, the update out of the tag (U4), the
// B3 pill with jess's orb, Volt strokes, and no red recording dot on Send.

// MARK: - Fakes

/// Notices the test hands out; records which were marked seen.
private final class FakeNotices: JessRepairNoticesAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [JessRepairNotice] = []
    private var seenIds: [String] = []
    private var askedCount = 0

    func give(_ notices: [JessRepairNotice]) {
        lock.lock()
        queued = notices
        lock.unlock()
    }

    var seen: [String] {
        lock.lock()
        defer { lock.unlock() }
        return seenIds
    }

    var asked: Int {
        lock.lock()
        defer { lock.unlock() }
        return askedCount
    }

    func notices() async -> [JessRepairNotice]? {
        takeNotices()
    }

    func markSeen(id: String) async {
        recordSeen(id)
    }

    // NSLock is not allowed inside async functions under Swift 6, so the locked parts are here.
    private func takeNotices() -> [JessRepairNotice] {
        lock.lock()
        defer { lock.unlock() }
        askedCount += 1
        let seenNow = Set(seenIds)
        return queued.filter { !seenNow.contains($0.id) }
    }

    private func recordSeen(_ id: String) {
        lock.lock()
        seenIds.append(id)
        lock.unlock()
    }
}

@MainActor
private final class FakeResender: RepairResending {
    private(set) var sent: [RepairReport] = []

    func send(_ report: RepairReport) async {
        sent.append(report)
    }
}

/// Starts listening at once, so the layer shows jess listening.
@MainActor
private final class ListeningTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {}

    func stop() {}
}

@MainActor
private final class DeafTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        throw RepairSpeechError.notAuthorized
    }

    func stop() {}
}

private struct NoUpload: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .retryLater
    }
}

private func temporaryFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
}

private func solidImage(size: CGSize, white: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { context in
        UIColor(white: white, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

private func makeReport(clientReportId: String, sidekickId: String = "reminders", transcript: String = "add every 2 hrs") -> RepairReport {
    RepairReport(
        clientReportId: clientReportId,
        sidekickId: sidekickId,
        kind: RepairReport.unknownKind,
        bundleVersion: "v7",
        bundleScope: "user",
        transcript: transcript,
        spokenText: transcript,
        typedText: "",
        words: [],
        strokesJSON: Data("[]".utf8),
        screenshotJPEG: Data([0xFF, 0xD8]),
        drawingPNG: solidImage(size: CGSize(width: 4, height: 4), white: 1).pngData() ?? Data(),
        device: "iPhone",
        iosVersion: "27.0",
        appVersion: "1",
        appBuild: "1"
    )
}

private func notice(_ id: String, client: String?, kind: RepairResultKind?, summary: String? = nil) -> JessRepairNotice {
    JessRepairNotice(id: id, reportId: "server-\(id)", text: "words", kind: kind, summary: summary, clientReportId: client)
}

/// An image's pixels, decoded once.
private struct DecodedPixels {
    private let bytes: [UInt8]
    let width: Int
    let height: Int

    init(_ image: UIImage) {
        let cgImage = image.cgImage!
        width = cgImage.width
        height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = CGContext(data: &buffer, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        bytes = buffer
    }

    func at(x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)
        let offset = (clampedY * width + clampedX) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}

/// RGBA of one pixel.
private func pixel(in image: UIImage, x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
    DecodedPixels(image).at(x: x, y: y)
}

// MARK: - The tag's words and rules

final class RepairTagRulesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func pending(_ id: String, sidekickId: String = "reminders", minutesAgo: Double = 0) -> RepairPending {
        RepairPending(clientReportId: id, sidekickId: sidekickId, transcript: "t", sentAt: start.addingTimeInterval(-minutesAgo * 60))
    }

    private func outcome(_ id: String, kind: RepairResultKind, whileOpen: Bool = true, sidekickId: String = "reminders") -> RepairOutcome {
        RepairOutcome(clientReportId: id, sidekickId: sidekickId, kind: kind, summary: "Added every 2 hrs.", arrivedAt: start, arrivedWhileOpen: whileOpen)
    }

    func testTheWordsAreTheFoundersAndNeverSayFailed() {
        XCTAssertEqual(RepairTagCopy.repairMode, "Edit")
        XCTAssertEqual(RepairTagCopy.fixedOnPage, "Edit done. Tap to update")
        XCTAssertEqual(RepairTagCopy.alreadyThere, "Already There")
        XCTAssertEqual(RepairTagCopy.couldntFix, "Check back in some time.")
        XCTAssertEqual(RepairTagCopy.tryAgain, "Try Again")
        XCTAssertEqual(RepairTagCopy.takingLonger, "Taking longer")
        XCTAssertEqual(RepairTagCopy.repairing(count: 1), "Editing")
        XCTAssertEqual(RepairTagCopy.repairing(count: 2), "Editing 2")
        let every = [RepairTagDisplay.repairMode, .repairing(count: 1, takingLonger: false), .fixed(onPage: true, summary: nil), .fixed(onPage: false, summary: nil), .alreadyThere(summary: nil), .couldntFix]
        for display in every {
            XCTAssertFalse(display.words.lowercased().contains("fail"), display.words)
        }
    }

    func testRepairModeWinsThenAResultThenRepairing() {
        var state = RepairCenterState(pending: [pending("a")], outcomes: [])
        XCTAssertEqual(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: true, now: start), .repairMode)
        XCTAssertEqual(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: false, now: start), .repairing(count: 1, takingLonger: false))
        state.outcomes = [outcome("b", kind: .alreadyThere)]
        XCTAssertEqual(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: false, now: start), .alreadyThere(summary: "Added every 2 hrs."))
    }

    func testTheTagIsOnlyOnTheSidekickBeingRepaired() {
        let state = RepairCenterState(pending: [pending("a", sidekickId: "reminders")], outcomes: [outcome("b", kind: .couldntFix, sidekickId: "reminders")])
        XCTAssertNil(RepairTagRules.display(state: state, sidekickId: "groceries", repairModeOn: false, now: start))
        XCTAssertNotNil(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: false, now: start))
    }

    func testASecondRepairWaitsAndTenMinutesIsTakingLonger() {
        let state = RepairCenterState(pending: [pending("a", minutesAgo: 10), pending("b", minutesAgo: 1)], outcomes: [])
        let display = RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: false, now: start)
        XCTAssertEqual(display, .repairing(count: 2, takingLonger: true))
        XCTAssertEqual(display?.words, "Taking longer")
        let early = RepairCenterState(pending: [pending("a", minutesAgo: 9.9), pending("b")], outcomes: [])
        XCTAssertEqual(RepairTagRules.display(state: early, sidekickId: "reminders", repairModeOn: false, now: start)?.words, "Editing 2")
    }

    func testAFixSaysTapToUpdateOnlyWhenItLandedOnThePage() {
        let onPage = RepairCenterState(pending: [], outcomes: [outcome("a", kind: .fixed, whileOpen: true)])
        let away = RepairCenterState(pending: [], outcomes: [outcome("a", kind: .fixed, whileOpen: false)])
        XCTAssertEqual(RepairTagRules.display(state: onPage, sidekickId: "reminders", repairModeOn: false, now: start)?.words, "Edit done. Tap to update")
        XCTAssertEqual(RepairTagRules.display(state: away, sidekickId: "reminders", repairModeOn: false, now: start)?.words, "Fixed")
    }

    func testOnlyAlreadyThereAndAFixFromAwayLeaveOnTheirOwn() {
        XCTAssertTrue(RepairTagDisplay.alreadyThere(summary: nil).leavesOnItsOwn)
        XCTAssertTrue(RepairTagDisplay.fixed(onPage: false, summary: nil).leavesOnItsOwn)
        XCTAssertFalse(RepairTagDisplay.fixed(onPage: true, summary: nil).leavesOnItsOwn, "Tap to update waits for the tap")
        XCTAssertFalse(RepairTagDisplay.couldntFix.leavesOnItsOwn, "Check back in some time. stays until Close")
        XCTAssertFalse(RepairTagDisplay.repairing(count: 1, takingLonger: false).leavesOnItsOwn)
        XCTAssertEqual(RepairTagDisplay.alreadyThere(summary: nil).leavesAfterSeconds, 2.4)
        XCTAssertEqual(RepairTagDisplay.fixed(onPage: false, summary: nil).leavesAfterSeconds, 1, "Fixed shows for 1 s on return")
    }

    func testTheSummaryIsOneLine() {
        XCTAssertEqual(RepairTagRules.oneLine("Added every 2 hrs.\nChanged index.html line 40."), "Added every 2 hrs.")
        XCTAssertNil(RepairTagRules.oneLine("  \n"))
        XCTAssertNil(RepairTagRules.oneLine(nil))
        XCTAssertEqual(RepairTagRules.oneLine(String(repeating: "a", count: 300))?.count, 200)
    }
}

// MARK: - Repair state per Sidekick

@MainActor
final class RepairCenterTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        super.tearDown()
    }

    private func makeCenter(notices: FakeNotices, resender: FakeResender = FakeResender(), stateFile: URL? = nil, sentFolder: URL? = nil) -> RepairCenter {
        let sent = sentFolder ?? temporaryFolder("repairs-sent")
        folders.append(sent)
        let file = stateFile.map(RepairCenterFile.init(fileURL:))
        return RepairCenter(notices: notices, resender: resender, sentReports: RepairOutbox(directoryURL: sent), file: file, pollSeconds: 3600)
    }

    func testSendShowsRepairingOnThatSidekickOnly() {
        let center = makeCenter(notices: FakeNotices())
        center.didSend(makeReport(clientReportId: "c1"))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
        XCTAssertNil(center.display(for: "groceries", repairModeOn: false))
        XCTAssertEqual(center.latestPending(for: "reminders")?.transcript, "add every 2 hrs")
        XCTAssertNotNil(center.sentDrawing(clientReportId: "c1"), "what was sent shows the circled screenshot")
    }

    func testNothingToChangeIsAlreadyThereWithItsSummaryAndIsMarkedSeen() async {
        let notices = FakeNotices()
        let center = makeCenter(notices: notices)
        center.sidekickOpened("reminders")
        center.didSend(makeReport(clientReportId: "c1"))
        notices.give([notice("n1", client: "c1", kind: .alreadyThere, summary: "The every 2 hrs option is already there.\nmore"), notice("n2", client: nil, kind: .fixed)])

        await center.check()

        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .alreadyThere(summary: "The every 2 hrs option is already there."))
        XCTAssertEqual(notices.seen, ["n1"], "a notice for a repair jess sent is left for jess")
        XCTAssertTrue(center.state.pending.isEmpty)
    }

    func testAFixWhileOnThePageWaitsForTheTapAndLeavingPutsItAway() async {
        let notices = FakeNotices()
        let center = makeCenter(notices: notices)
        var refreshedAway: [String] = []
        center.onFixedAway = { refreshedAway.append($0) }
        center.sidekickOpened("reminders")
        center.didSend(makeReport(clientReportId: "c1"))
        notices.give([notice("n1", client: "c1", kind: .fixed, summary: "Added it.")])

        await center.check()

        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false)?.words, "Edit done. Tap to update")
        XCTAssertEqual(refreshedAway, [], "on the page the user updates it with the tap")
        center.sidekickClosed("reminders")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false), "the next open loads the new page; nothing to update")
    }

    func testAFixWhileAwayRefreshesInTheBackgroundAndShowsOnReturn() async {
        let notices = FakeNotices()
        let center = makeCenter(notices: notices)
        var refreshedAway: [String] = []
        center.onFixedAway = { refreshedAway.append($0) }
        center.sidekickOpened("reminders")
        center.didSend(makeReport(clientReportId: "c1"))
        center.sidekickClosed("reminders")
        notices.give([notice("n1", client: "c1", kind: .fixed)])

        await center.check()

        XCTAssertEqual(refreshedAway, ["reminders"])
        center.sidekickOpened("reminders")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .fixed(onPage: false, summary: nil))
    }

    func testCouldntFixStaysUntilTryAgainWhichResendsTheSameReportUnderANewId() async {
        let notices = FakeNotices()
        let resender = FakeResender()
        let center = makeCenter(notices: notices, resender: resender)
        center.sidekickOpened("reminders")
        center.didSend(makeReport(clientReportId: "c1", transcript: "make the circles bigger"))
        notices.give([notice("n1", client: "c1", kind: .couldntFix)])
        await center.check()
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .couldntFix)

        await center.tryAgain(clientReportId: "c1")

        XCTAssertEqual(resender.sent.count, 1)
        XCTAssertEqual(resender.sent.first?.transcript, "make the circles bigger")
        XCTAssertNotEqual(resender.sent.first?.clientReportId, "c1", "the server keeps one row per phone id")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }

    func testCloseTakesCouldntFixAway() async {
        let notices = FakeNotices()
        let center = makeCenter(notices: notices)
        center.didSend(makeReport(clientReportId: "c1"))
        notices.give([notice("n1", client: "c1", kind: .couldntFix)])
        await center.check()
        center.putAway(clientReportId: "c1")
        XCTAssertNil(center.display(for: "reminders", repairModeOn: false))
        XCTAssertNil(center.sentDrawing(clientReportId: "c1"))
    }

    func testRepairingSurvivesARelaunch() {
        let stateFile = temporaryFolder("repair-center").appending(path: "state.json")
        let sentFolder = temporaryFolder("repairs-sent")
        folders.append(stateFile.deletingLastPathComponent())
        let first = makeCenter(notices: FakeNotices(), stateFile: stateFile, sentFolder: sentFolder)
        first.didSend(makeReport(clientReportId: "c1"))

        let relaunched = makeCenter(notices: FakeNotices(), stateFile: stateFile, sentFolder: sentFolder)

        XCTAssertEqual(relaunched.display(for: "reminders", repairModeOn: false), .repairing(count: 1, takingLonger: false))
    }

    func testNothingWaitingAsksTheServerNothing() async {
        let notices = FakeNotices()
        let center = makeCenter(notices: notices)
        await center.check()
        XCTAssertEqual(notices.asked, 0)
    }

    func testTheShellOwnsOneCenterAndAsksWhenMidasOpens() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appending(path: "Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("await ShellServices.shared.repairCenter.check()"))
        XCTAssertTrue(app.contains("repairCenter.sidekickOpened(sidekick.id)"))
        XCTAssertTrue(app.contains("repairCenter.sidekickClosed(sidekick.id)"))
    }
}

// MARK: - Notices with a kind

@MainActor
final class RepairNoticeKindTests: XCTestCase {
    func testTheNoticesAnswerCarriesKindSummaryAndThePhonesId() {
        let body = #"{"notices":[{"id":"n1","reportId":"r1","clientReportId":"c1","sidekickId":"reminders","kind":"already_there","summary":"Already there.","text":"Already there. Nothing needed to change.","createdAt":"2026-10-23T00:00:00Z"},{"id":"n2","reportId":"r2","text":"The update you requested is done."},{"id":"n3","reportId":"r3","kind":"something_new","text":"x"}]}"#
        let notices = RemoteJessRepairNotices.notices(statusCode: 200, data: Data(body.utf8))
        XCTAssertEqual(notices?.count, 3)
        XCTAssertEqual(notices?[0].resultKind, .alreadyThere)
        XCTAssertEqual(notices?[0].summary, "Already there.")
        XCTAssertEqual(notices?[0].clientReportId, "c1")
        XCTAssertEqual(notices?[1].resultKind, .fixed, "an older server only sent fixed notices")
        XCTAssertNil(notices?[2].kind, "an unknown kind never hides the list")
    }

    func testAJessCardIsNotTurnedDoneByARepairThatCouldNotBeMade() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Midas/JessRepairFollowUp.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("notice.resultKind != .couldntFix"))
    }
}

// MARK: - The swipe, the rim and Send

final class RepairSwipeProgressTests: XCTestCase {
    private func track(down: Double) -> [RepairGesturePoint] {
        [RepairGesturePoint(x: 100, y: 100, ms: 0), RepairGesturePoint(x: 100, y: 100 + down, ms: 100)]
    }

    func testProgressIsTheSlowestFingersShareOfTheWay() {
        let thresholds = SwipeDownThresholds.standard
        XCTAssertEqual(ThreeFingerSwipeDetector.progress(tracks: [track(down: 40), track(down: 60)], thresholds: thresholds), 0, "two fingers are not the swipe")
        XCTAssertEqual(ThreeFingerSwipeDetector.progress(tracks: [track(down: 40), track(down: 60), track(down: 80)], thresholds: thresholds), 0.5, accuracy: 0.001)
        XCTAssertEqual(ThreeFingerSwipeDetector.progress(tracks: [track(down: 200), track(down: 160), track(down: 90)], thresholds: thresholds), 1)
        XCTAssertEqual(ThreeFingerSwipeDetector.progress(tracks: [track(down: -10), track(down: 60), track(down: 80)], thresholds: thresholds), 0)
    }
}

@MainActor
final class RepairChromeTests: XCTestCase {
    private func makeChrome(reduceMotion: Bool = false) -> (RepairChrome, HapticCounter) {
        let chrome = RepairChrome()
        let counter = HapticCounter()
        chrome.reduceMotion = { reduceMotion }
        chrome.lockHaptic = counter.lock
        chrome.sendHaptic = counter.send
        return (chrome, counter)
    }

    func testTheRimFollowsTheFingersButNotAStrayTouch() {
        let (chrome, _) = makeChrome()
        chrome.swipeProgressed(0.05)
        XCTAssertFalse(chrome.isRimShown, "a stray three-finger touch never flashes the rim")
        chrome.swipeProgressed(0.5)
        XCTAssertEqual(chrome.rimPhase, .tracing)
        XCTAssertEqual(chrome.traceEnd, 0.5 * RepairRimSpec.tracedShare, accuracy: 0.001)
        XCTAssertFalse(chrome.repairModeOn)
    }

    func testLockClosesTheRimDropsTheTagAndTapsOnce() {
        let (chrome, counter) = makeChrome()
        chrome.swipeProgressed(0.6)
        chrome.swipeProgressed(1)
        chrome.swipeLocked()
        XCTAssertEqual(chrome.rimPhase, .on)
        XCTAssertEqual(chrome.traceEnd, 1)
        XCTAssertTrue(chrome.repairModeOn)
        XCTAssertEqual(counter.locks, 1)
    }

    func testTheRimStaysOnWhileTheLayerIsUpAndLeavesOnSendOrCancel() {
        let (chrome, counter) = makeChrome()
        chrome.swipeLocked()
        chrome.swipeProgressed(0)
        XCTAssertEqual(chrome.rimPhase, .on, "a lift after the lock does not take the rim away")
        chrome.sessionEnded(.sent)
        XCTAssertEqual(chrome.rimPhase, .draining)
        XCTAssertFalse(chrome.repairModeOn)
        XCTAssertFalse(chrome.tagRisesOnLeave)
        chrome.pageFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        chrome.tagFrame = CGRect(x: 164, y: 54, width: 74, height: 26)
        let sentAt = Date()
        chrome.playSendAnimation(shot: solidImage(size: CGSize(width: 2, height: 2), white: 1), now: sentAt)
        XCTAssertNotNil(chrome.flyingShot)
        XCTAssertEqual(counter.sends, 1)
        XCTAssertEqual(chrome.sendTagLook(at: sentAt)?.labelMix, 0, "the tag still says Repair as the shot sets off")
        chrome.finishSend(startedAt: sentAt)
        XCTAssertNil(chrome.flyingShot)
        XCTAssertNil(chrome.sendTagLook(at: sentAt))

        let (cancelled, _) = makeChrome()
        cancelled.swipeLocked()
        cancelled.sessionEnded(.cancelled)
        XCTAssertEqual(cancelled.rimPhase, .fading)
        XCTAssertTrue(cancelled.tagRisesOnLeave, "Cancel sends the tag back into the island")
    }

    func testReduceMotionFadesTheRimInsteadOfTracingIt() {
        let (chrome, _) = makeChrome(reduceMotion: true)
        chrome.swipeProgressed(0.5)
        XCTAssertEqual(chrome.traceEnd, 1, "drawn whole, faded in")
    }

    func testTheRimIsVoltOnAnInkLineInLightModeOnly() {
        XCTAssertEqual(RepairVolt.hex, "#CEFF00")
        XCTAssertTrue(RepairRimSpec.hasKeyline(for: .light))
        XCTAssertFalse(RepairRimSpec.hasKeyline(for: .dark))
        XCTAssertEqual(RepairRimSpec.lineWidth, 4)
        XCTAssertEqual(RepairRimSpec.inset, 4)
        XCTAssertEqual(RepairRimSpec.keylineWidth, 8)
    }
}

@MainActor
private final class HapticCounter {
    private(set) var locks = 0
    private(set) var sends = 0

    func lock() {
        locks += 1
    }

    func send() {
        sends += 1
    }
}

// MARK: - Send: T1c "Quick and quiet"

final class RepairSendMotionTests: XCTestCase {
    private let stage = RepairSendMotion.Stage(page: CGRect(x: 0, y: 0, width: 402, height: 874), tag: CGRect(x: 164, y: 54, width: 74, height: 26))

    func testTheShotSetsOffAsThePageAndEndsAsASmallCapsuleAboveTheTagCentre() {
        let start = RepairSendMotion.box(at: 0, stage: stage)
        XCTAssertEqual(start.scale, 1)
        XCTAssertEqual(start.center, CGPoint(x: 201, y: 437))
        XCTAssertEqual(start.cornerRadius, 56, accuracy: 0.01, "phone corners while big")
        let end = RepairSendMotion.box(at: 3, stage: stage)
        XCTAssertEqual(end.center.x, 201, accuracy: 0.01, "straight up")
        XCTAssertEqual(end.center.y, 67 - 27, accuracy: 0.5, "aims 27 pt above the tag centre")
        XCTAssertEqual(402 * end.scale, 18, accuracy: 1)
        XCTAssertEqual(874 * end.scale, 39, accuracy: 1)
        XCTAssertEqual(end.cornerRadius, 201, accuracy: 0.5, "a capsule once small")
    }

    func testItNeverOvershootsAndShrinksAheadOfTheTravel() {
        var previousY = CGFloat.infinity
        var seconds = 0.0
        while seconds < 1.5 {
            let box = RepairSendMotion.box(at: seconds, stage: stage)
            XCTAssertLessThanOrEqual(box.center.y, previousY + 0.001, "damping 1.0: it only ever moves up")
            previousY = box.center.y
            seconds += 0.02
        }
        let early = RepairSendMotion.box(at: 0.1, stage: stage)
        let travelled = (437 - early.center.y) / (437 - 40)
        XCTAssertGreaterThan(1 - early.scale, travelled * (1 - RepairSendMotion.endScale), "the shrink leads")
    }

    func testItIsClippedAtTheTagsLowerEdgeOnlyOnceItFits() {
        let big = RepairSendMotion.box(at: 0.05, stage: stage)
        XCTAssertNil(RepairSendMotion.clipTop(big, stage: stage))
        let small = RepairSendMotion.box(at: 1, stage: stage)
        XCTAssertEqual(RepairSendMotion.clipTop(small, stage: stage), 80)
        let contact = RepairSendMotion.contactSeconds(stage: stage)
        let gone = RepairSendMotion.goneSeconds(stage: stage)
        XCTAssertGreaterThan(contact, 0)
        XCTAssertGreaterThan(gone, contact)
        XCTAssertLessThan(gone, RepairSendMotion.duration)
    }

    func testTheTagSwellsOnContactThenReadsOnItAndWidens() {
        let contact = RepairSendMotion.contactSeconds(stage: stage)
        let gone = RepairSendMotion.goneSeconds(stage: stage)
        let before = RepairSendMotion.tagLook(at: contact - 0.01, contact: contact, gone: gone, reduceMotion: false)
        XCTAssertEqual(before.swellX, 1)
        XCTAssertEqual(before.labelMix, 0)
        XCTAssertEqual(before.width, RepairSendMotion.tagWidth(for: "Edit", withOrb: false))
        XCTAssertEqual(RepairSendMotion.tagWidth(for: "Edit", withOrb: false), 49, accuracy: 3, "\"Edit\" alone is about 49 pt")
        var peakX: CGFloat = 1
        var peakY: CGFloat = 1
        var seconds = contact
        while seconds < contact + 0.4 {
            let look = RepairSendMotion.tagLook(at: seconds, contact: contact, gone: gone, reduceMotion: false)
            peakX = max(peakX, look.swellX)
            peakY = max(peakY, look.swellY)
            seconds += 0.002
        }
        XCTAssertEqual(peakX, 1.08, accuracy: 0.002)
        XCTAssertEqual(peakY, 1.05, accuracy: 0.002)
        let after = RepairSendMotion.tagLook(at: gone + 0.14, contact: contact, gone: gone, reduceMotion: false)
        XCTAssertEqual(after.labelMix, 1, accuracy: 0.001, "140 ms cross-fade once the shot is inside")
        let settled = RepairSendMotion.tagLook(at: 3, contact: contact, gone: gone, reduceMotion: false)
        XCTAssertEqual(settled.width, RepairSendMotion.tagWidth(for: "On it", withOrb: true), accuracy: 0.5)
        XCTAssertEqual(RepairSendMotion.tagWidth(for: "On it", withOrb: true), 73, accuracy: 3, "\"On it\" with its orb is about 73 pt")
    }

    func testReduceMotionFadesWithNoSwell() {
        let look = RepairSendMotion.tagLook(at: 0.1, contact: 0.05, gone: 0.2, reduceMotion: true)
        XCTAssertEqual(look.swellX, 1)
        XCTAssertEqual(look.swellY, 1)
        XCTAssertEqual(RepairSendMotion.reducedShotOpacity(at: 0.2), 0, accuracy: 0.001)
        XCTAssertEqual(RepairSendMotion.reducedShotOpacity(at: 0), 1)
    }
}

// MARK: - Strokes

@MainActor
final class RepairVoltPenTests: XCTestCase {
    func testOnWhiteTheVoltStrokeSitsOnAnInkLine() {
        let screenshot = solidImage(size: CGSize(width: 60, height: 60), white: 1)
        let stroke = RepairStroke(points: [[10, 30, 0], [50, 30, 100]])
        let drawing = RepairDrawingRenderer.render(screenshot: screenshot, strokes: [stroke], penColor: RepairPen.uiColor, keylineColor: RepairPen.keyline(for: .light))
        let middle = pixel(in: drawing, x: 30, y: 30)
        XCTAssertEqual(middle.red, 206, accuracy: 3)
        XCTAssertEqual(middle.green, 255, accuracy: 2)
        XCTAssertEqual(middle.blue, 0, accuracy: 2)
        // 3.5 pt from the centre: outside the 5 pt Volt, inside the 8 pt ink line
        let edge = pixel(in: drawing, x: 30, y: 33)
        XCTAssertLessThan(edge.red + edge.green + edge.blue, 120, "the ink line shows at the edge")
    }

    func testInDarkModeThereIsNoInkLine() {
        XCTAssertNil(RepairPen.keyline(for: .dark))
        XCTAssertNotNil(RepairPen.keyline(for: .light))
    }

    func testTheSentDrawingUsesTheModeTheSwipeFiredIn() {
        let uploader = RepairUploader(api: NoUpload(), outbox: RepairOutbox(directoryURL: temporaryFolder("outbox")))
        let session = RepairSession(sidekickId: "reminders", snapshot: solidImage(size: CGSize(width: 60, height: 60), white: 1), viewSize: CGSize(width: 60, height: 60), transcriber: DeafTranscriber(), uploader: uploader)
        session.beginStroke(at: CGPoint(x: 10, y: 30))
        session.extendStroke(to: CGPoint(x: 50, y: 30))
        session.endStroke()
        session.interfaceStyle = .light
        let light = pixel(in: session.renderDrawing(), x: 30, y: 33)
        session.interfaceStyle = .dark
        let dark = pixel(in: session.renderDrawing(), x: 30, y: 33)
        XCTAssertLessThan(light.red + light.green + light.blue, 120)
        XCTAssertGreaterThan(dark.red + dark.green + dark.blue, 700)
    }
}

// MARK: - Send and Cancel

@MainActor
final class RepairSessionFinishTests: XCTestCase {
    private func makeSession() -> RepairSession {
        let uploader = RepairUploader(api: NoUpload(), outbox: RepairOutbox(directoryURL: temporaryFolder("outbox")))
        return RepairSession(sidekickId: "reminders", snapshot: solidImage(size: CGSize(width: 20, height: 30), white: 1), viewSize: CGSize(width: 20, height: 30), transcriber: DeafTranscriber(), uploader: uploader)
    }

    func testSendHandsTheReportAndTheCircledShotToTheTag() {
        let session = makeSession()
        var sent: [(RepairReport, UIImage)] = []
        var finishedAs: RepairFinish?
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { report, drawing in sent.append((report, drawing)) }
        session.typedText = "move it"
        session.send()
        XCTAssertEqual(finishedAs, .sent)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.0.clientReportId, session.id)
        XCTAssertEqual(sent.first?.1.size, CGSize(width: 20, height: 30))
    }

    func testCancelSendsNothingToTheTag() {
        let session = makeSession()
        var sentCount = 0
        session.onSent = { _, _ in sentCount += 1 }
        session.typedText = "never mind"
        session.cancel()
        XCTAssertEqual(session.finish, .cancelled)
        XCTAssertEqual(sentCount, 0)
    }

    func testTryAgainKeepsEverythingButThePhonesId() {
        let report = makeReport(clientReportId: "c1", transcript: "bigger circles")
        let resent = report.resent(clientReportId: "c2")
        XCTAssertEqual(resent.clientReportId, "c2")
        XCTAssertEqual(resent.transcript, "bigger circles")
        XCTAssertEqual(resent.drawingPNG, report.drawingPNG)
        XCTAssertEqual(resent.bundleVersion, report.bundleVersion)
    }
}

// MARK: - The update out of the tag (U4)

@MainActor
final class SidekickPageUpdateTests: XCTestCase {
    func testTheNewPageGrowsOutOfTheTagNotTheCentre() {
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let tag = CGPoint(x: 201, y: 67)
        let transform = SidekickPageUpdateSpec.scaling(SidekickPageUpdateSpec.newPageStartScale, about: tag, in: bounds)
        // UIKit applies a view's transform about its centre
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let tagFromCenter = CGPoint(x: tag.x - center.x, y: tag.y - center.y)
        let moved = tagFromCenter.applying(transform)
        XCTAssertEqual(moved.x, tagFromCenter.x, accuracy: 0.001)
        XCTAssertEqual(moved.y, tagFromCenter.y, accuracy: 0.001)
        let corner = CGPoint(x: -center.x, y: -center.y).applying(transform)
        XCTAssertLessThan(abs(corner.x - tagFromCenter.x), 0.08 * 402, "the page starts at 7% around the tag")
    }

    func testU4Numbers() {
        XCTAssertEqual(SidekickPageUpdateSpec.tagPressScale, 0.94)
        XCTAssertEqual(SidekickPageUpdateSpec.tagPress, 0.12)
        XCTAssertEqual(SidekickPageUpdateSpec.newPageStartScale, 0.07)
        XCTAssertEqual(SidekickPageUpdateSpec.grow, 0.6)
        XCTAssertEqual(SidekickPageUpdateSpec.fadeInShare, 0.3)
        XCTAssertEqual(SidekickPageUpdateSpec.oldPageScale, 0.97)
        XCTAssertEqual(SidekickPageUpdateSpec.oldPageAlpha, 0.5)
        XCTAssertEqual(SidekickPageUpdateSpec.reduceMotionFade, 0.2)
    }

    func testTheUpdateShowsTheNewPageOnceItHasLoaded() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let webView = WKWebView(frame: container.bounds)
        container.addSubview(webView)
        var finishLoad: (@MainActor () -> Void)?
        func reload(_ shown: @escaping @MainActor () -> Void) {
            finishLoad = shown
        }
        SidekickPageUpdate.play(webView: webView, tagCenterInWindow: CGPoint(x: 50, y: 20), reduceMotion: true, reload: reload)
        XCTAssertEqual(webView.alpha, 0, "the old page stays until the new one is in")
        XCTAssertEqual(container.subviews.count, 2)
        finishLoad?()
        XCTAssertEqual(webView.alpha, 1)
    }

    func testTheNavigationGuardReportsTheNextLoadOnce() {
        let navigationGuard = SidekickNavigationGuard(sidekickId: "reminders")
        var finished = 0
        navigationGuard.onNextLoadFinished = { finished += 1 }
        let webView = WKWebView()
        navigationGuard.webView(webView, didFinish: nil)
        navigationGuard.webView(webView, didFinish: nil)
        XCTAssertEqual(finished, 1)
    }

    func testAnUpdateReloadsTheSidekicksOwnPage() {
        let coordinator = SidekickWebViewCoordinator(sidekickId: "reminders")
        var calledBack = false
        coordinator.reloadPage(finished: { calledBack = true })
        XCTAssertTrue(calledBack, "no web view: nothing to wait for")
    }
}

// MARK: - The pill

/// Hosts the repair layer the way `SidekickScreen` does.
private struct HostedLayer: View {
    let session: RepairSession
    let onLayout: (RepairLayerPart, CGRect) -> Void

    var body: some View {
        Color.gray
            .repairLayer(session, onLayout: onLayout)
    }
}

@MainActor
private final class PartFrames {
    var send = CGRect.zero
    var bar = CGRect.zero

    func receive(_ part: RepairLayerPart, _ frame: CGRect) {
        switch part {
        case .send:
            send = frame
        case .bottomBar:
            bar = frame
        case .snapshot, .cancel:
            break
        }
    }
}

@MainActor
final class RepairPillTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func host(style: UIUserInterfaceStyle, transcriber: RepairTranscribing) async throws -> (UIWindow, PartFrames, RepairSession) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first)
        let hostWindow = UIWindow(windowScene: scene)
        hostWindow.frame = scene.coordinateSpace.bounds
        hostWindow.overrideUserInterfaceStyle = style
        window = hostWindow
        let size = hostWindow.bounds.size
        let uploader = RepairUploader(api: NoUpload(), outbox: RepairOutbox(directoryURL: temporaryFolder("outbox")))
        let session = RepairSession(sidekickId: "reminders", snapshot: solidImage(size: size, white: 0.2), viewSize: size, transcriber: transcriber, uploader: uploader)
        session.typedText = "move it"
        let frames = PartFrames()
        hostWindow.rootViewController = UIHostingController(rootView: HostedLayer(session: session, onLayout: frames.receive))
        hostWindow.makeKeyAndVisible()
        hostWindow.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        hostWindow.layoutIfNeeded()
        return (hostWindow, frames, session)
    }

    private static func firstTextInput(in view: UIView) -> UIView? {
        if view is UITextView || view is UITextField {
            return view
        }
        for subview in view.subviews {
            if let found = firstTextInput(in: subview) {
                return found
            }
        }
        return nil
    }

    /// "What to fix" sits on the orb's and the arrow's centre line, not top left.
    func testTheWordsSitOnThePillsCentreLine() async throws {
        let (hostWindow, frames, _) = try await host(style: .light, transcriber: DeafTranscriber())
        let field = try XCTUnwrap(Self.firstTextInput(in: hostWindow))
        let fieldFrame = field.convert(field.bounds, to: nil)
        XCTAssertGreaterThan(frames.send.height, 0)
        XCTAssertEqual(fieldFrame.midY, frames.send.midY, accuracy: 2, "the words are off the pill's centre line")
        XCTAssertLessThan(fieldFrame.minX - frames.bar.minX, 80, "the words start right after the orb")
    }

    /// Bug: a red recording dot sat in Send the whole time jess listened. The orb shows listening.
    func testSendHasNoRedWhileJessListens() async throws {
        let (hostWindow, frames, session) = try await host(style: .light, transcriber: ListeningTranscriber())
        XCTAssertTrue(session.isListening)
        let renderer = UIGraphicsImageRenderer(bounds: hostWindow.bounds)
        let image = renderer.image { _ in
            hostWindow.drawHierarchy(in: hostWindow.bounds, afterScreenUpdates: true)
        }
        let scale = image.scale
        let pixels = DecodedPixels(image)
        var redPixels = 0
        var y = frames.send.minY
        while y < frames.send.maxY {
            var x = frames.send.minX
            while x < frames.send.maxX {
                let colour = pixels.at(x: Int(x * scale), y: Int(y * scale))
                if colour.red > 160 && colour.green < 110 && colour.blue < 110 {
                    redPixels += 1
                }
                x += 1
            }
            y += 1
        }
        XCTAssertEqual(redPixels, 0, "Send shows red")
    }

    func testTheLayerHasNoRedAndNoTomatoAnyMore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["RepairCanvasView.swift", "RepairSession.swift", "RepairChromeView.swift", "RepairTheme.swift"] {
            let source = try String(contentsOf: root.appending(path: "Midas").appending(path: name), encoding: .utf8)
            XCTAssertFalse(source.contains("Color.red"), "\(name) has red")
            XCTAssertFalse(source.contains("FF6347"), "\(name) still has tomato")
        }
    }
}
