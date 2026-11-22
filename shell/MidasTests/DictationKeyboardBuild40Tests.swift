#if MIDAS_TEST_BUILD
// Build 40: our UI while Apple listens (TEST BUILD, founder 2026-11-22;
// docs/briefs/dictation-keyboard-test.md, "Build 40"; branch agent/dictation-test, never merged).
// Compiled only against a Test build: run with the "Midas Test" scheme's test action.
//
// keyboardMic "apple": the keyboard watches Apple's dictation through public signals (a fake
// input-mode and text sequence here), shows it, and when it ends replaces the dictated span with
// the gate's text when the text still ends with that span, else skips and says why. Also here:
// the setting, appleCleanup, and the run Midas Test saves (mic apple).
import XCTest
@testable import Midas

@MainActor
final class DictationKeyboardBuild40Tests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_763_800_000)
    private var temporaryFolder: URL!

    override func setUp() {
        super.setUp()
        temporaryFolder = FileManager.default.temporaryDirectory.appending(path: "dictation-build40-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryFolder)
        super.tearDown()
    }

    private func seconds(_ offset: TimeInterval) -> Date {
        startedAt.addingTimeInterval(offset)
    }

    private func mailbox() -> DictationKeyboardMailbox {
        DictationKeyboardMailbox(folder: temporaryFolder.appending(path: "group"))
    }

    private static func builtInSettings() -> DictationGateSettings {
        .builtIn
    }

    /// The one ended dictation in a list of events; nil when none ended.
    private func finished(in events: [DictationAppleEvent]) -> DictationAppleFinished? {
        for event in events {
            if case .ended(let finished) = event {
                return finished
            }
        }
        return nil
    }

    // MARK: The dictated span

    func testTheSpanIsWhatFollowsTheTextFromBefore() {
        XCTAssertEqual(DictationAppleSpan.dictated(from: "Hi", to: "Hi um tell"), " um tell")
        XCTAssertEqual(DictationAppleSpan.dictated(from: "", to: "Hello"), "Hello")
        XCTAssertEqual(DictationAppleSpan.dictated(from: "Hi", to: "Hi"), "")
    }

    func testTheSpanSurvivesIOSDroppingTextFromTheFrontOfTheContext() {
        let before = "abcdefghijklmnopqrstuvwxyz"
        XCTAssertEqual(DictationAppleSpan.dictated(from: before, to: "mnopqrstuvwxyz hello"), " hello")
        // Fewer than 12 characters still shared: not the same text
        XCTAssertNil(DictationAppleSpan.dictated(from: before, to: "uvwxyz hello"))
        XCTAssertNil(DictationAppleSpan.dictated(from: "the quick brown fox jumps", to: "something else entirely here"))
    }

    func testTheSpanSplitsIntoWhitespaceAndWords() {
        let parts = DictationAppleSpan.parts(of: " um tell mom ")
        XCTAssertEqual(parts.leading, " ")
        XCTAssertEqual(parts.core, "um tell mom")
        XCTAssertEqual(parts.trailing, " ")
        let bare = DictationAppleSpan.parts(of: "ok")
        XCTAssertEqual(bare.leading, "")
        XCTAssertEqual(bare.core, "ok")
        XCTAssertEqual(bare.trailing, "")
    }

    // MARK: Detection from a fake signal sequence

    func testTextChangedWithoutAMidasKeyIsDictatedAndEndsAfterOnePointFiveQuietSeconds() throws {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "Hi", after: "")
        XCTAssertEqual(tracker.observed(context: "Hi", after: "", by: .poll, at: seconds(0)), [], "no change, no dictation")
        XCTAssertEqual(tracker.observed(context: "Hi um", after: "", by: .poll, at: seconds(1)), [.began(.poll), .heard(" um")])
        XCTAssertEqual(tracker.phase, .dictating)
        XCTAssertEqual(tracker.observed(context: "Hi um tell mom", after: "", by: .textDidChange, at: seconds(1.5)), [.heard(" um tell mom")])
        XCTAssertEqual(tracker.observed(context: "Hi um tell mom", after: "", by: .poll, at: seconds(1.6)), [], "the same words again")
        XCTAssertEqual(tracker.tick(at: seconds(2.9)), [], "1.4 s quiet is not the end")
        let ended = try XCTUnwrap(finished(in: tracker.tick(at: seconds(3.0))))
        XCTAssertEqual(ended.span, " um tell mom")
        XCTAssertEqual(ended.end, .quiet)
        XCTAssertEqual(ended.startedAt, seconds(1))
        XCTAssertEqual(ended.lastChangeAt, seconds(1.5))
        XCTAssertEqual(ended.signals, [.poll, .textDidChange])
        XCTAssertEqual(ended.signalCounts, [.poll: 2, .textDidChange: 1])
        XCTAssertEqual(DictationAppleLog.countsDetail(ended), "poll 2, text-did-change 1")
        XCTAssertEqual(tracker.phase, .waiting)
        XCTAssertEqual(DictationAppleConstants.quietEnd, 1.5)
    }

    func testMidasKeysAreNotDictationEvenWhenTheHostsTextLags() {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "Hi", after: "")
        tracker.midasTyped(expected: "Hi!", at: seconds(0))
        XCTAssertEqual(tracker.observed(context: "Hi!", after: "", by: .textDidChange, at: seconds(0.05)), [])
        // The host shows something else right after a key: still the key
        tracker.midasTyped(expected: "Hi!x", at: seconds(1))
        XCTAssertEqual(tracker.observed(context: "Hi! x", after: "", by: .poll, at: seconds(1.2)), [])
        XCTAssertEqual(tracker.baseline, "Hi! x")
        XCTAssertEqual(tracker.phase, .waiting)
        // Past the grace, a change Midas did not make is dictation
        XCTAssertEqual(tracker.observed(context: "Hi! x yes", after: "", by: .poll, at: seconds(2)), [.began(.poll), .heard(" yes")])
    }

    func testTheCursorMovingIsNotDictation() {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "Hello", after: " world")
        XCTAssertEqual(tracker.observed(context: "Hello world", after: "", by: .poll, at: seconds(5)), [])
        XCTAssertEqual(tracker.phase, .waiting)
        XCTAssertEqual(tracker.baseline, "Hello world")
        XCTAssertEqual(tracker.baselineAfter, "")
    }

    func testTheCursorMovingDuringDictationLosesTheSpan() throws {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "A", after: "")
        XCTAssertEqual(tracker.observed(context: "A b", after: "", by: .poll, at: seconds(1)), [.began(.poll), .heard(" b")])
        XCTAssertEqual(tracker.observed(context: "A b", after: "zzz", by: .poll, at: seconds(1.2)), [.heard("")])
        let ended = try XCTUnwrap(finished(in: tracker.tick(at: seconds(2.8))))
        XCTAssertNil(ended.span)
        let plan = DictationAppleCleanup.plan(span: ended.span, contextNow: "A b", settings: .builtIn)
        XCTAssertEqual(plan.result, .contextLost)
        XCTAssertFalse(plan.replaces)
    }

    func testTheInputModeStartsAndEndsADictationAndHoldsOffTheQuietEnd() throws {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "Hi", after: "")
        XCTAssertEqual(tracker.inputModeChanged(isDictation: false, at: seconds(0)), [], "not dictating: nothing")
        XCTAssertEqual(tracker.inputModeChanged(isDictation: true, at: seconds(0)), [.began(.inputMode)])
        XCTAssertEqual(tracker.observed(context: "Hi um ok", after: "", by: .poll, at: seconds(0.5)), [.heard(" um ok")])
        XCTAssertEqual(tracker.tick(at: seconds(5)), [], "the mode still says dictation")
        let ended = try XCTUnwrap(finished(in: tracker.inputModeChanged(isDictation: false, at: seconds(6))))
        XCTAssertEqual(ended.end, .inputMode)
        XCTAssertEqual(ended.span, " um ok")
        XCTAssertEqual(ended.signals, [.inputMode, .poll])
        XCTAssertEqual(ended.signalCounts[.inputMode], 2)
        XCTAssertTrue(DictationAppleConstants.isDictation(language: "dictation"))
        XCTAssertFalse(DictationAppleConstants.isDictation(language: "en-US"))
        XCTAssertFalse(DictationAppleConstants.isDictation(language: nil))
    }

    func testTheKeyboardComingBackEndsADictationInTheSameFieldOnly() throws {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "Hi", after: "")
        // Another field or app: its text is the person's
        XCTAssertEqual(tracker.appeared(context: "Other field", after: "", sameDocument: false, at: seconds(1)), [])
        XCTAssertEqual(tracker.baseline, "Other field")
        // The same field with words added at the cursor while hidden: dictated, and it ended
        let events = tracker.appeared(context: "Other field and more", after: "", sameDocument: true, at: seconds(10))
        XCTAssertEqual(events.first, .began(.appeared))
        let ended = try XCTUnwrap(finished(in: events))
        XCTAssertEqual(ended.end, .keyboardShown)
        XCTAssertEqual(ended.span, " and more")
        // Seen before it hid: ends with the text found now, whatever the field
        tracker.reset(context: "A", after: "")
        _ = tracker.observed(context: "A b", after: "", by: .poll, at: seconds(20))
        let shown = try XCTUnwrap(finished(in: tracker.appeared(context: "A b c", after: "", sameDocument: false, at: seconds(21))))
        XCTAssertEqual(shown.span, " b c")
    }

    func testAMidasKeyEndsADictationAndWhitespaceOnlyEndsWithNothing() throws {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "A", after: "")
        XCTAssertEqual(tracker.end(.midasKey), [], "nothing running")
        _ = tracker.observed(context: "A b", after: "", by: .poll, at: seconds(1))
        let ended = try XCTUnwrap(finished(in: tracker.end(.midasKey)))
        XCTAssertEqual(ended.end, .midasKey)
        tracker.reset(context: "A", after: "")
        _ = tracker.observed(context: "A ", after: "", by: .poll, at: seconds(2))
        XCTAssertEqual(tracker.end(.midasKey), [])
        XCTAssertEqual(tracker.phase, .waiting)
    }

    // MARK: Span check and replace

    func testAppleTypedFillersAreReplacedWithTheGatesText() throws {
        let span = " Um tell mom I'm on my way."
        let plan = DictationAppleCleanup.plan(span: span, contextNow: "Hi." + span, settings: .builtIn)
        XCTAssertEqual(plan.result, .applied)
        XCTAssertEqual(plan.raw, "Um tell mom I'm on my way.")
        let expected = try XCTUnwrap(DictationKeyboardInsertText.make(raw: plan.raw, settings: .builtIn)).text
        XCTAssertEqual(plan.cleaned, expected)
        XCTAssertTrue(expected.hasPrefix("Tell mom"), expected)
        XCTAssertEqual(plan.gate?.decision.path, .rule)
        XCTAssertEqual(plan.gate?.decision.matched.first?.lowercased(), "um")
        // Only what differs is deleted: the leading space stays
        XCTAssertEqual(plan.deleteCount, span.count - 1)
        XCTAssertEqual(plan.insertText, expected)
        XCTAssertEqual(DictationAppleCleanup.contextAfter(plan, contextNow: "Hi." + span), "Hi. " + expected)
        XCTAssertTrue(DictationAppleLog.cleanupDetail(plan).hasPrefix("applied: deleted \(span.count - 1), inserted \(expected.count)"))
    }

    func testFillersOnlyAreDeleted() {
        let plan = DictationAppleCleanup.plan(span: " um", contextNow: "Hi um", settings: .builtIn)
        XCTAssertEqual(plan.result, .applied)
        XCTAssertEqual(plan.cleaned, "")
        XCTAssertEqual(plan.deleteCount, 2)
        XCTAssertEqual(plan.insertText, "")
        XCTAssertEqual(DictationAppleCleanup.contextAfter(plan, contextNow: "Hi um"), "Hi ")
    }

    func testTextAlreadyCleanIsLeftAsItIs() {
        let span = " Tell mom."
        let plan = DictationAppleCleanup.plan(span: span, contextNow: "Hi." + span, settings: .builtIn)
        XCTAssertEqual(plan.result, .unchanged)
        XCTAssertFalse(plan.replaces)
        XCTAssertEqual(plan.deleteCount, 0)
        XCTAssertEqual(DictationAppleCleanup.contextAfter(plan, contextNow: "Hi." + span), "Hi." + span)
    }

    func testEachSkipSaysWhy() {
        var off = DictationGateSettings.builtIn
        off.appleCleanup = false
        let offPlan = DictationAppleCleanup.plan(span: " um ok", contextNow: "Hi um ok", settings: off)
        XCTAssertEqual(offPlan.result, .off)
        XCTAssertEqual(offPlan.cleaned, "um ok", "nothing ran: the words as Apple typed them")
        XCTAssertNil(offPlan.gate)

        let moved = DictationAppleCleanup.plan(span: " um ok", contextNow: "Hi um ok!!", settings: .builtIn)
        XCTAssertEqual(moved.result, .textChanged)
        XCTAssertEqual(moved.deleteCount, 0)
        XCTAssertNotNil(moved.gate, "the gate still ran, for the record")
        XCTAssertEqual(DictationAppleLog.cleanupDetail(moved), "skipped: text-changed")

        XCTAssertEqual(DictationAppleCleanup.plan(span: "  ", contextNow: "Hi  ", settings: .builtIn).result, .empty)
        XCTAssertEqual(DictationAppleCleanup.plan(span: nil, contextNow: "Hi", settings: .builtIn).result, .contextLost)
        XCTAssertEqual(DictationAppleCleanup.plan(span: " um ok", contextNow: nil, settings: .builtIn).result, .textChanged)
        for result in [offPlan.result, moved.result] {
            XCTAssertFalse(DictationAppleCleanupPlan(result: result, raw: "", cleaned: "", gate: nil, deleteCount: 0, insertText: "").replaces)
        }
        XCTAssertEqual(DictationAppleCleanup.sharedPrefixCount("abc", "abd"), 2)
    }

    // MARK: The setting

    func testKeyboardMicAppleRoutesToAppleWithItsLabel() {
        let value: JSONValue = .object([DictationKeyboardMicMode.settingsField: .string("apple")])
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: value), .apple)
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .apple, hasFullAccess: true, keyboardMicFailed: false), .apple)
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .apple, hasFullAccess: true, keyboardMicFailed: true), .apple)
        XCTAssertNil(DictationKeyboardMicRoute.route(mode: .apple, hasFullAccess: false, keyboardMicFailed: false))
        XCTAssertEqual(DictationKeyboardMicRoute.apple.label, "APPLE MIC")
        XCTAssertEqual(DictationKeyboardMicRoute.apple.runMic, .apple)
        XCTAssertEqual(DictationKeyboardMicRoute.reason(mode: .apple, hasFullAccess: true, keyboardMicFailed: false), "keyboardMic apple")
        XCTAssertEqual(DictationAppleConstants.hint, "Tap 🎙 below")
    }

    func testAppleCleanupIsOnByDefaultAndReadFromTheRecord() throws {
        XCTAssertTrue(DictationGateSettings.builtIn.appleCleanup)
        guard case .object(var fields) = DictationGateSettings.builtIn.recordValue else {
            return XCTFail("not an object")
        }
        XCTAssertEqual(fields[DictationAppleConstants.cleanupField], .bool(true))
        fields[DictationAppleConstants.cleanupField] = .bool(false)
        let off = try XCTUnwrap(DictationGateSettings.from(.object(fields)))
        XCTAssertFalse(off.appleCleanup)
        XCTAssertEqual(off.recordValue[DictationAppleConstants.cleanupField], .bool(false))
        fields[DictationAppleConstants.cleanupField] = .string("yes")
        XCTAssertNil(DictationGateSettings.from(.object(fields)), "not true or false: the record does not fit")
        fields.removeValue(forKey: DictationAppleConstants.cleanupField)
        XCTAssertEqual(DictationGateSettings.from(.object(fields))?.appleCleanup, true)
        fields[DictationKeyboardMicMode.settingsField] = .string("apple")
        XCTAssertEqual(DictationGateSettings.from(.object(fields))?.keyboardMic, .apple)
    }

    // MARK: The record

    private func appleRun(cleanedAt offset: TimeInterval = 2.562) -> DictationAppleRun {
        let finished = DictationAppleFinished(span: " um tell mom", end: .quiet, startedAt: seconds(0), lastChangeAt: seconds(1), signals: [.poll],
                                              signalCounts: [.poll: 3])
        let plan = DictationAppleCleanup.plan(span: " um tell mom", contextNow: "Hi um tell mom", settings: .builtIn)
        return DictationAppleRun(id: "1763800002562-0001", plan: plan, finished: finished, cleanedAt: seconds(offset), thermal: .fair)
    }

    func testAnAppleRunIsSavedAsAKeyboardRunWithMicAppleAndItsCleanup() throws {
        let queued = appleRun()
        let data = try DictationKeyboardHandoff.encode(queued)
        XCTAssertEqual(DictationKeyboardHandoff.decode(DictationAppleRun.self, from: data), queued)
        let run = DictationTestRuns.keyboard(appleRun: queued, modelStatus: "Available")
        XCTAssertEqual(run.source, .keyboard)
        XCTAssertEqual(run.mic, .apple)
        XCTAssertEqual(run.cleanup, .applied)
        XCTAssertEqual(run.dictationEnd, .quiet)
        XCTAssertEqual(run.raw, "um tell mom")
        XCTAssertEqual(run.cleaned, queued.cleaned)
        XCTAssertEqual(run.totalMs, 1562, "last change → cleanup")
        XCTAssertNil(run.releaseToRawMs)
        XCTAssertEqual(run.path, .rule)
        XCTAssertEqual(run.thermal, .fair)
        let value = DictationRunRecord.value(run, device: DictationDeviceInfo(device: "iPhone17,1", ios: "27.1", build: "40"))
        XCTAssertEqual(value["mic"]?.stringValue, "apple")
        XCTAssertEqual(value["cleanup"]?.stringValue, "applied")
        XCTAssertEqual(value["dictationEnd"]?.stringValue, "quiet")
        XCTAssertEqual(value["totalMs"]?.numberValue, 1562)
        XCTAssertNil(value["releaseToRawMs"])
    }

    func testMidasTestSavesEachQueuedAppleRunOnce() throws {
        var saved: [DictationRun] = []
        func keepRun(_ run: DictationRun) {
            saved.append(run)
        }
        let box = mailbox()
        let session = DictationKeyboardSession(settings: Self.builtInSettings, saveRun: keepRun, mailbox: box)
        let queued = appleRun()
        try box.queue(queued, id: queued.id, in: DictationAppleConstants.runsFolder)
        session.saveKeyboardRecords(now: seconds(3))
        session.saveKeyboardRecords(now: seconds(4))
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.mic, .apple)
        XCTAssertEqual(saved.first?.cleanup, .applied)
        XCTAssertTrue(box.queued(DictationAppleRun.self, in: DictationAppleConstants.runsFolder).isEmpty)
    }

    func testTheSummaryCountsAppleMicRuns() {
        let store = LocalRecordStore(fileURL: temporaryFolder.appending(path: "runs.json"))
        let center = DictationTestCenter(store: store, device: DictationDeviceInfo(device: "iPhone17,1", ios: "27.1", build: "40"))
        center.save(DictationTestRuns.keyboard(appleRun: appleRun(cleanedAt: 2), modelStatus: "Available"))
        center.save(DictationTestRuns.keyboard(appleRun: appleRun(cleanedAt: 3), modelStatus: "Available"))
        let summary = store.get(sidekickId: DictationRunRecord.sidekickId, key: DictationRunRecord.summaryKey)
        XCTAssertEqual(summary?["mics"]?["apple"]?["runs"]?.numberValue, 2)
        XCTAssertEqual(summary?["mics"]?["keyboard"]?["runs"]?.numberValue, 0)
        XCTAssertEqual(summary?["mics"]?["app"]?["runs"]?.numberValue, 0)
    }
}
#endif
