import SwiftUI
import XCTest
@testable import Midas

// jess queue, instant acknowledgement and the Workdesk (founder, 2026-10-22; docs/PRODUCT.md
// section of that name; midas-intel docs/plans/2026-10-22-jess-workdesk-brief.md; mockup
// docs/mockups/jess-workdesk-2026-10-22.html):
// - exactly once through a queue: every send carries the request's id (the server keeps its answer
//   under it); a request with no answer (cut off) stays queued, waiting for a connection, and is
//   sent again under the same id; after 1 hour it gives up as Not Done; Try Again uses a new id;
// - a request sent to repair waits on its card; the grow's result or the repair's done notice
//   settles that same card and moves it to the top;
// - the Workdesk: a log of every task (the last 200), apart from the home cards; the stack's slots,
//   scroll and words; the screen stays open after a request with Cancel before words and Done
//   after; no glow on the orb's thinking arc.

private let workdeskRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let workdeskZone = TimeZone(identifier: "America/Los_Angeles")!
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
private let workdeskSaidTime = ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!

@MainActor
private func waitUntilTrue(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private func workdeskResultsFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "jess-workdesk-\(UUID().uuidString)/results.json")
}

/// iOS background time that never ends early.
@MainActor
private final class EndlessBackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

/// Stands in for JessRouter.route: answers from a list and keeps the request id each send carried.
/// It names the Sidekick through the route context, as the router does.
@MainActor
private final class QueueRoute {
    var answers: [JessResult]
    var sidekickName: String?
    private(set) var sentRequestIds: [String?] = []
    private(set) var applied = 0

    init(answers: [JessResult]) {
        self.answers = answers
    }

    func route(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        sentRequestIds.append(JessRouteContext.current?.requestId)
        if let sidekickName {
            JessRouteContext.current?.sidekickName = sidekickName
        }
        let answer = answers.isEmpty ? JessResult.cutOff(transcript: transcript) : answers.removeFirst()
        if case .done = answer {
            applied += 1
            onApplied(answer)
        }
        return answer
    }
}

@MainActor
private final class QueueSurroundings {
    var now = workdeskSaidTime
    var inForeground = false
}

@MainActor
private func makeQueue(file: URL = workdeskResultsFile(), route: QueueRoute, surroundings: QueueSurroundings = QueueSurroundings(), retryDelay: Duration? = nil) -> JessResults {
    func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        await route.route(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone, onApplied: onApplied)
    }
    func isSignedIn() -> Bool {
        true
    }
    func isInForeground() -> Bool {
        surroundings.inForeground
    }
    func now() -> Date {
        surroundings.now
    }
    func timeZone() -> TimeZone {
        workdeskZone
    }
    var dependencies = JessResultsDependencies(route: routeCall, backgroundTime: EndlessBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    dependencies.foregroundRetryDelay = retryDelay
    return JessResults(file: JessResultsFile(fileURL: file), dependencies: dependencies)
}

private let addedMilk = JessResult.done(text: "Added Milk", at: nil, allDay: nil, timeZone: "America/Los_Angeles")
private let addedMilkKind = JessResultCard.Kind.done(text: "Added Milk", at: nil, allDay: false, timeZone: "America/Los_Angeles")

// MARK: - The queue

@MainActor
final class JessQueueTests: XCTestCase {
    func testACutOffRequestWaitsForAConnectionAndIsSentAgainUnderTheSameId() async {
        let file = workdeskResultsFile()
        let route = QueueRoute(answers: [.cutOff(transcript: "add milk")])
        let results = makeQueue(file: file, route: route)
        await results.submit(transcript: "add milk", listenMs: 900)

        XCTAssertEqual(results.cards.first?.kind, .waitingForConnection, "not Not Done")
        XCTAssertEqual(results.pendingRequests.count, 1, "still queued on disk")
        XCTAssertEqual(VoiceReminderCopy.cardTitle(results.cards[0]), "Waiting for Connection")
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(results.log[0]), "Waiting for Connection")
        let firstId = try? XCTUnwrap(route.sentRequestIds.first ?? nil)
        XCTAssertEqual(firstId, results.pendingRequests[0].id.uuidString.lowercased())

        // The next open: sent again, under the same id, and finished
        route.answers = [addedMilk]
        let reopened = makeQueue(file: file, route: route)
        XCTAssertEqual(reopened.cards.first?.kind, .waitingForConnection, "the wait is kept on disk")
        await reopened.resume()
        XCTAssertEqual(route.sentRequestIds.count, 2)
        XCTAssertEqual(route.sentRequestIds[1], firstId, "the server dedupes on this id")
        XCTAssertEqual(reopened.cards.first?.kind, addedMilkKind)
        XCTAssertTrue(reopened.pendingRequests.isEmpty)
        XCTAssertEqual(route.applied, 1)
    }

    func testACutOffRequestGivesUpAsNotDoneAfterOneHour() async {
        let surroundings = QueueSurroundings()
        let route = QueueRoute(answers: [.cutOff(transcript: "add milk"), .cutOff(transcript: "add milk")])
        let results = makeQueue(route: route, surroundings: surroundings)
        await results.submit(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(results.cards.first?.kind, .waitingForConnection)

        // 59 minutes later still waiting; 60 minutes later Not Done with Try Again
        surroundings.now = workdeskSaidTime.addingTimeInterval(59 * 60)
        route.answers = [.cutOff(transcript: "add milk")]
        await results.resume()
        XCTAssertEqual(results.cards.first?.kind, .waitingForConnection)
        surroundings.now = workdeskSaidTime.addingTimeInterval(60 * 60)
        route.answers = [.cutOff(transcript: "add milk")]
        await results.resume()
        XCTAssertEqual(results.cards.first?.kind, .notDone)
        XCTAssertEqual(VoiceReminderCopy.cardActionTitle(results.cards[0]), "Try Again")
        XCTAssertTrue(results.pendingRequests.isEmpty)
    }

    func testAWaitingCardCannotBeDismissed() async {
        let route = QueueRoute(answers: [.cutOff(transcript: "add milk")])
        let results = makeQueue(route: route)
        await results.submit(transcript: "add milk", listenMs: 900)
        results.dismiss(cardId: results.cards[0].id)
        XCTAssertEqual(results.cards.count, 1)
    }

    func testOnScreenACutOffRequestIsSentAgainByItself() async {
        let surroundings = QueueSurroundings()
        surroundings.inForeground = true
        let route = QueueRoute(answers: [.cutOff(transcript: "add milk"), addedMilk])
        let results = makeQueue(route: route, surroundings: surroundings, retryDelay: .milliseconds(50))
        await results.submit(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(results.cards.first?.kind, .waitingForConnection)
        await waitUntilTrue { results.cards.first?.kind == addedMilkKind }
        XCTAssertEqual(results.cards.first?.kind, addedMilkKind)
        XCTAssertEqual(route.sentRequestIds.count, 2)
    }

    func testTryAgainSendsUnderANewIdSoTheServerRunsItAgain() async {
        let route = QueueRoute(answers: [.notDone(transcript: "move dentist to friday"), .done(text: "Moved Dentist", at: nil, allDay: nil, timeZone: nil)])
        let results = makeQueue(route: route)
        await results.submit(transcript: "move dentist to friday", listenMs: 900)
        let cardId = results.cards[0].id
        results.retry(cardId: cardId)
        await waitUntilTrue { route.sentRequestIds.count == 2 && results.cards.first?.kind != .working }
        XCTAssertEqual(route.sentRequestIds.count, 2)
        XCTAssertNotNil(route.sentRequestIds[1] ?? nil)
        XCTAssertNotEqual(route.sentRequestIds[0], route.sentRequestIds[1])
        XCTAssertEqual(results.cards.first?.id, cardId)
    }

    func testTryAgainWorksFromTheWorkdeskAfterTheHomeCardWasDismissed() async {
        let route = QueueRoute(answers: [.notDone(transcript: "move dentist to friday"), .done(text: "Moved Dentist", at: nil, allDay: nil, timeZone: nil)])
        let results = makeQueue(route: route)
        await results.submit(transcript: "move dentist to friday", listenMs: 900)
        let cardId = results.cards[0].id
        results.dismiss(cardId: cardId)
        XCTAssertTrue(results.cards.isEmpty)
        results.retry(cardId: cardId)
        await waitUntilTrue { results.log.first?.kind == .done(text: "Moved Dentist", at: nil, allDay: false, timeZone: nil) }
        XCTAssertEqual(results.log.first?.id, cardId)
        XCTAssertEqual(results.log.count, 1)
    }

    func testTheRouterTurnsNoAnswerAndAnUnreachableModelIntoCutOffAndPassesTheRequestId() async throws {
        let api = WorkdeskScriptedAPI(answers: [.unreachable, .notDone(reason: "model-error"), .notDone(reason: "question")])
        let router = try makeWorkdeskRouter(api: api)
        let context = JessRouteContext(requestId: "0f6c9a52-6b1e-4f43-9a0c-2d7b8e51c3aa")
        func routeOffline() async -> JessResult {
            await router.route(transcript: "add milk", listenMs: 900)
        }
        let offline = await JessRouteContext.$current.withValue(context, operation: routeOffline)
        let modelDown = await router.route(transcript: "add milk", listenMs: 900)
        let question = await router.route(transcript: "what's the weather", listenMs: 900)
        XCTAssertEqual(offline, .cutOff(transcript: "add milk"))
        XCTAssertEqual(modelDown, .cutOff(transcript: "add milk"))
        XCTAssertEqual(question, .notDone(transcript: "what's the weather"))
        XCTAssertEqual(api.requests[0].requestId, "0f6c9a52-6b1e-4f43-9a0c-2d7b8e51c3aa")
        XCTAssertNil(api.requests[1].requestId, "outside the queue no id is sent")
    }

    func testTheRequestIdIsSentOnlyWhenSetAndTheClientWaitsLongerThanTheServer() throws {
        let app = VoiceParseApp(version: "0.1.0", build: "6", ios: "26.1", device: "iPhone17,1")
        var request = JessRouteRequest(transcript: "add milk", now: "2026-10-20T17:00:00.000Z", timeZone: "America/Los_Angeles", locale: "en-US", sidekicks: [], app: app, listenMs: 900)
        let withoutId = try XCTUnwrap(String(data: try JSONEncoder().encode(request), encoding: .utf8))
        XCTAssertFalse(withoutId.contains("requestId"))
        request.requestId = "abc"
        let withId = try XCTUnwrap(String(data: try JSONEncoder().encode(request), encoding: .utf8))
        XCTAssertTrue(withId.contains(#""requestId":"abc""#))
        // The server tries the model twice for 8 s each
        XCTAssertGreaterThan(RemoteJessRouter.requestTimeout, 16)
    }

    func testTheServersBusyAnswerIsNoAnswerAndRepairRepliesCarryTheirLinks() {
        func reply(_ statusCode: Int, _ body: String) -> JessRouteReply {
            RemoteJessRouter.reply(statusCode: statusCode, data: Data(body.utf8))
        }
        XCTAssertEqual(reply(409, #"{"error":"busy"}"#), .unreachable)
        XCTAssertEqual(reply(200, #"{"status":"repair","sidekickId":"reminders","reportId":"r1","logId":"l1"}"#), .repair(sidekickId: "reminders", logId: "l1", reportId: "r1"))
        XCTAssertEqual(reply(200, #"{"status":"grow","sidekickId":"reminders","reportId":"r2","pendingId":"p2","logId":"l2"}"#), .grow(sidekickId: "reminders", logId: "l2", reportId: "r2", pendingId: "p2"))
    }
}

// MARK: - Waiting on a repair

@MainActor
final class JessRepairWaitTests: XCTestCase {
    func testTheRouterLinksARepairAndAGrowToWhatTheyWaitFor() async throws {
        let api = WorkdeskScriptedAPI(answers: [.repair(sidekickId: "reminders", logId: "l1", reportId: "r1"), .grow(sidekickId: "reminders", logId: "l2", reportId: "r2", pendingId: "p2"), .repair(sidekickId: "reminders", logId: "l3")])
        let router = try makeWorkdeskRouter(api: api)
        let repair = await router.route(transcript: "make the circles bigger", listenMs: 900)
        let grow = await router.route(transcript: "add call the bank and flag it", listenMs: 900)
        let olderServer = await router.route(transcript: "make it blue", listenMs: 900)
        XCTAssertEqual(repair, .sentToRepair(sidekickName: "Reminders", link: JessRepairLink(reportId: "r1", pendingId: nil)))
        XCTAssertEqual(grow, .sentToRepair(sidekickName: "Reminders", link: JessRepairLink(reportId: "r2", pendingId: "p2")))
        XCTAssertEqual(olderServer, .sentToRepair(sidekickName: "Reminders"))
    }

    func testAGrowsResultSettlesTheSameCardAndMovesItToTheTop() async {
        let link = JessRepairLink(reportId: "r2", pendingId: "p2")
        let route = QueueRoute(answers: [.sentToRepair(sidekickName: "Reminders", link: link), addedMilk])
        let results = makeQueue(route: route)
        await results.submit(transcript: "add call the bank and flag it", listenMs: 900)
        let waitingId = results.cards[0].id
        XCTAssertEqual(results.log[0].workdeskOrbState, .idle, "grey while the repair is not live")
        await results.submit(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(results.log[0].kind, addedMilkKind)

        let backendDone = JessResult.done(text: "Added Call the bank", at: nil, allDay: nil, timeZone: nil)
        XCTAssertFalse(results.settleGrow(pendingId: "someone-else", result: backendDone))
        XCTAssertTrue(results.settleGrow(pendingId: "p2", result: backendDone))
        XCTAssertEqual(results.cards[0].id, waitingId, "the same card, at the top")
        XCTAssertEqual(results.cards[0].kind, .done(text: "Added Call the bank", at: nil, allDay: false, timeZone: nil))
        XCTAssertEqual(results.log[0].id, waitingId)
        XCTAssertEqual(results.cards.count, 2, "no second card")
        XCTAssertEqual(results.log.count, 2)
    }

    func testTheGrowFollowUpPresentsOnlyWhatNoCardWaitedOn() async {
        let api = TwoPendingAPI()
        var presented: [JessResult] = []
        func present(_ result: JessResult) {
            presented.append(result)
        }
        func settle(pendingId: String, result: JessResult) -> Bool {
            pendingId == "p1"
        }
        let followUp = JessGrowFollowUp(api: api, present: present)
        followUp.settle = settle
        await followUp.check()
        XCTAssertEqual(presented, [.notDone(transcript: "share my groceries list with Sam")])
        XCTAssertEqual(api.shown, ["p1", "p2"])
        let services = try? String(contentsOf: workdeskRepoRoot.appending(path: "shell/Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertEqual(services?.contains("jessGrowFollowUp.settle = jessResults.settleGrow"), true)
    }

    func testARepairsDoneNoticeTurnsItsWaitingCardDoneAndOnlyThatNoticeIsMarkedSeen() async {
        let link = JessRepairLink(reportId: "r1", pendingId: nil)
        let route = QueueRoute(answers: [.sentToRepair(sidekickName: "Reminders", link: link)])
        let results = makeQueue(route: route)
        await results.submit(transcript: "make the circles bigger", listenMs: 900)
        XCTAssertEqual(results.waitingReportIds, ["r1"])
        let notices = StubNotices(notices: [JessRepairNotice(id: "n9", reportId: "r9", text: "The update you requested is done."), JessRepairNotice(id: "n1", reportId: "r1", text: "The update you requested is done.")])
        let followUp = JessRepairFollowUp(api: notices, results: results)
        await followUp.check()
        XCTAssertEqual(results.cards[0].kind, .done(text: "Make the circles bigger", at: nil, allDay: false, timeZone: nil))
        XCTAssertEqual(results.log[0].workdeskOrbState, .added)
        XCTAssertEqual(notices.seen, ["n1"])
        XCTAssertTrue(results.waitingReportIds.isEmpty)
        // Nothing waits any more: the server is not asked again
        await followUp.check()
        XCTAssertEqual(notices.asked, 1)
        let app = try? String(contentsOf: workdeskRepoRoot.appending(path: "shell/Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertEqual(app?.contains("await ShellServices.shared.jessRepairFollowUp.check()"), true)
    }

    func testTheNoticesAnswerIsRead() {
        let body = #"{"notices":[{"id":"n1","reportId":"r1","sidekickId":"reminders","text":"The update you requested is done.","createdAt":"2026-10-22T00:00:00Z"}]}"#
        XCTAssertEqual(RemoteJessRepairNotices.notices(statusCode: 200, data: Data(body.utf8)), [JessRepairNotice(id: "n1", reportId: "r1", text: "The update you requested is done.")])
        XCTAssertNil(RemoteJessRepairNotices.notices(statusCode: 401, data: Data()))
    }
}

// MARK: - The Workdesk log

@MainActor
final class JessWorkdeskLogTests: XCTestCase {
    func testDismissingAHomeCardKeepsTheTaskOnTheWorkdeskWithItsSidekick() async {
        let route = QueueRoute(answers: [addedMilk])
        route.sidekickName = "Groceries"
        let results = makeQueue(route: route)
        await results.submit(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(results.log.first?.sidekickName, "Groceries")
        results.dismiss(cardId: results.cards[0].id)
        XCTAssertTrue(results.cards.isEmpty)
        XCTAssertEqual(results.log.count, 1)
        XCTAssertEqual(VoiceReminderCopy.workdeskLine(results.log[0]), "Added Milk")
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(results.log[0]), "Groceries")
    }

    func testTheLogKeepsTheLast200NewestFirstAndSurvivesAReopen() {
        let file = workdeskResultsFile()
        let results = makeQueue(file: file, route: QueueRoute(answers: []))
        for number in 1...205 {
            results.present(.done(text: "Added \(number)", at: nil, allDay: nil, timeZone: nil))
        }
        XCTAssertEqual(results.log.count, 200)
        XCTAssertEqual(results.log.first?.kind, .done(text: "Added 205", at: nil, allDay: false, timeZone: nil))
        XCTAssertEqual(results.log.last?.kind, .done(text: "Added 6", at: nil, allDay: false, timeZone: nil))
        let reopened = makeQueue(file: file, route: QueueRoute(answers: []))
        XCTAssertEqual(reopened.log, results.log)
    }

    func testAFileFromBeforeTheWorkdeskStartsTheLogFromItsCards() throws {
        let file = workdeskResultsFile()
        let card = JessResultCard(id: UUID(), kind: .notDone, transcript: "move dentist", createdAt: workdeskSaidTime)
        let encodedCards = try JSONEncoder().encode([card])
        let cardsText = try XCTUnwrap(String(data: encodedCards, encoding: .utf8))
        let oldFile = #"{"cards":"# + cardsText + #","requests":[]}"#
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(oldFile.utf8).write(to: file)
        let results = makeQueue(file: file, route: QueueRoute(answers: []))
        XCTAssertEqual(results.cards, [card], "the old cards are kept")
        XCTAssertEqual(results.log, [card])
    }
}

// MARK: - The Workdesk screen

@MainActor
final class JessWorkdeskScreenTests: XCTestCase {
    func testTheSlotsMatchTheMockup() {
        XCTAssertEqual(JessWorkdeskLayout.slot(at: 0), JessWorkdeskLayout.slots[0])
        XCTAssertEqual(JessWorkdeskLayout.slot(at: 2), JessWorkdeskLayout.slots[2])
        XCTAssertEqual(JessWorkdeskLayout.slot(at: -1), JessWorkdeskLayout.exit)
        XCTAssertEqual(JessWorkdeskLayout.slot(at: 9), JessWorkdeskLayout.slots[5])
        let halfway = JessWorkdeskLayout.slot(at: 0.5)
        XCTAssertEqual(halfway.top, 83, accuracy: 0.001)
        XCTAssertEqual(halfway.height, 110, accuracy: 0.001)
        XCTAssertEqual(JessWorkdeskLayout.slots[0].height, 156)
        XCTAssertEqual(JessWorkdeskLayout.slots[1].height, JessWorkdeskLayout.slots[2].height, "slim cards are one size")
        XCTAssertEqual(JessWorkdeskLayout.slots[3].content, 0, "tucked cards show only their edges")
        // The big and slim words never show together
        XCTAssertEqual(JessWorkdeskLayout.bigLookOpacity(halfway), 0)
        XCTAssertEqual(JessWorkdeskLayout.slimLookOpacity(halfway), 0)
        XCTAssertEqual(JessWorkdeskLayout.bigLookOpacity(JessWorkdeskLayout.slots[0]), 1)
        XCTAssertEqual(JessWorkdeskLayout.slimLookOpacity(JessWorkdeskLayout.slots[1]), 1)
    }

    func testTheStackMovesOneCardPerFingerStepAndSnapsToACard() {
        XCTAssertEqual(JessWorkdeskLayout.draggedScroll(startScroll: 0, translation: -110, cardCount: 5), 1, accuracy: 0.001)
        // Past the newest card it moves a third as far
        XCTAssertEqual(JessWorkdeskLayout.draggedScroll(startScroll: 0, translation: 110, cardCount: 5), -1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(JessWorkdeskLayout.draggedScroll(startScroll: 4, translation: -110, cardCount: 5), 4 + 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(JessWorkdeskLayout.settledScroll(startScroll: 0, predictedTranslation: -160, cardCount: 5), 1)
        XCTAssertEqual(JessWorkdeskLayout.settledScroll(startScroll: 0, predictedTranslation: -2000, cardCount: 5), 4)
        XCTAssertEqual(JessWorkdeskLayout.settledScroll(startScroll: 1, predictedTranslation: 900, cardCount: 5), 0)
    }

    func testTheCardWordsSayTheTaskAndOnlyTheSidekick() {
        var working = JessResultCard(id: UUID(), kind: .working, transcript: "water the ferns every 3 weeks", createdAt: workdeskSaidTime)
        XCTAssertEqual(VoiceReminderCopy.workdeskLine(working), "“water the ferns every 3 weeks”")
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(working), "On It")
        working.kind = .waitingForConnection
        XCTAssertEqual(VoiceReminderCopy.workdeskLine(working), "Water the ferns every 3 weeks")
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(working), "Waiting for Connection")
        let repair = JessResultCard(id: UUID(), kind: .sentToRepair(sidekickName: "Care", link: JessRepairLink(reportId: "r1", pendingId: nil)), transcript: "water the ferns every 3 weeks", createdAt: workdeskSaidTime)
        XCTAssertEqual(VoiceReminderCopy.workdeskLine(repair), "Water the ferns every 3 weeks")
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(repair), "Care")
        XCTAssertEqual(repair.workdeskOrbState, .idle)
        XCTAssertEqual(repair.orbState, .added, "the home card is unchanged")
        let notDone = JessResultCard(id: UUID(), kind: .notDone, transcript: "move dentist to friday", createdAt: workdeskSaidTime, sidekickName: "Reminders")
        XCTAssertEqual(VoiceReminderCopy.workdeskLine(notDone), "Move dentist to friday")
        XCTAssertEqual(VoiceReminderCopy.workdeskMeta(notDone), "Reminders")
        XCTAssertEqual(VoiceReminderCopy.cardActionTitle(notDone), "Try Again")
    }

    func testTheScreenStaysOpenAfterARequestWithCancelBeforeWordsAndDoneAfter() async {
        let harness = WorkdeskFlowHarness()
        harness.flow.request()
        XCTAssertEqual(harness.opened, 1, "opening the screen sends a waiting request again")
        await harness.flow.startListening()
        XCTAssertEqual(harness.flow.buttonTitle, "Cancel")
        harness.transcriber.say("add milk")
        XCTAssertEqual(harness.flow.buttonTitle, "Done")
        harness.transcriber.end(.silence)
        await waitUntilTrue { harness.flow.phase == .ready }
        XCTAssertEqual(harness.flow.phase, .ready)
        XCTAssertTrue(harness.flow.isPresented)
        XCTAssertEqual(harness.flow.buttonTitle, "Done")
        XCTAssertEqual(harness.routed, ["add milk"])

        // Tapping the orb listens again; saying nothing returns to the Workdesk
        await harness.flow.listenAgain()
        XCTAssertEqual(harness.flow.phase, .listening)
        harness.transcriber.end(.silence)
        XCTAssertEqual(harness.flow.phase, .ready)
        XCTAssertTrue(harness.flow.isPresented)
        harness.flow.cancel()
        XCTAssertFalse(harness.flow.isPresented)
    }

    func testTheWorkdeskRendersInBothModes() async {
        let route = QueueRoute(answers: [addedMilk, .notDone(transcript: "move dentist"), .cutOff(transcript: "add eggs")])
        let results = makeQueue(route: route)
        await results.submit(transcript: "add milk", listenMs: 900)
        await results.submit(transcript: "move dentist", listenMs: 900)
        await results.submit(transcript: "add eggs", listenMs: 900)
        let harness = WorkdeskFlowHarness()
        harness.flow.request()
        for scheme in [ColorScheme.light, .dark] {
            let view = VoiceCaptureView(flow: harness.flow, results: results).frame(width: 402, height: 874).environment(\.colorScheme, scheme)
            XCTAssertNotNil(ImageRenderer(content: view).uiImage, "\(scheme)")
        }
        XCTAssertGreaterThan(VoiceCaptureView.riseFromOrb(height: 874), 400, "the card starts at the orb, far below the stack")
    }

    func testTheThinkingArcHasNoGlow() throws {
        let orb = try String(contentsOf: workdeskRepoRoot.appending(path: "shell/Midas/JessOrb.swift"), encoding: .utf8)
        XCTAssertFalse(orb.contains("palette.arcGlow.color"))
        XCTAssertTrue(orb.contains("context.stroke(arcPath"))
    }

    func testTheNetworkComingBackSendsWaitingRequestsAgain() {
        var calls = 0
        func back() {
            calls += 1
        }
        let watch = JessNetworkWatch(onBack: back)
        watch.connectionChanged(isConnected: true)
        XCTAssertEqual(calls, 0, "connected at start is not a change")
        watch.connectionChanged(isConnected: false)
        watch.connectionChanged(isConnected: true)
        watch.connectionChanged(isConnected: true)
        XCTAssertEqual(calls, 1)
        let services = try? String(contentsOf: workdeskRepoRoot.appending(path: "shell/Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertEqual(services?.contains("JessNetworkWatch(onBack: resumeJessQueue)"), true)
        XCTAssertEqual(services?.contains("voiceDependencies.opened = resumeJessQueue"), true)
    }
}

// MARK: - Stand-ins

private final class WorkdeskScriptedAPI: JessRouting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [JessRouteReply]
    private var sentRequests: [JessRouteRequest] = []

    init(answers: [JessRouteReply]) {
        self.answers = answers
    }

    var requests: [JessRouteRequest] {
        lock.withLock { sentRequests }
    }

    func route(_ request: JessRouteRequest) async -> JessRouteReply {
        lock.withLock {
            sentRequests.append(request)
            return answers.isEmpty ? .unreachable : answers.removeFirst()
        }
    }

    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async {}
}

@MainActor
private func makeWorkdeskRouter(api: WorkdeskScriptedAPI) throws -> JessRouter {
    let manifestText = try String(contentsOf: workdeskRepoRoot.appending(path: "sidekicks/reminders/manifest.json"), encoding: .utf8)
    let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(manifestText.utf8))
    let agent = try XCTUnwrap(manifest["agent"])
    let toolsSource = try String(contentsOf: workdeskRepoRoot.appending(path: "sidekicks/reminders/tools.js"), encoding: .utf8)
    func sidekicks() -> [JessSidekickSource] {
        [JessSidekickSource(id: "reminders", name: "Reminders", version: "v5", agent: agent)]
    }
    func engine(sidekickId: String, version: String) async throws -> SidekickToolsEngine {
        try SidekickToolsEngine(source: toolsSource)
    }
    func records(sidekickId: String) -> [LocalRecord] {
        []
    }
    func apply(sidekickId: String, ops: [SidekickToolOp]) throws {}
    func now() -> Date {
        workdeskSaidTime
    }
    func timeZone() -> TimeZone {
        workdeskZone
    }
    func app() -> VoiceParseApp {
        VoiceParseApp(version: "0.1.0", build: "6", ios: "26.1", device: "iPhone17,1")
    }
    return JessRouter(dependencies: JessRouterDependencies(sidekicks: sidekicks, engine: engine, records: records, apply: apply, api: api, now: now, timeZone: timeZone, app: app))
}

private final class TwoPendingAPI: JessPendingAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var shownIds: [String] = []

    var shown: [String] {
        lock.withLock { shownIds }
    }

    func pending() async -> [JessPendingItem]? {
        [
            JessPendingItem(id: "p1", sidekickId: "reminders", state: "done", text: "Added Call the bank", transcript: "add call the bank and flag it"),
            JessPendingItem(id: "p2", sidekickId: "reminders", state: "failed", text: nil, transcript: "share my groceries list with Sam"),
        ]
    }

    func markShown(id: String) async {
        lock.withLock {
            shownIds.append(id)
        }
    }
}

private final class StubNotices: JessRepairNoticesAPI, @unchecked Sendable {
    private let lock = NSLock()
    private let list: [JessRepairNotice]
    private var seenIds: [String] = []
    private var askedCount = 0

    init(notices: [JessRepairNotice]) {
        self.list = notices
    }

    var seen: [String] {
        lock.withLock { seenIds }
    }

    var asked: Int {
        lock.withLock { askedCount }
    }

    func notices() async -> [JessRepairNotice]? {
        lock.withLock {
            askedCount += 1
            return list
        }
    }

    func markSeen(id: String) async {
        lock.withLock {
            seenIds.append(id)
        }
    }
}

/// Stands in for the shared transcriber.
@MainActor
private final class WorkdeskWords: VoiceTranscribing {
    var onUpdate: (@MainActor (VoiceTranscript) -> Void)?
    var onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        self.onUpdate = onUpdate
        self.onEnd = onEnd
    }

    func stop() {
        end(.stopped)
    }

    func say(_ text: String) {
        onUpdate?(VoiceTranscript(text: text, words: []))
    }

    func end(_ reason: VoiceTranscriptionEnd) {
        let endHandler = onEnd
        onEnd = nil
        onUpdate = nil
        endHandler?(reason)
    }
}

private final class UnusedParser: VoiceReminderParsing, @unchecked Sendable {
    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        .unreachable
    }
}

/// The jess screen's flow with a router that records what was said.
@MainActor
private final class WorkdeskFlowHarness {
    let transcriber = WorkdeskWords()
    var routed: [String] = []
    var opened = 0
    private(set) var flow: VoiceReminderFlow!

    init() {
        func isSignedIn() -> Bool {
            true
        }
        func lists() -> [VoiceReminderList] {
            []
        }
        let words = transcriber
        func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing {
            words
        }
        func save(_ reminder: VoiceResolvedReminder) throws {}
        func now() -> Date {
            workdeskSaidTime
        }
        func timeZone() -> TimeZone {
            workdeskZone
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "6", ios: "26.1", device: "iPhone17,1")
        }
        var dependencies = VoiceReminderDependencies(isSignedIn: isSignedIn, lists: lists, makeTranscriber: makeTranscriber, api: UnusedParser(), save: save, now: now, timeZone: timeZone, app: app)
        dependencies.route = routeSaid
        dependencies.opened = screenOpened
        flow = VoiceReminderFlow(dependencies: dependencies)
    }

    private func routeSaid(transcript: String, listenMs: Int) async {
        routed.append(transcript)
    }

    private func screenOpened() {
        opened += 1
    }
}
