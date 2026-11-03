import SwiftUI
import XCTest
@testable import Midas

// Build 22 feedback (founder, 2026-11-02, TestFlight on Midas Test; mockup
// docs/mockups/build22-feedback-2026-11-02.html):
// 1. The consent screen is "Third-Party Services" / "Midas uses third-party services." with Allow;
//    no feature or provider names (who gets what is on the Privacy Policy page).
// 2. The Settings switch was white on white in dark mode (ink is white there, as is iOS's knob):
//    dark mode's "on" is #6B6B6B (pick T2).
// 3. jess: tapping the orb while listening stops and sends what was heard; tapping again listens.
// 4. A Workdesk card swipes to show Delete, as the Reminders Sidekick's rows do; deleting a task
//    that has not finished stops it on the phone and tells the server to drop it.

private let feedbackSaidTime = Date(timeIntervalSince1970: 1_793_100_000)

private func feedbackShellRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

@MainActor
private func waitUntilTrue(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<300 {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - 1. Consent words

final class Build22FeedbackConsentTests: XCTestCase {
    func testTheConsentScreenSaysThirdPartyServicesAndNothingMore() {
        XCTAssertEqual(AIConsentCopy.title, "Third-Party Services")
        XCTAssertEqual(AIConsentCopy.line, "Midas uses third-party services.")
        XCTAssertEqual(AIConsentCopy.allow, "Allow")
        XCTAssertEqual(AIConsentCopy.notNow, "Not Now")
        XCTAssertEqual(AIConsentCopy.privacyPolicy, "Privacy Policy")
        XCTAssertEqual(AIConsentCopy.settingsSwitch, "Third-Party Services")
        let onScreen = [AIConsentCopy.title, AIConsentCopy.line, AIConsentCopy.settingsSwitch]
        let neverNamed = ["OpenRouter", "Anthropic", "jess", "Edit", "Screenshot", "Sidekick"]
        for words in onScreen {
            for name in neverNamed {
                XCTAssertFalse(words.contains(name), "\(name) is on the Privacy Policy page only: \(words)")
            }
        }
        XCTAssertTrue(AIConsentCopy.line.hasSuffix("."), "a sentence ends with a period")
        XCTAssertFalse(AIConsentCopy.title.hasSuffix("."))
    }

    func testTheConsentViewHasNoFeatureRows() throws {
        let source = try String(contentsOf: feedbackShellRoot().appending(path: "Midas/AIConsent.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("AIConsentRow"), "the jess and Edit rows are gone")
        XCTAssertFalse(source.contains("AIConsentChips"))
        XCTAssertTrue(source.contains("Text(AIConsentCopy.line)"))
    }
}

// MARK: - 2. The switch in dark mode

final class Build22FeedbackSwitchTests: XCTestCase {
    func testTheSwitchIsInkInLightAndGreyInDark() {
        XCTAssertEqual(ShellSwitchTint.forScheme(.light), RepairTokens.light.ink)
        XCTAssertEqual(ShellSwitchTint.forScheme(.dark), JessOrbColor(hex: 0x6B6B6B))
        XCTAssertNotEqual(ShellSwitchTint.forScheme(.dark), RepairTokens.dark.ink, "dark ink is white, like the knob: the bug")
        XCTAssertNotEqual(ShellSwitchTint.forScheme(.dark), JessOrbColor(hex: 0xFFFFFF))
    }

    func testSettingsUsesTheSwitchTint() throws {
        let source = try String(contentsOf: feedbackShellRoot().appending(path: "Midas/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(".tint(ShellSwitchTint.forScheme(colorScheme).color)"))
        XCTAssertFalse(source.contains(".tint(tokens.ink.color)"))
    }
}

// MARK: - 3. jess: tap to start, tap again to stop

@MainActor
private final class FeedbackTranscriber: VoiceTranscribing {
    var onUpdate: (@MainActor (VoiceTranscript) -> Void)?
    var onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        startCount += 1
        self.onUpdate = onUpdate
        self.onEnd = onEnd
    }

    func stop() {
        stopCount += 1
        let endHandler = onEnd
        onEnd = nil
        onUpdate = nil
        endHandler?(.stopped)
    }

    func say(_ text: String) {
        onUpdate?(VoiceTranscript(text: text, words: []))
    }
}

private struct UnusedParser: VoiceReminderParsing {
    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        .unreachable
    }
}

@MainActor
private final class ToggleHarness {
    let transcriber = FeedbackTranscriber()
    var routed: [String] = []
    private(set) var flow: VoiceReminderFlow!

    init() {
        flow = VoiceReminderFlow(dependencies: dependencies())
    }

    private func dependencies() -> VoiceReminderDependencies {
        func isSignedIn() -> Bool {
            true
        }
        func lists() -> [VoiceReminderList] {
            []
        }
        func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing {
            transcriber
        }
        func save(_ reminder: VoiceResolvedReminder) throws {}
        func now() -> Date {
            feedbackSaidTime
        }
        func timeZone() -> TimeZone {
            TimeZone(identifier: "America/Los_Angeles")!
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "22", ios: "26.1", device: "iPhone17,1")
        }
        func route(transcript: String, listenMs: Int) async {
            routed.append(transcript)
        }
        var dependencies = VoiceReminderDependencies(isSignedIn: isSignedIn, lists: lists, makeTranscriber: makeTranscriber, api: UnusedParser(), save: save, now: now, timeZone: timeZone, app: app)
        dependencies.route = route
        return dependencies
    }
}

@MainActor
final class Build22FeedbackJessToggleTests: XCTestCase {
    func testTappingWhileListeningStopsAndSendsWhatWasHeard() async {
        let harness = ToggleHarness()
        harness.flow.request()
        await harness.flow.startListening()
        harness.transcriber.say("remind me to call mom at 6")
        XCTAssertEqual(harness.flow.phase, .listening)
        XCTAssertTrue(harness.flow.orbTapWorks, "the orb answers a tap while listening")

        await harness.flow.orbTapped()
        await waitUntilTrue { harness.flow.phase == .ready }

        XCTAssertEqual(harness.transcriber.stopCount, 1, "the microphone stopped")
        XCTAssertEqual(harness.routed, ["remind me to call mom at 6"], "sent once, as heard")
        XCTAssertTrue(harness.flow.isPresented, "the Workdesk stays up")
    }

    func testTappingWithNothingHeardStopsAndSendsNothing() async {
        let harness = ToggleHarness()
        harness.flow.request()
        await harness.flow.startListening()

        await harness.flow.orbTapped()

        XCTAssertEqual(harness.transcriber.stopCount, 1)
        XCTAssertEqual(harness.flow.phase, .ready, "the orb is idle, ready to listen again")
        XCTAssertTrue(harness.flow.isPresented)
        XCTAssertTrue(harness.routed.isEmpty)
    }

    func testTappingAgainListensAgain() async {
        let harness = ToggleHarness()
        harness.flow.request()
        await harness.flow.startListening()
        await harness.flow.orbTapped()
        XCTAssertEqual(harness.flow.phase, .ready)

        await harness.flow.orbTapped()

        XCTAssertEqual(harness.flow.phase, .listening)
        XCTAssertEqual(harness.transcriber.startCount, 2)
    }

    func testTheOrbIsButtonedToTheToggle() throws {
        let source = try String(contentsOf: feedbackShellRoot().appending(path: "Midas/VoiceCaptureView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Button(action: orbTapped)"))
        XCTAssertTrue(source.contains(".disabled(!flow.orbTapWorks)"))
        XCTAssertFalse(source.contains(".disabled(flow.phase != .ready)"), "listening no longer disables the orb")
    }
}

// MARK: - 4a. Swipe to show Delete

final class Build22FeedbackSwipeRevealTests: XCTestCase {
    private let width: Double = 370

    func testAShortSwipeRestsOpenWithDeleteShowing() {
        let left = WorkdeskSwipeReveal.settle(startOffset: 0, translation: -70, predicted: -90, cardWidth: width)
        XCTAssertEqual(left, .open(offset: -WorkdeskSwipeReveal.buttonWidth))
        let right = WorkdeskSwipeReveal.settle(startOffset: 0, translation: 70, predicted: 90, cardWidth: width)
        XCTAssertEqual(right, .open(offset: WorkdeskSwipeReveal.buttonWidth), "either direction, as in Reminders")
    }

    func testATinySwipeOrAThrowBackCloses() {
        XCTAssertEqual(WorkdeskSwipeReveal.settle(startOffset: 0, translation: -20, predicted: -25, cardWidth: width), .closed)
        XCTAssertEqual(WorkdeskSwipeReveal.settle(startOffset: -84, translation: 60, predicted: 200, cardWidth: width), .closed, "thrown back shut")
        XCTAssertEqual(WorkdeskSwipeReveal.settle(startOffset: 0, translation: -60, predicted: 40, cardWidth: width), .closed)
    }

    func testSwipingMostOfTheWayDeletes() {
        XCTAssertEqual(WorkdeskSwipeReveal.settle(startOffset: 0, translation: -240, predicted: -260, cardWidth: width), .delete(direction: -1))
        XCTAssertEqual(WorkdeskSwipeReveal.settle(startOffset: -84, translation: -150, predicted: -150, cardWidth: width), .delete(direction: -1), "from open, on past")
        XCTAssertNotEqual(WorkdeskSwipeReveal.settle(startOffset: 0, translation: -150, predicted: -150, cardWidth: width), .delete(direction: -1), "past Delete but not most of the way")
    }

    func testTheCardFollowsTheFingerFromWhereItRests() {
        XCTAssertEqual(WorkdeskSwipeReveal.dragOffset(startOffset: -84, translation: -10, cardWidth: width), -94)
        XCTAssertEqual(WorkdeskSwipeReveal.dragOffset(startOffset: 0, translation: -900, cardWidth: width), -width, "never past the card's width")
    }

    func testTheWorkdeskUsesTheReveal() throws {
        let source = try String(contentsOf: feedbackShellRoot().appending(path: "Midas/JessWorkdeskView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("WorkdeskSwipeReveal.settle("))
        XCTAssertTrue(source.contains("deleteButton(for: entry.card"))
        XCTAssertFalse(source.contains("CardSwipeDelete.decision("), "the Workdesk no longer flings cards away")
    }
}

// MARK: - 4b. Deleting a task that has not finished stops it

@MainActor
private final class FeedbackBackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

/// Answers in order; while `holdNext` is set the next call waits for `release`.
@MainActor
private final class FeedbackRoute {
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
        return answers.isEmpty ? JessResult.cutOff(transcript: transcript) : answers.removeFirst()
    }
}

/// Stands in for POST /voice/jess/cancel.
@MainActor
private final class FeedbackCancels {
    var reachesServer = true
    private(set) var received: [JessServerCancel] = []

    func cancel(_ cancel: JessServerCancel) async -> Bool {
        received.append(cancel)
        return reachesServer
    }
}

private func feedbackResultsFileURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "build22-feedback-\(UUID().uuidString)/results.json")
}

@MainActor
private func feedbackResults(route: FeedbackRoute, cancels: FeedbackCancels, fileURL: URL) -> JessResults {
    func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        await route.route(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone, onApplied: onApplied)
    }
    func cancelCall(_ cancel: JessServerCancel) async -> Bool {
        await cancels.cancel(cancel)
    }
    func isSignedIn() -> Bool {
        true
    }
    func isInForeground() -> Bool {
        false
    }
    func now() -> Date {
        feedbackSaidTime
    }
    func timeZone() -> TimeZone {
        TimeZone(identifier: "America/Los_Angeles")!
    }
    var dependencies = JessResultsDependencies(route: routeCall, backgroundTime: FeedbackBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    dependencies.foregroundRetryDelay = nil
    dependencies.cancelOnServer = cancelCall
    return JessResults(file: JessResultsFile(fileURL: fileURL), dependencies: dependencies)
}

@MainActor
final class Build22FeedbackDeleteStopsTests: XCTestCase {
    func testATaskDeletedWhileWaitingForConnectionIsNeverSentAgain() async {
        let route = FeedbackRoute(answers: [.cutOff(transcript: "add eggs"), .done(text: "Added Eggs", at: nil, allDay: nil, timeZone: nil)])
        let cancels = FeedbackCancels()
        let results = feedbackResults(route: route, cancels: cancels, fileURL: feedbackResultsFileURL())
        await results.submit(transcript: "add eggs", listenMs: 900)
        let cardId = results.log[0].id
        XCTAssertEqual(results.pendingRequests.count, 1)

        results.removeFromLog(cardId: cardId)
        await results.resume()
        await waitUntilTrue { !cancels.received.isEmpty }

        XCTAssertEqual(route.callCount, 1, "not sent again")
        XCTAssertTrue(results.pendingRequests.isEmpty, "the request left the queue")
        XCTAssertEqual(cancels.received, [JessServerCancel(requestId: cardId.uuidString.lowercased())], "the server drops its id")
    }

    func testATaskDeletedOnItsWayShowsNothingAndIsNotSentAgain() async {
        let route = FeedbackRoute(answers: [.cutOff(transcript: "add milk"), .done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil)])
        route.holdNext = true
        let cancels = FeedbackCancels()
        let results = feedbackResults(route: route, cancels: cancels, fileURL: feedbackResultsFileURL())
        let submitting = Task { @MainActor in
            await results.submit(transcript: "add milk", listenMs: 900)
        }
        await waitUntilTrue { route.isHolding }
        let cardId = results.log[0].id

        results.removeFromLog(cardId: cardId)
        route.release()
        _ = await submitting.value
        await results.resume()

        XCTAssertEqual(route.callCount, 1, "a cut-off answer for a deleted task is not sent again")
        XCTAssertTrue(results.log.isEmpty)
        XCTAssertTrue(results.pendingRequests.isEmpty)
    }

    func testAnEditFiledForADeletedTaskIsDroppedOnTheServer() async {
        let link = JessRepairLink(reportId: "r-on-its-way", pendingId: "p-on-its-way")
        let route = FeedbackRoute(answers: [.sentToRepair(sidekickName: "Reminders", link: link)])
        route.holdNext = true
        let cancels = FeedbackCancels()
        let results = feedbackResults(route: route, cancels: cancels, fileURL: feedbackResultsFileURL())
        let submitting = Task { @MainActor in
            await results.submit(transcript: "flag it", listenMs: 900)
        }
        await waitUntilTrue { route.isHolding }
        results.removeFromLog(cardId: results.log[0].id)
        route.release()
        _ = await submitting.value
        await waitUntilTrue { cancels.received.count >= 2 }

        XCTAssertTrue(cancels.received.contains(JessServerCancel(reportId: "r-on-its-way", pendingId: "p-on-its-way")))
        XCTAssertTrue(results.log.isEmpty)
    }

    func testDeletingACardWaitingOnItsEditCancelsTheEdit() async {
        let link = JessRepairLink(reportId: "r1", pendingId: "p1")
        let route = FeedbackRoute(answers: [.sentToRepair(sidekickName: "Reminders", link: link)])
        let cancels = FeedbackCancels()
        let results = feedbackResults(route: route, cancels: cancels, fileURL: feedbackResultsFileURL())
        await results.submit(transcript: "remind me every 4 hours", listenMs: 900)

        results.removeFromLog(cardId: results.log[0].id)
        await waitUntilTrue { !cancels.received.isEmpty }

        XCTAssertEqual(cancels.received, [JessServerCancel(reportId: "r1", pendingId: "p1")])
    }

    func testADoneTaskDeletedCancelsNothing() async {
        let route = FeedbackRoute(answers: [.done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil)])
        let cancels = FeedbackCancels()
        let results = feedbackResults(route: route, cancels: cancels, fileURL: feedbackResultsFileURL())
        await results.submit(transcript: "add milk", listenMs: 900)

        results.removeFromLog(cardId: results.log[0].id)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(cancels.received.isEmpty, "a finished task has nothing to stop")
        XCTAssertTrue(results.unsentServerCancels.isEmpty)
    }

    func testACancelThatDidNotReachTheServerIsSentOnTheNextOpen() async {
        let fileURL = feedbackResultsFileURL()
        let firstRoute = FeedbackRoute(answers: [.cutOff(transcript: "add bread")])
        let offline = FeedbackCancels()
        offline.reachesServer = false
        let first = feedbackResults(route: firstRoute, cancels: offline, fileURL: fileURL)
        await first.submit(transcript: "add bread", listenMs: 900)
        first.removeFromLog(cardId: first.log[0].id)
        await waitUntilTrue { !offline.received.isEmpty }
        XCTAssertEqual(first.unsentServerCancels.count, 1, "kept until the server takes it")

        let secondRoute = FeedbackRoute(answers: [])
        let online = FeedbackCancels()
        let reopened = feedbackResults(route: secondRoute, cancels: online, fileURL: fileURL)
        XCTAssertEqual(reopened.unsentServerCancels.count, 1, "kept on disk")
        await reopened.resume()
        await waitUntilTrue { reopened.unsentServerCancels.isEmpty }

        XCTAssertEqual(online.received.count, 1)
        XCTAssertTrue(reopened.unsentServerCancels.isEmpty)
        XCTAssertEqual(secondRoute.callCount, 0, "the deleted request itself is not sent")
    }

    func testTheRouterWritesNoOpsForADeletedTask() throws {
        let source = try String(contentsOf: feedbackShellRoot().appending(path: "Midas/JessRouter.swift"), encoding: .utf8)
        guard let check = source.range(of: "JessRouteContext.current?.isCancelled == true"), let write = source.range(of: "try dependencies.apply(sidekickId, ops)") else {
            XCTFail("the cancel check and the write are both in JessRouter")
            return
        }
        XCTAssertLessThan(check.lowerBound, write.lowerBound, "checked before the ops are written")
    }

    func testTheCancelCallIsSentAgainUnlessTheServerTookIt() {
        XCTAssertTrue(RemoteJessRouter.cancelTaken(statusCode: 200))
        XCTAssertTrue(RemoteJessRouter.cancelTaken(statusCode: 400), "malformed never gets better")
        XCTAssertFalse(RemoteJessRouter.cancelTaken(statusCode: 0), "no network")
        XCTAssertFalse(RemoteJessRouter.cancelTaken(statusCode: 401))
        XCTAssertFalse(RemoteJessRouter.cancelTaken(statusCode: 503))
    }
}
