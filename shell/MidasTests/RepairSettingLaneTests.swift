import UIKit
import XCTest
@testable import Midas

// Repair lanes W5, the setting lane (founder, 2026-11-13; docs/briefs/repair-lanes.md W5): the
// Worker maps "make the water blue" to settings, writes settings:self and answers
// { lane: "setting", message: "Changed", setting: { changes } }. The phone closes repair mode with
// no edit on its way and pulls the record; the page's settings engine redraws. A `setting` reply
// without changes (the Worker sent it up to code) closes as an edit, as before.

@MainActor
private final class SettingQuietTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {}

    func stop() {}
}

/// The Worker as a stub: every report gets `reply`.
private final class SettingSortStub: RepairUploadAPI, @unchecked Sendable {
    let reply: RepairSortReply

    init(reply: RepairSortReply) {
        self.reply = reply
    }

    var sortsReports: Bool {
        true
    }

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .accepted
    }

    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        RepairSortedUpload(outcome: .accepted, reply: reply)
    }

    func answerOutcome(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome {
        .failed
    }
}

private let seaChange = RepairSettingResult(changes: [RepairSettingChange(key: "sea.colour", label: "Sea (the rising water) colour")])

final class RepairSettingContractTests: XCTestCase {
    func testTheWorkersSettingReplyDecodes() {
        let json = ##"{"id":"r1","status":"received","lane":"setting","message":"Changed","setting":{"changes":[{"key":"sea.colour","label":"Sea (the rising water) colour","value":"#1E6FD9"}]}}"##
        let reply = RepairSortReply.decode(Data(json.utf8))
        XCTAssertEqual(reply?.lane, .setting)
        XCTAssertEqual(reply?.message, "Changed")
        XCTAssertEqual(reply?.setting, seaChange)
    }

    func testABoolValueOrAnUnknownShapeStillDecodesTheLane() {
        let hidden = #"{"id":"r1","lane":"setting","setting":{"changes":[{"key":"streak.show","label":"Streak","value":false}]}}"#
        XCTAssertEqual(RepairSortReply.decode(Data(hidden.utf8))?.setting?.changes.map(\.key), ["streak.show"])
        let odd = #"{"id":"r1","lane":"setting","setting":"changed"}"#
        let oddReply = RepairSortReply.decode(Data(odd.utf8))
        XCTAssertEqual(oddReply?.lane, .setting)
        XCTAssertNil(oddReply?.setting, "an unreadable setting is left out, so it closes as an edit")
    }

    func testOnlyASettingReplyWithChangesIsDoneOnThePhone() {
        for lane in RepairLane.allCases {
            let reply = RepairSortReply(id: "r1", lane: lane, question: nil, message: nil, setting: seaChange)
            XCTAssertEqual(RepairSortRules.settingDone(reply), lane == .setting, lane.rawValue)
        }
        let upToCode = RepairSortReply(id: "r1", lane: .setting, question: nil, message: nil)
        XCTAssertFalse(RepairSortRules.settingDone(upToCode))
        let empty = RepairSortReply(id: "r1", lane: .setting, question: nil, message: nil, setting: RepairSettingResult(changes: []))
        XCTAssertFalse(RepairSortRules.settingDone(empty))
        XCTAssertFalse(RepairSortRules.settingDone(nil))
    }
}

@MainActor
final class RepairSettingSessionTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-setting-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private func makeSession(reply: RepairSortReply) -> RepairSession {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format).image(actions: Self.fillWhite)
        let uploader = RepairUploader(api: SettingSortStub(reply: reply), outbox: RepairOutbox(directoryURL: outboxURL))
        return RepairSession(sidekickId: "hydration", snapshot: snapshot, viewSize: CGSize(width: 20, height: 30), transcriber: SettingQuietTranscriber(), uploader: uploader)
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

    func testADoneSettingClosesWithNoEditAndPullsTheRecord() async {
        let reply = RepairSortReply(id: "srv-1", lane: .setting, question: nil, message: "Changed", setting: seaChange)
        let session = makeSession(reply: reply)
        var finishedAs: RepairFinish?
        var sentCount = 0
        var pullCount = 0
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { _, _ in sentCount += 1 }
        session.onSettingChanged = { pullCount += 1 }
        session.typedText = "Make the water blue"
        session.send()
        await waitUntil { finishedAs != nil }
        XCTAssertEqual(finishedAs, .answered, "closes like Cancel: no Editing tag waiting for a job that never comes")
        XCTAssertEqual(sentCount, 0, "no edit on its way")
        XCTAssertEqual(pullCount, 1, "the phone pulls settings:self so the page redraws")
    }

    func testASettingTheWorkerSentUpToCodeClosesAsAnEdit() async {
        let reply = RepairSortReply(id: "srv-2", lane: .setting, question: nil, message: nil)
        let session = makeSession(reply: reply)
        var finishedAs: RepairFinish?
        var sentCount = 0
        var pullCount = 0
        session.onFinish = { finishedAs = session.finish }
        session.onSent = { _, _ in sentCount += 1 }
        session.onSettingChanged = { pullCount += 1 }
        session.typedText = "Make the water sparkle"
        session.send()
        await waitUntil { finishedAs != nil }
        XCTAssertEqual(finishedAs, .sent)
        XCTAssertEqual(sentCount, 1, "the tag takes the report: an edit is on its way")
        XCTAssertEqual(pullCount, 0)
    }
}
