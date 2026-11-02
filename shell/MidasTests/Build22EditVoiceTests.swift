import SwiftUI
import UIKit
import XCTest
@testable import Midas

// Build 22, the edit-voice worktree (founder, 2026-10-31, docs/briefs/build-22-2026-10-31.md):
// "Repair" is "Edit" everywhere a person sees it, the tag says "On it" then "Editing" after Send,
// the hint cloud on the first five sends, "Taking a Deeper Look" (founder, 2026-11-01; was "Check back in some time.") for an edit that could not
// be made, Make's sender is "Make" and its first open shows "Built by Hand" signed RJ, the keyboard
// stops the Edit layer's voice and the orb listens again, jess listens 2.5 s after the last word
// for up to 30 s, home shows only Not Done cards, and cards swipe sideways to delete.

private func build22Defaults() -> UserDefaults {
    let suiteName = "build22-\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

private func build22ShellRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func build22Wait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 {
        if await condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Words

final class Build22EditWordsTests: XCTestCase {
    func testThePersonSeesEditNeverRepair() {
        XCTAssertEqual(RepairTagCopy.repairMode, "Edit")
        XCTAssertEqual(RepairTagCopy.onIt, "On it")
        XCTAssertEqual(RepairTagCopy.repairing(count: 1), "Editing")
        XCTAssertEqual(RepairTagCopy.repairing(count: 2), "Editing 2")
        XCTAssertEqual(RepairTagCopy.fixedOnPage, "Edit done. Tap to update")
        XCTAssertEqual(RepairTagCopy.couldntFix, "Taking a Deeper Look")
        XCTAssertEqual(VoiceReminderCopy.sentToRepair, "Sent to Edit")
        XCTAssertEqual(MakeCopy.notAvailable(), "Edit not available for this Sidekick.")
        let every: [RepairTagDisplay] = [.repairMode, .repairing(count: 1, takingLonger: false), .repairing(count: 2, takingLonger: true), .fixed(onPage: true, summary: nil), .fixed(onPage: false, summary: nil), .alreadyThere(summary: nil), .couldntFix]
        for display in every {
            XCTAssertFalse(display.words.contains("Repair"), display.words)
        }
    }

    func testMakesSenderIsMake() {
        XCTAssertEqual(MakeCopy.senderName, "Make")
        XCTAssertEqual(MakeCopy.line(from: MakeCopy.senderName, "3 designs"), "Make: 3 designs")
    }

    func testTheTagSaysOnItForTheFirstSecondsAfterSendThenEditing() {
        let editing = RepairTagDisplay.repairing(count: 1, takingLonger: false)
        XCTAssertEqual(RepairTagSpec.onItSeconds, 3.1)
        XCTAssertEqual(RepairTagCopy.words(for: editing, secondsSinceSend: 0.5), "On it")
        XCTAssertEqual(RepairTagCopy.words(for: editing, secondsSinceSend: 3.0), "On it")
        XCTAssertEqual(RepairTagCopy.words(for: editing, secondsSinceSend: 3.2), "Editing")
        XCTAssertEqual(RepairTagCopy.words(for: editing, secondsSinceSend: nil), "Editing", "back on the screen later it is Editing")
        XCTAssertEqual(RepairTagCopy.words(for: .repairing(count: 1, takingLonger: true), secondsSinceSend: 1), "Taking longer")
        XCTAssertEqual(RepairTagCopy.words(for: .repairMode, secondsSinceSend: 1), "Edit")
        XCTAssertEqual(RepairTagCopy.words(for: .couldntFix, secondsSinceSend: 1), "Taking a Deeper Look")
    }

    func testTheSendAnimationWidensFromEditToOnIt() {
        XCTAssertEqual(RepairSendMotion.tagStartWidth, RepairSendMotion.tagWidth(for: "Edit", withOrb: false))
        XCTAssertEqual(RepairSendMotion.tagEndWidth, RepairSendMotion.tagWidth(for: "On it", withOrb: true))
        XCTAssertGreaterThan(RepairSendMotion.tagEndWidth, RepairSendMotion.tagStartWidth)
        let wider = RepairSendMotion.tagWidth(for: "Editing", withOrb: true)
        XCTAssertGreaterThan(wider, RepairSendMotion.tagEndWidth)
    }

    func testCouldNotEditHasNoTryAgain() throws {
        let chromeSource = try String(contentsOf: build22ShellRoot().appending(path: "Midas/RepairChromeView.swift"), encoding: .utf8)
        XCTAssertFalse(chromeSource.contains("onTryAgain"), "the founder makes it by hand; Try Again would send it twice")
        XCTAssertFalse(chromeSource.contains("RepairTagCopy.tryAgain"))
    }
}

// MARK: - The hint cloud

@MainActor
final class Build22SendHintTests: XCTestCase {
    func testTheHintShowsOnTheFirstFiveSendsOnly() {
        let counter = RepairSendHintCounter(defaults: build22Defaults())
        var shown: [Bool] = []
        for _ in 0..<7 {
            shown.append(counter.countSend())
        }
        XCTAssertEqual(shown, [true, true, true, true, true, false, false])
        XCTAssertEqual(RepairSendHintCopy.text, "Close anytime. Edits finish on their own.")
    }

    func testTheCloudGrowsInAndIsGoneAfterThreeSeconds() throws {
        XCTAssertNil(RepairSendHintLook.at(-0.01, reduceMotion: false))
        let start = try XCTUnwrap(RepairSendHintLook.at(0, reduceMotion: false))
        XCTAssertEqual(start.opacity, 0, accuracy: 0.001)
        XCTAssertEqual(start.scale, RepairSendHintSpec.startScale, accuracy: 0.001)
        let settled = try XCTUnwrap(RepairSendHintLook.at(1.5, reduceMotion: false))
        XCTAssertEqual(settled.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(settled.scale, 1, accuracy: 0.01)
        XCTAssertEqual(Double(settled.rise), 0, accuracy: 0.2)
        let fading = try XCTUnwrap(RepairSendHintLook.at(2.8, reduceMotion: false))
        XCTAssertLessThan(fading.opacity, 1)
        XCTAssertGreaterThan(fading.opacity, 0)
        XCTAssertNil(RepairSendHintLook.at(3.01, reduceMotion: false), "gone 3 s after it came")
        let still = try XCTUnwrap(RepairSendHintLook.at(0.05, reduceMotion: true))
        XCTAssertEqual(still.scale, 1, "Reduce Motion: it fades, no growing")
    }

    func testSendStartsTheHintRightAfterTheTagsNewWordsThenNotAfterTheFifth() throws {
        let chrome = RepairChrome()
        chrome.sendHaptic = {}
        chrome.reduceMotion = { false }
        chrome.hintCounter = RepairSendHintCounter(defaults: build22Defaults())
        chrome.pageFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        chrome.tagFrame = CGRect(x: 164, y: 53, width: 74, height: 28)
        let shot = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let sentAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for send in 1...6 {
            chrome.playSendAnimation(shot: shot, now: sentAt)
            if send <= 5 {
                let hintStart = try XCTUnwrap(chrome.hintStartsAt, "send \(send) has the hint")
                XCTAssertGreaterThan(hintStart, sentAt)
                XCTAssertLessThan(hintStart.timeIntervalSince(sentAt), 1.5, "right after Send, while the person is still there")
                XCTAssertNotNil(chrome.hintLook(at: hintStart.addingTimeInterval(1)))
            } else {
                XCTAssertNil(chrome.hintStartsAt, "never after the fifth send")
                XCTAssertNil(chrome.hintLook(at: sentAt.addingTimeInterval(1.5)))
            }
            let liveUntil = try XCTUnwrap(chrome.liveUntil)
            XCTAssertGreaterThanOrEqual(liveUntil.timeIntervalSince(sentAt), RepairTagSpec.onItSeconds, "frames run until the tag says Editing")
        }
        XCTAssertEqual(try XCTUnwrap(chrome.secondsSinceSend(at: sentAt.addingTimeInterval(1))), 1, accuracy: 0.001)
    }
}

// MARK: - Edit layer voice

@MainActor
private final class Build22Transcriber: RepairTranscribing {
    private(set) var starts = 0
    private(set) var stops = 0
    private var hear: (@MainActor (RepairTranscript) -> Void)?
    private var ended: (@MainActor (VoiceTranscriptionEnd) -> Void)?

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        starts += 1
        hear = onUpdate
    }

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        starts += 1
        hear = onUpdate
        ended = onEnd
    }

    func stop() {
        stops += 1
        ended?(.stopped)
    }

    func say(_ text: String) {
        hear?(RepairTranscript(text: text, words: []))
    }
}

private struct Build22NoUpload: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .retryLater
    }
}

@MainActor
final class Build22EditVoiceTests: XCTestCase {
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "build22-voice-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    private func makeSession(_ transcriber: Build22Transcriber) -> RepairSession {
        let uploader = RepairUploader(api: Build22NoUpload(), outbox: RepairOutbox(directoryURL: outboxURL))
        let snapshot = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        return RepairSession(sidekickId: "reminders", snapshot: snapshot, viewSize: CGSize(width: 402, height: 874), transcriber: transcriber, uploader: uploader)
    }

    func testTheKeyboardStopsVoiceAndKeepsTheWordsHeard() async {
        let transcriber = Build22Transcriber()
        let session = makeSession(transcriber)
        await session.startListening()
        XCTAssertTrue(session.isListening)
        transcriber.say("make the button")

        session.isTyping = true

        XCTAssertFalse(session.isListening, "the keyboard came up: voice stops")
        XCTAssertEqual(transcriber.stops, 1)
        XCTAssertEqual(session.transcript.text, "make the button", "words already heard stay")
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(transcriber.starts, 1, "it does not listen again by itself while typing")
        await session.startListening()
        XCTAssertEqual(transcriber.starts, 1, "nothing listens while the keyboard is up")
        session.typedText = "bigger"
        XCTAssertEqual(RepairReportBuilder.combinedTranscript(spokenText: session.transcript.text, typedText: session.typedText).contains("bigger"), true)
    }

    func testTappingTheOrbListensAgainAfterTheWordsAndPutsTheKeyboardDown() async {
        let transcriber = Build22Transcriber()
        let session = makeSession(transcriber)
        await session.startListening()
        transcriber.say("make the button")
        session.isTyping = true
        session.typedText = "bigger"

        session.listenAgain()
        await build22Wait { session.isListening }

        XCTAssertTrue(session.isListening)
        XCTAssertFalse(session.isTyping, "the keyboard goes down")
        XCTAssertEqual(transcriber.starts, 2)
        transcriber.say("and blue")
        XCTAssertEqual(session.transcript.text, "make the button and blue", "the new words follow the words already there")
        XCTAssertEqual(session.typedText, "bigger")
    }

    func testThePillsOrbIsAButtonInTheEditLayer() throws {
        let canvas = try String(contentsOf: build22ShellRoot().appending(path: "Midas/RepairCanvasView.swift"), encoding: .utf8)
        XCTAssertTrue(canvas.contains("onOrbTap: session.listenAgain"))
    }

    func testJessListensTwoAndAHalfSecondsAfterTheLastWordForUpToThirty() {
        XCTAssertEqual(VoiceReminderListening.endOfSpeechSilence, .milliseconds(2500))
        XCTAssertEqual(VoiceReminderListening.maximumDuration, .seconds(30))
        let options = VoiceReminderListening.transcriberOptions(lists: [])
        XCTAssertEqual(options.endOfSpeechSilence, .milliseconds(2500))
        XCTAssertEqual(options.maximumDuration, .seconds(30))
    }
}

// MARK: - Cards

private let build22SaidTime = Date(timeIntervalSince1970: 1_793_000_000)

@MainActor
private final class Build22BackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

@MainActor
private final class Build22Route {
    var answers: [JessResult]

    init(answers: [JessResult]) {
        self.answers = answers
    }

    func route(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        let answer = answers.isEmpty ? JessResult.cutOff(transcript: transcript) : answers.removeFirst()
        if case .done = answer {
            onApplied(answer)
        }
        return answer
    }
}

@MainActor
private func build22Results(route: Build22Route) -> JessResults {
    let file = FileManager.default.temporaryDirectory.appending(path: "build22-cards-\(UUID().uuidString)/results.json")
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
        build22SaidTime
    }
    func timeZone() -> TimeZone {
        TimeZone(identifier: "America/Los_Angeles")!
    }
    var dependencies = JessResultsDependencies(route: routeCall, backgroundTime: Build22BackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    dependencies.foregroundRetryDelay = nil
    return JessResults(file: JessResultsFile(fileURL: file), dependencies: dependencies)
}

@MainActor
final class Build22CardsTests: XCTestCase {
    func testHomeShowsOnlyNotDoneCards() async throws {
        let growLink = JessRepairLink(reportId: "r1", pendingId: "p1")
        let route = Build22Route(answers: [
            .done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil),
            .notDone(transcript: "move dentist to friday"),
            .sentToRepair(sidekickName: "Reminders", link: growLink),
            .cutOff(transcript: "add eggs"),
        ])
        let results = build22Results(route: route)
        await results.submit(transcript: "add milk", listenMs: 900)
        await results.submit(transcript: "move dentist to friday", listenMs: 900)
        await results.submit(transcript: "make reminders flag it", listenMs: 900)
        await results.submit(transcript: "add eggs", listenMs: 900)

        XCTAssertEqual(results.log.count, 4, "the Workdesk keeps every task")
        XCTAssertEqual(results.homeCards.count, 1)
        XCTAssertEqual(results.homeCards.first?.kind, .notDone)
        XCTAssertEqual(results.homeCards.first?.transcript, "move dentist to friday")
        let app = try String(contentsOf: build22ShellRoot().appending(path: "Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("jessResults.homeCards.isEmpty"))
        let capture = try String(contentsOf: build22ShellRoot().appending(path: "Midas/VoiceCaptureView.swift"), encoding: .utf8)
        XCTAssertTrue(capture.contains("let shown = results.homeCards"))
    }

    func testAnEditThatTurnsNotDoneComesBackToHome() async {
        let growLink = JessRepairLink(reportId: "r1", pendingId: "p1")
        let route = Build22Route(answers: [.sentToRepair(sidekickName: "Reminders", link: growLink)])
        let results = build22Results(route: route)
        await results.submit(transcript: "make reminders flag it", listenMs: 900)
        let cardId = results.log[0].id
        results.dismiss(cardId: cardId)
        XCTAssertTrue(results.homeCards.isEmpty)

        XCTAssertTrue(results.settleGrow(pendingId: "p1", result: .notDone(transcript: "make reminders flag it")))

        XCTAssertEqual(results.homeCards.map(\.id), [cardId], "Not Done brings its card to home")
    }

    func testSwipingAWorkdeskCardRemovesItFromTheLogAndHome() async {
        let route = Build22Route(answers: [.notDone(transcript: "move dentist"), .done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil)])
        let results = build22Results(route: route)
        await results.submit(transcript: "move dentist", listenMs: 900)
        await results.submit(transcript: "add milk", listenMs: 900)
        let notDoneId = results.homeCards[0].id

        results.removeFromLog(cardId: notDoneId)

        XCTAssertEqual(results.log.count, 1)
        XCTAssertFalse(results.log.contains { $0.id == notDoneId })
        XCTAssertTrue(results.homeCards.isEmpty)
        results.removeFromLog(cardId: UUID())
        XCTAssertEqual(results.log.count, 1, "an unknown card changes nothing")
    }

    func testSidewaysFarOrFastDeletesAnythingElseSpringsBack() {
        XCTAssertEqual(CardSwipeDelete.decision(translation: CGSize(width: 120, height: 10), predicted: CGSize(width: 130, height: 10)), .delete(direction: 1))
        XCTAssertEqual(CardSwipeDelete.decision(translation: CGSize(width: -120, height: 4), predicted: CGSize(width: -120, height: 4)), .delete(direction: -1))
        XCTAssertEqual(CardSwipeDelete.decision(translation: CGSize(width: 40, height: 2), predicted: CGSize(width: 300, height: 2)), .delete(direction: 1), "a fling")
        XCTAssertEqual(CardSwipeDelete.decision(translation: CGSize(width: 40, height: 2), predicted: CGSize(width: 60, height: 2)), .springBack)
        XCTAssertEqual(CardSwipeDelete.decision(translation: CGSize(width: 40, height: 2), predicted: CGSize(width: -300, height: 2)), .springBack, "flung back the other way")
        XCTAssertEqual(CardSwipeDelete.decision(translation: CGSize(width: 110, height: 200), predicted: CGSize(width: 110, height: 400)), .springBack, "up or down is not a delete")
        XCTAssertTrue(CardSwipeDelete.isSideways(CGSize(width: 10, height: 3)))
        XCTAssertFalse(CardSwipeDelete.isSideways(CGSize(width: 3, height: 10)))
    }

    func testTheSwipedWorkdeskCardIsTheOneUnderTheFinger() {
        XCTAssertEqual(JessWorkdeskLayout.cardIndex(atY: 50, scroll: 0, cardCount: 6), 0, "the big card")
        XCTAssertEqual(JessWorkdeskLayout.cardIndex(atY: 200, scroll: 0, cardCount: 6), 1)
        XCTAssertEqual(JessWorkdeskLayout.cardIndex(atY: 270, scroll: 0, cardCount: 6), 2, "the slim card, not the tucked one behind it")
        XCTAssertNil(JessWorkdeskLayout.cardIndex(atY: 160, scroll: 0, cardCount: 6), "between cards")
        XCTAssertNil(JessWorkdeskLayout.cardIndex(atY: 320, scroll: 0, cardCount: 6), "tucked cards show no words")
        XCTAssertEqual(JessWorkdeskLayout.cardIndex(atY: 50, scroll: 1, cardCount: 6), 1, "scrolled one down")
        XCTAssertNil(JessWorkdeskLayout.cardIndex(atY: 200, scroll: 0, cardCount: 1), "only one card")
    }

    func testHomeCardsHaveNoCloseButtonAndSwipeSideways() throws {
        let capture = try String(contentsOf: build22ShellRoot().appending(path: "Midas/VoiceCaptureView.swift"), encoding: .utf8)
        XCTAssertTrue(capture.contains(".swipeSidewaysToDelete(onDismiss)"))
        XCTAssertFalse(capture.contains("dismissOnSwipeUp(_ value: DragGesture.Value) {\n        if value.translation.height < -20 && card.kind"))
        let workdesk = try String(contentsOf: build22ShellRoot().appending(path: "Midas/VoiceCaptureView.swift"), encoding: .utf8)
        XCTAssertTrue(workdesk.contains("onDelete: results.removeFromLog"))
    }
}

// MARK: - Make, first open

final class Build22MakeWelcomeTests: XCTestCase {
    func testTheSheetShowsOnceOnThisPhone() {
        let memory = MakeWelcomeMemory(defaults: build22Defaults())
        XCTAssertTrue(memory.takeFirstOpen())
        XCTAssertFalse(memory.takeFirstOpen())
        XCTAssertFalse(memory.takeFirstOpen())
    }

    func testTheFoundersWords() {
        XCTAssertEqual(MakeWelcomeCopy.title, "Built by Hand")
        XCTAssertEqual(MakeWelcomeCopy.line, "I build your first version myself, so it arrives near perfect.")
        XCTAssertEqual(MakeWelcomeCopy.signature, "RJ")
        XCTAssertEqual(MakeWelcomeCopy.continueButton, "Continue")
        let marked = MakeWelcomeSheet.markedLine(scheme: .light)
        XCTAssertEqual(String(marked.characters), MakeWelcomeCopy.line)
        let range = try? XCTUnwrap(marked.range(of: "myself"))
        XCTAssertNotNil(range.flatMap { marked[$0].backgroundColor }, "myself is marked in Volt")
    }

    func testTheHandIsBundledForTheSignature() throws {
        XCTAssertNotNil(UIFont(name: MakeWelcomeSpec.handFontName, size: MakeWelcomeSpec.signatureSize), "Caveat Bold is not registered (UIAppFonts)")
        let make = try String(contentsOf: build22ShellRoot().appending(path: "Midas/MakeHomeView.swift"), encoding: .utf8)
        XCTAssertTrue(make.contains(".makeWelcomeOnFirstOpen()"))
    }
}
