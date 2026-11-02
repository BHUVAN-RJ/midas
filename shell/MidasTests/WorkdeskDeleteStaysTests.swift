import XCTest
@testable import Midas

// Small fixes, build 22 (founder, 2026-11-02, docs/PRODUCT.md section 6 "Open, 2026-10-31: build
// 22", "Small fixes"): a Workdesk card deleted while it is working came back as a new card when
// its answer arrived. Once deleted it must stay deleted: a request still on its way finishes (its
// ops are the server's and the Sidekick's), but no card for it shows again, on the Workdesk or
// home, after an answer, a resend, a grow result, or a reopen of Midas.

private let deleteSaidTime = Date(timeIntervalSince1970: 1_793_000_000)

@MainActor
private final class DeleteBackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

/// Answers in order; while `holdNext` is set the next call waits until `release` gives it its
/// answer, so a test can delete the card while the request is on its way.
@MainActor
private final class DeleteRoute {
    var answers: [JessResult]
    var holdNext = false
    private(set) var callCount = 0
    private var held: CheckedContinuation<Void, Never>?

    init(answers: [JessResult]) {
        self.answers = answers
    }

    var isHolding: Bool {
        held != nil
    }

    func release() {
        let continuation = held
        held = nil
        continuation?.resume()
    }

    func route(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        callCount += 1
        if holdNext {
            holdNext = false
            func store(_ continuation: CheckedContinuation<Void, Never>) {
                held = continuation
            }
            await withCheckedContinuation(store)
        }
        let answer = answers.isEmpty ? JessResult.cutOff(transcript: transcript) : answers.removeFirst()
        if case .done = answer {
            onApplied(answer)
        }
        return answer
    }
}

private final class DeletePendingAPI: JessPendingAPI, @unchecked Sendable {
    let items: [JessPendingItem]
    private let lock = NSLock()
    private var shownIds: [String] = []

    init(items: [JessPendingItem]) {
        self.items = items
    }

    var shown: [String] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return shownIds
    }

    func pending() async -> [JessPendingItem]? {
        items
    }

    func markShown(id: String) async {
        lock.withLock {
            shownIds.append(id)
        }
    }
}

private func deleteResultsFileURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "workdesk-delete-\(UUID().uuidString)/results.json")
}

@MainActor
private func deleteResults(route: DeleteRoute, fileURL: URL) -> JessResults {
    func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        await route.route(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone, onApplied: onApplied)
    }
    func isSignedIn() -> Bool {
        true
    }
    func isInForeground() -> Bool {
        false
    }
    func now() -> Date {
        deleteSaidTime
    }
    func timeZone() -> TimeZone {
        TimeZone(identifier: "America/Los_Angeles")!
    }
    var dependencies = JessResultsDependencies(route: routeCall, backgroundTime: DeleteBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    dependencies.foregroundRetryDelay = nil
    return JessResults(file: JessResultsFile(fileURL: fileURL), dependencies: dependencies)
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<300 {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
final class WorkdeskDeleteStaysTests: XCTestCase {
    func testACardDeletedWhileWorkingStaysDeletedWhenItsAnswerComes() async {
        let route = DeleteRoute(answers: [.done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil)])
        route.holdNext = true
        let results = deleteResults(route: route, fileURL: deleteResultsFileURL())
        let submitting = Task { @MainActor in
            await results.submit(transcript: "add milk", listenMs: 900)
        }
        await waitUntil { route.isHolding }
        XCTAssertEqual(results.log.first?.kind, .working, "the card shows working while the answer is on its way")
        let cardId = results.log[0].id

        results.removeFromLog(cardId: cardId)
        route.release()
        _ = await submitting.value

        XCTAssertTrue(results.log.isEmpty, "the deleted card does not come back on the Workdesk")
        XCTAssertTrue(results.cards.isEmpty, "nor on home")
        XCTAssertTrue(results.pendingRequests.isEmpty, "the request itself still finished")
    }

    func testACardDeletedWhileWaitingForConnectionStaysDeletedWhenItIsSentAgain() async {
        let route = DeleteRoute(answers: [.cutOff(transcript: "add eggs"), .done(text: "Added Eggs", at: nil, allDay: nil, timeZone: nil)])
        let results = deleteResults(route: route, fileURL: deleteResultsFileURL())
        await results.submit(transcript: "add eggs", listenMs: 900)
        XCTAssertEqual(results.log.first?.kind, .waitingForConnection)
        let cardId = results.log[0].id

        results.removeFromLog(cardId: cardId)
        await results.resume()

        XCTAssertEqual(route.callCount, 2, "the request was sent again")
        XCTAssertTrue(results.log.isEmpty)
        XCTAssertTrue(results.cards.isEmpty)
        XCTAssertTrue(results.pendingRequests.isEmpty)
    }

    func testADeletedCardStaysDeletedAfterMidasIsOpenedAgain() async {
        let fileURL = deleteResultsFileURL()
        let firstRoute = DeleteRoute(answers: [.cutOff(transcript: "add bread")])
        let first = deleteResults(route: firstRoute, fileURL: fileURL)
        await first.submit(transcript: "add bread", listenMs: 900)
        first.removeFromLog(cardId: first.log[0].id)

        let secondRoute = DeleteRoute(answers: [.done(text: "Added Bread", at: nil, allDay: nil, timeZone: nil)])
        let reopened = deleteResults(route: secondRoute, fileURL: fileURL)
        XCTAssertEqual(reopened.pendingRequests.count, 1, "the unfinished request was kept on disk")
        await reopened.resume()

        XCTAssertEqual(secondRoute.callCount, 1)
        XCTAssertTrue(reopened.log.isEmpty, "the delete is kept on disk with the request")
        XCTAssertTrue(reopened.cards.isEmpty)
        XCTAssertTrue(reopened.pendingRequests.isEmpty)
    }

    func testAnEditCardDeletedWhileWaitingStaysDeletedWhenTheGrowResultComes() async {
        let growLink = JessRepairLink(reportId: "r1", pendingId: "p1")
        let route = DeleteRoute(answers: [.sentToRepair(sidekickName: "Reminders", link: growLink)])
        let results = deleteResults(route: route, fileURL: deleteResultsFileURL())
        await results.submit(transcript: "remind me every 4 hours", listenMs: 900)
        results.removeFromLog(cardId: results.log[0].id)
        let doneItem = JessPendingItem(id: "p1", sidekickId: "reminders", state: "done", text: "Added Ibuprofen", transcript: "remind me every 4 hours")
        let failedItem = JessPendingItem(id: "p2", sidekickId: "reminders", state: "failed", text: nil, transcript: "something else")
        let api = DeletePendingAPI(items: [doneItem, failedItem])
        let followUp = JessGrowFollowUp(api: api, present: results.present)
        followUp.settle = results.settleGrow

        await followUp.check()

        XCTAssertEqual(api.shown, ["p1", "p2"], "both results are marked shown on the server")
        XCTAssertEqual(results.log.count, 1, "only the result no deleted card waited on shows")
        XCTAssertEqual(results.log.first?.kind, .notDone)
        XCTAssertEqual(results.log.first?.transcript, "something else")
    }

    func testACardNotDeletedStillShowsItsAnswer() async {
        let route = DeleteRoute(answers: [.done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil), .done(text: "Added Eggs", at: nil, allDay: nil, timeZone: nil)])
        let results = deleteResults(route: route, fileURL: deleteResultsFileURL())
        await results.submit(transcript: "add milk", listenMs: 900)
        results.removeFromLog(cardId: results.log[0].id)
        await results.submit(transcript: "add eggs", listenMs: 900)

        XCTAssertEqual(results.log.count, 1)
        XCTAssertEqual(results.log.first?.kind, .done(text: "Added Eggs", at: nil, allDay: false, timeZone: nil))
    }
}
