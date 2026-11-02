import XCTest
@testable import Midas

// Build 22 small fixes (founder, 2026-11-02, docs/PRODUCT.md section 6 "Open, 2026-10-31: build 22",
// "Small fixes"; pick B): a jess request that needed an edit (jess grew the Sidekick) stayed Not
// Done after the founder fixed the edit by hand. Now, while he works, its Workdesk card says Taking a
// Deeper Look, as a plain edit's does. His fix's own notice settles nothing: the backend re-runs the
// request on his fix and the card turns Done with the result (JessGrowFollowUp, settleGrow).

/// Notices the test hands out; records which were marked seen.
private final class GrowNotices: JessRepairNoticesAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [JessRepairNotice] = []
    private var seenIds: [String] = []

    func give(_ notices: [JessRepairNotice]) {
        lock.withLock {
            queued = notices
        }
    }

    var seen: [String] {
        lock.withLock {
            seenIds
        }
    }

    func notices() async -> [JessRepairNotice]? {
        takeQueued()
    }

    func markSeen(id: String) async {
        recordSeen(id)
    }

    private func takeQueued() -> [JessRepairNotice] {
        lock.withLock {
            queued
        }
    }

    private func recordSeen(_ id: String) {
        lock.withLock {
            seenIds.append(id)
        }
    }
}

@MainActor
private struct GrowBackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

private let growStart = Date(timeIntervalSince1970: 1_793_000_000)
private let growLink = JessRepairLink(reportId: "r1", pendingId: "p1")

@MainActor
private func growResults() -> JessResults {
    let file = FileManager.default.temporaryDirectory.appending(path: "grow-deeper-look-\(UUID().uuidString)/results.json")
    func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        .sentToRepair(sidekickName: "Reminders", link: growLink)
    }
    func isSignedIn() -> Bool {
        true
    }
    func isInForeground() -> Bool {
        false
    }
    func now() -> Date {
        growStart
    }
    func timeZone() -> TimeZone {
        TimeZone(identifier: "America/Los_Angeles")!
    }
    let dependencies = JessResultsDependencies(route: routeCall, backgroundTime: GrowBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone, foregroundRetryDelay: nil)
    return JessResults(file: JessResultsFile(fileURL: file), dependencies: dependencies)
}

@MainActor
final class GrowDeeperLookTests: XCTestCase {
    func testAGrowCardSaysTakingADeeperLookThenTurnsDoneWithTheReRun() async {
        let results = growResults()
        await results.submit(transcript: "remind me to call the bank and flag it", listenMs: 900)
        XCTAssertEqual(results.log[0].kind, .sentToRepair(sidekickName: "Reminders", link: growLink))
        XCTAssertTrue(results.editReportIds.contains("r1"))
        XCTAssertFalse(results.waitingReportIds.contains("r1"), "a grow card is not settled by a repair notice")

        let notices = GrowNotices()
        let followUp = JessRepairFollowUp(api: notices, results: results)
        notices.give([JessRepairNotice(id: "n1", reportId: "r1", text: "Check back in some time.", kind: .couldntFix, summary: nil, clientReportId: nil)])
        await followUp.check()

        XCTAssertEqual(results.log[0].takingDeeperLook, true)
        XCTAssertEqual(VoiceReminderCopy.cardTitle(results.log[0]), "Taking a Deeper Look")
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(results.log[0]), "Taking a Deeper Look")
        XCTAssertTrue(results.homeCards.isEmpty, "not Not Done: nothing on home")
        XCTAssertEqual(notices.seen, [])

        // The founder's fix: its notice settles nothing; the card keeps waiting for the re-run
        notices.give([
            JessRepairNotice(id: "n1", reportId: "r1", text: "Check back in some time.", kind: .couldntFix, summary: nil, clientReportId: nil),
            JessRepairNotice(id: "n2", reportId: "r1", text: "The update you requested is done.", kind: .fixed, summary: "Flags.", clientReportId: nil),
        ])
        await followUp.check()
        XCTAssertEqual(results.log[0].kind, .sentToRepair(sidekickName: "Reminders", link: growLink))
        XCTAssertEqual(notices.seen, [])

        // The backend re-ran the request on the fix
        XCTAssertTrue(results.settleGrow(pendingId: "p1", result: .done(text: "Added Call the bank", at: nil, allDay: nil, timeZone: nil)))
        XCTAssertEqual(results.log[0].kind, .done(text: "Added Call the bank", at: nil, allDay: false, timeZone: nil))
        XCTAssertNil(results.log[0].takingDeeperLook)
        XCTAssertFalse(results.editReportIds.contains("r1"))
    }
}
