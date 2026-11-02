import UIKit
import XCTest
@testable import Midas

// "Taking a Deeper Look" (founder, 2026-11-01; docs/mockups/edit-deeper-look-2026-11-01.html): an
// edit the agent could not make never ends as a failure. The Edit tag says "Taking a Deeper Look"
// with its orb still spinning and no close (L1), keeps listening, and the founder's fix (made by
// hand, published, thread marked Built) turns it into "Edit done. Tap to update". A repair jess
// sent says the same on its Workdesk card until the fix settles it as done.

// MARK: - Stand-ins

/// Notices the test hands out; records which were marked seen and how often the server was asked.
private final class DeeperLookNotices: JessRepairNoticesAPI, @unchecked Sendable {
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
        var unseen: [JessRepairNotice] = []
        for notice in queued where !seenNow.contains(notice.id) {
            unseen.append(notice)
        }
        return unseen
    }

    private func recordSeen(_ id: String) {
        lock.lock()
        seenIds.append(id)
        lock.unlock()
    }
}

@MainActor
private final class DeeperLookResender: RepairResending {
    private(set) var sentCount = 0

    func send(_ report: RepairReport) async {
        sentCount += 1
    }
}

@MainActor
private struct DeeperLookBackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

private let deeperLookStart = Date(timeIntervalSince1970: 1_793_000_000)

private func deeperLookFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
}

private func deeperLookDrawing() -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format)
    let image = renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
    return image.pngData() ?? Data()
}

private func deeperLookReport(clientReportId: String, sidekickId: String = "reminders") -> RepairReport {
    RepairReport(
        clientReportId: clientReportId,
        sidekickId: sidekickId,
        kind: RepairReport.unknownKind,
        bundleVersion: "v7",
        bundleScope: "user",
        transcript: "add a due date to each one",
        spokenText: "add a due date to each one",
        typedText: "",
        words: [],
        strokesJSON: Data("[]".utf8),
        screenshotJPEG: Data([0xFF, 0xD8]),
        drawingPNG: deeperLookDrawing(),
        device: "iPhone",
        iosVersion: "27.0",
        appVersion: "1",
        appBuild: "1"
    )
}

private func deeperLookNotice(_ id: String, client: String?, kind: RepairResultKind, summary: String? = nil, reportId: String? = nil) -> JessRepairNotice {
    JessRepairNotice(id: id, reportId: reportId ?? "server-\(id)", text: "words", kind: kind, summary: summary, clientReportId: client)
}

// MARK: - The words and the look

final class EditDeeperLookWordsTests: XCTestCase {
    func testTheTagSaysTakingADeeperLookAndNeverFailedOrCheckBack() {
        XCTAssertEqual(RepairTagCopy.couldntFix, "Taking a Deeper Look")
        XCTAssertEqual(RepairTagDisplay.couldntFix.words, "Taking a Deeper Look")
        XCTAssertEqual(RepairTagCopy.words(for: .couldntFix, secondsSinceSend: 1), "Taking a Deeper Look")
        XCTAssertFalse(RepairTagDisplay.couldntFix.words.lowercased().contains("fail"))
        XCTAssertFalse(RepairTagDisplay.couldntFix.words.contains("Check back"))
        XCTAssertNil(RepairTagDisplay.couldntFix.leavesAfterSeconds, "stays until the founder's fix lands")
        XCTAssertNil(RepairTagDisplay.couldntFix.summary)
        XCTAssertEqual(VoiceReminderCopy.takingDeeperLook, "Taking a Deeper Look")
    }

    func testTheTagKeepsSpinningAndHasNoClose() throws {
        let shellRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let chromeSource = try String(contentsOf: shellRoot.appending(path: "Midas/RepairChromeView.swift"), encoding: .utf8)
        XCTAssertTrue(chromeSource.contains("case .repairing, .couldntFix:"), "the orb spins through a deeper look")
        XCTAssertFalse(chromeSource.contains("xmark"), "L1: no close on the tag")
        XCTAssertFalse(chromeSource.contains("onClose"))
    }
}

// MARK: - The tag's rule

final class EditDeeperLookRulesTests: XCTestCase {
    func testANewerEditOnTheSameSidekickShowsEditingThenTheDeeperLookAgain() {
        let deeperLook = RepairOutcome(clientReportId: "a", sidekickId: "reminders", kind: .couldntFix, summary: nil, arrivedAt: deeperLookStart, arrivedWhileOpen: true)
        let newer = RepairPending(clientReportId: "b", sidekickId: "reminders", transcript: "t", sentAt: deeperLookStart)
        var state = RepairCenterState(pending: [newer], outcomes: [deeperLook])
        XCTAssertEqual(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: false, now: deeperLookStart), .repairing(count: 1, takingLonger: false))
        XCTAssertNil(RepairTagRules.display(state: state, sidekickId: "groceries", repairModeOn: false, now: deeperLookStart))
        state.pending = []
        XCTAssertEqual(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: false, now: deeperLookStart), .couldntFix)
        XCTAssertEqual(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: true, now: deeperLookStart), .repairMode)
    }

    func testOtherResultsStillShowBeforeANewerEdit() {
        let alreadyThere = RepairOutcome(clientReportId: "a", sidekickId: "reminders", kind: .alreadyThere, summary: "There.", arrivedAt: deeperLookStart, arrivedWhileOpen: true)
        let newer = RepairPending(clientReportId: "b", sidekickId: "reminders", transcript: "t", sentAt: deeperLookStart)
        let state = RepairCenterState(pending: [newer], outcomes: [alreadyThere])
        XCTAssertEqual(RepairTagRules.display(state: state, sidekickId: "reminders", repairModeOn: false, now: deeperLookStart), .alreadyThere(summary: "There."))
    }
}

// MARK: - The center keeps listening

@MainActor
final class EditDeeperLookCenterTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        super.tearDown()
    }

    private func makeCenter(notices: DeeperLookNotices, stateFile: URL? = nil, sentFolder: URL? = nil) -> RepairCenter {
        let sent = sentFolder ?? deeperLookFolder("deeper-look-sent")
        folders.append(sent)
        let file = stateFile.map(RepairCenterFile.init(fileURL:))
        return RepairCenter(notices: notices, resender: DeeperLookResender(), sentReports: RepairOutbox(directoryURL: sent), file: file, pollSeconds: 3600, deeperLookPollSeconds: 3600)
    }

    func testTheFoundersFixTurnsTheDeeperLookIntoEditDoneOnThePage() async {
        let notices = DeeperLookNotices()
        let center = makeCenter(notices: notices)
        var refreshedAway: [String] = []
        center.onFixedAway = { refreshedAway.append($0) }
        center.sidekickOpened("reminders")
        center.didSend(deeperLookReport(clientReportId: "c1"))
        notices.give([deeperLookNotice("n1", client: "c1", kind: .couldntFix)])

        await center.check()

        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .couldntFix)
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false)?.words, "Taking a Deeper Look")
        XCTAssertTrue(center.state.pending.isEmpty)
        XCTAssertEqual(center.deeperLooks.map(\.clientReportId), ["c1"])
        XCTAssertEqual(notices.seen, ["n1"])
        XCTAssertNotNil(center.sentDrawing(clientReportId: "c1"), "what was sent stays while the founder works")

        // Nothing new yet: the server is still asked, the tag stays
        let askedBefore = notices.asked
        await center.check()
        XCTAssertEqual(notices.asked, askedBefore + 1, "a deeper look keeps asking")
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .couldntFix)

        // The founder published and marked it Built: the same report comes back fixed
        notices.give([deeperLookNotice("n1", client: "c1", kind: .couldntFix), deeperLookNotice("n2", client: "c1", kind: .fixed, summary: "Added a due date to each one.\nmore")])
        await center.check()

        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .fixed(onPage: true, summary: "Added a due date to each one."))
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false)?.words, "Edit done. Tap to update")
        XCTAssertEqual(notices.seen, ["n1", "n2"])
        XCTAssertTrue(center.deeperLooks.isEmpty)
        XCTAssertNil(center.sentDrawing(clientReportId: "c1"), "the sent report is let go once the fix lands")
        XCTAssertEqual(refreshedAway, [], "on the page the user updates it with the tap")

        // Nothing waits any more: the server is not asked
        let askedAfter = notices.asked
        await center.check()
        XCTAssertEqual(notices.asked, askedAfter)
    }

    func testTheFoundersFixWhileAwayRefreshesAndShowsFixedOnReturn() async {
        let notices = DeeperLookNotices()
        let center = makeCenter(notices: notices)
        var refreshedAway: [String] = []
        center.onFixedAway = { refreshedAway.append($0) }
        center.didSend(deeperLookReport(clientReportId: "c1"))
        notices.give([deeperLookNotice("n1", client: "c1", kind: .couldntFix)])
        await center.check()

        notices.give([deeperLookNotice("n2", client: "c1", kind: .fixed)])
        await center.check()

        XCTAssertEqual(refreshedAway, ["reminders"])
        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .fixed(onPage: false, summary: nil))
    }

    func testAnotherCouldNotNoticeLeavesTheDeeperLookInPlace() async {
        let notices = DeeperLookNotices()
        let center = makeCenter(notices: notices)
        center.didSend(deeperLookReport(clientReportId: "c1"))
        notices.give([deeperLookNotice("n1", client: "c1", kind: .couldntFix)])
        await center.check()

        notices.give([deeperLookNotice("n2", client: "c1", kind: .couldntFix), deeperLookNotice("n3", client: nil, kind: .fixed)])
        await center.check()

        XCTAssertEqual(center.display(for: "reminders", repairModeOn: false), .couldntFix)
        XCTAssertEqual(notices.seen, ["n1", "n2"], "a notice for a repair jess sent is left for jess")
    }

    func testADeeperLookSurvivesARelaunchAndStillTurnsDone() async {
        let stateFolder = deeperLookFolder("deeper-look-state")
        folders.append(stateFolder)
        let stateFile = stateFolder.appending(path: "state.json")
        let sentFolder = deeperLookFolder("deeper-look-sent")
        let notices = DeeperLookNotices()
        let first = makeCenter(notices: notices, stateFile: stateFile, sentFolder: sentFolder)
        first.didSend(deeperLookReport(clientReportId: "c1"))
        notices.give([deeperLookNotice("n1", client: "c1", kind: .couldntFix)])
        await first.check()

        let relaunched = makeCenter(notices: notices, stateFile: stateFile, sentFolder: sentFolder)
        XCTAssertEqual(relaunched.display(for: "reminders", repairModeOn: false), .couldntFix)
        relaunched.sidekickOpened("reminders")
        notices.give([deeperLookNotice("n2", client: "c1", kind: .fixed)])
        await relaunched.check()

        XCTAssertEqual(relaunched.display(for: "reminders", repairModeOn: false), .fixed(onPage: true, summary: nil))
    }
}

// MARK: - A repair jess sent

@MainActor
final class EditDeeperLookJessCardTests: XCTestCase {
    private var files: [URL] = []

    override func tearDown() {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        files = []
        super.tearDown()
    }

    private func makeResults(file: URL) -> JessResults {
        func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
            .notDone(transcript: transcript)
        }
        func isSignedIn() -> Bool {
            true
        }
        func isInForeground() -> Bool {
            false
        }
        func now() -> Date {
            deeperLookStart
        }
        func timeZone() -> TimeZone {
            TimeZone(identifier: "America/Los_Angeles")!
        }
        let dependencies = JessResultsDependencies(route: routeCall, backgroundTime: DeeperLookBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone, foregroundRetryDelay: nil)
        return JessResults(file: JessResultsFile(fileURL: file), dependencies: dependencies)
    }

    func testTheWorkdeskCardSaysTakingADeeperLookThenTurnsDoneWithTheFix() async {
        let file = deeperLookFolder("deeper-look-results").appendingPathExtension("json")
        files.append(file)
        let results = makeResults(file: file)
        results.present(.sentToRepair(sidekickName: "Reminders", link: JessRepairLink(reportId: "r1", pendingId: nil)))
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(results.log[0]), "Reminders")
        XCTAssertEqual(VoiceReminderCopy.cardTitle(results.log[0]), "Sent to Edit")

        let api = DeeperLookNotices()
        let followUp = JessRepairFollowUp(api: api, results: results)
        api.give([deeperLookNotice("n1", client: nil, kind: .couldntFix, reportId: "r1")])
        await followUp.check()

        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(results.log[0]), "Taking a Deeper Look")
        XCTAssertEqual(VoiceReminderCopy.cardTitle(results.log[0]), "Taking a Deeper Look")
        XCTAssertEqual(results.log[0].kind, .sentToRepair(sidekickName: "Reminders", link: JessRepairLink(reportId: "r1", pendingId: nil)), "still waiting for the fix")
        XCTAssertTrue(results.waitingReportIds.contains("r1"))
        XCTAssertEqual(api.seen, [], "the could-not notice is left unseen, as before")
        XCTAssertEqual(makeResults(file: file).log[0].takingDeeperLook, true, "kept on disk")

        // The founder's fix
        api.give([deeperLookNotice("n1", client: nil, kind: .couldntFix, reportId: "r1"), JessRepairNotice(id: "n2", reportId: "r1", text: "The update you requested is done.", kind: .fixed, summary: nil, clientReportId: nil)])
        await followUp.check()

        XCTAssertEqual(results.log[0].kind, .done(text: "The update you requested is done.", at: nil, allDay: false, timeZone: nil))
        XCTAssertNil(results.log[0].takingDeeperLook)
        XCTAssertFalse(results.waitingReportIds.contains("r1"))
        XCTAssertEqual(api.seen, ["n2"])
    }

    func testAnOlderCardWithoutTheFieldStillReads() throws {
        let card = JessResultCard(id: UUID(), kind: .sentToRepair(sidekickName: "Reminders", link: nil), transcript: "", createdAt: deeperLookStart)
        let encoder = JSONEncoder()
        let data = try encoder.encode(card)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "takingDeeperLook")
        let olderData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(JessResultCard.self, from: olderData)
        XCTAssertNil(decoded.takingDeeperLook)
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(decoded), "Reminders")
    }
}
