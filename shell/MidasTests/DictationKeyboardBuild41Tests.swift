#if MIDAS_TEST_BUILD
// Build 41: the keyboard experience (TEST BUILD, founder 2026-11-22;
// docs/briefs/dictation-keyboard-test.md, "Build 41"; branch agent/dictation-test, never merged).
// Compiled only against a Test build: run with the "Midas Test" scheme's test action.
//
// keyboardMic "apple": the numbers-first keyboard (Wispr Flow's layout), ABC going to the next
// keyboard, Apple's sound per key kind with a light haptic, ✕ cancel deleting exactly what the
// running dictation typed (or saying why not), undo for cleanups and cancels, and the motion with
// and without Reduce Motion.
import XCTest
@testable import Midas

final class DictationKeyboardBuild41Tests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_763_850_000)

    private func seconds(_ offset: TimeInterval) -> Date {
        startedAt.addingTimeInterval(offset)
    }

    // MARK: Layout pages

    func testOpensOnNumbersWithWisprFlowRows() {
        let layout = DictationNumbersLayout()
        XCTAssertEqual(layout.page, .numbers)
        XCTAssertEqual(layout.rows[0], ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        XCTAssertEqual(layout.rows[1], ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
        XCTAssertEqual(layout.rows[2], [".", ",", "?", "!", "'"])
        XCTAssertEqual(layout.pageKeyLabel, "#+=")
    }

    func testHashPlusEqualsTogglesApplesSecondSymbolsPage() {
        var layout = DictationNumbersLayout()
        XCTAssertEqual(layout.handle(.symbols), [])
        XCTAssertEqual(layout.page, .symbols)
        XCTAssertEqual(layout.rows[0], ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
        XCTAssertEqual(layout.rows[1], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"])
        XCTAssertEqual(layout.rows[2], [".", ",", "?", "!", "'"])
        XCTAssertEqual(layout.pageKeyLabel, "123")
        XCTAssertEqual(layout.handle(.symbols), [])
        XCTAssertEqual(layout.page, .numbers, "the same key goes back")
        _ = layout.handle(.symbols)
        XCTAssertEqual(layout.handle(.numbers), [])
        XCTAssertEqual(layout.page, .numbers)
    }

    func testEachAppearanceStartsOnNumbers() {
        var layout = DictationNumbersLayout()
        _ = layout.handle(.symbols)
        layout.appeared()
        XCTAssertEqual(layout.page, .numbers)
    }

    func testTypingKeysInsertAsTheyAre() {
        var layout = DictationNumbersLayout()
        XCTAssertEqual(layout.handle(.character("7")), [.insert("7")])
        XCTAssertEqual(layout.handle(.character("@")), [.insert("@")])
        XCTAssertEqual(layout.handle(.space), [.insert(" ")])
        XCTAssertEqual(layout.handle(.returnKey), [.insert("\n")])
        XCTAssertEqual(layout.handle(.backspace), [.deleteBackward])
    }

    func testNoLettersPageAndNoMidasListenKey() {
        var layout = DictationNumbersLayout()
        XCTAssertEqual(layout.handle(.shift), [])
        XCTAssertEqual(layout.handle(.shiftLock), [])
        XCTAssertEqual(layout.handle(.listen), [], "Apple's 🎙 listens, not a Midas key")
        XCTAssertEqual(layout.page, .numbers)
        XCTAssertEqual(DictationNumbersPage.allCases, [.numbers, .symbols])
    }

    // MARK: ABC → next keyboard

    func testABCGoesToTheNextKeyboardAndStaysOnItsPage() {
        var layout = DictationNumbersLayout()
        _ = layout.handle(.symbols)
        XCTAssertEqual(layout.handle(.abc), [.nextKeyboard])
        XCTAssertEqual(layout.page, .symbols, "coming back via 🌐 finds the same page")
        XCTAssertEqual(layout.handle(.nextKeyboard), [.nextKeyboard], "🌐 where iOS draws none")
    }

    // MARK: Sound per key kind

    func testEachKeyKindGetsApplesOwnSound() {
        XCTAssertEqual(DictationKeyKind.of(.character("1")), .character)
        XCTAssertEqual(DictationKeyKind.of(.backspace), .delete)
        let modifiers: [DictationKeyboardControl] = [.shift, .shiftLock, .symbols, .numbers, .abc, .returnKey, .space, .nextKeyboard, .listen]
        for control in modifiers {
            XCTAssertEqual(DictationKeyKind.of(control), .modifier, "\(control)")
        }
        XCTAssertEqual(DictationKeyKind.character.systemSoundID, 1104)
        XCTAssertEqual(DictationKeyKind.delete.systemSoundID, 1155)
        XCTAssertEqual(DictationKeyKind.modifier.systemSoundID, 1156)
    }

    func testWithFullAccessEveryKeyPlaysItsSoundAndALightHaptic() {
        let character = DictationKeyboardFeedbackPlan.forKey(.character, hasFullAccess: true)
        XCTAssertEqual(character.sound, .system(1104))
        XCTAssertEqual(character.haptic, .light)
        XCTAssertEqual(DictationKeyboardFeedbackPlan.forKey(.delete, hasFullAccess: true).sound, .system(1155))
        XCTAssertEqual(DictationKeyboardFeedbackPlan.forKey(.modifier, hasFullAccess: true).sound, .system(1156))
    }

    func testWithoutFullAccessOnlyTheInputClickAndNoHaptic() {
        for kind in DictationKeyKind.allCases {
            let plan = DictationKeyboardFeedbackPlan.forKey(kind, hasFullAccess: false)
            XCTAssertEqual(plan.sound, .inputClick)
            XCTAssertNil(plan.haptic)
        }
    }

    func testListeningAndLandingGetASoftHapticAndNoSound() {
        let started = DictationKeyboardFeedbackPlan.forMoment(.listeningStarted, hasFullAccess: true)
        XCTAssertEqual(started.haptic, .soft)
        XCTAssertNil(started.sound)
        XCTAssertEqual(DictationKeyboardFeedbackPlan.forMoment(.textLanded, hasFullAccess: true).haptic, .soft)
        XCTAssertNil(DictationKeyboardFeedbackPlan.forMoment(.textLanded, hasFullAccess: false).haptic)
    }

    func testTheKeyboardLogSaysWhatCanPlay() {
        let on = DictationKeyboardFeedbackPlan.availabilityDetail(hasFullAccess: true, inputClicksEnabled: true, reduceMotion: false)
        XCTAssertTrue(on.contains("full access on"))
        XCTAssertTrue(on.contains("1104/1155/1156"))
        XCTAssertTrue(on.contains("input clicks enabled"))
        XCTAssertTrue(on.contains("Keyboard Clicks"))
        XCTAssertTrue(on.contains("reduce motion off"))
        let off = DictationKeyboardFeedbackPlan.availabilityDetail(hasFullAccess: false, inputClicksEnabled: false, reduceMotion: true)
        XCTAssertTrue(off.contains("haptics off"))
        XCTAssertTrue(off.contains("input clicks not enabled"))
        XCTAssertTrue(off.contains("reduce motion on"))
    }

    // MARK: Cancel ✕

    func testCancelDeletesExactlyWhatTheDictationTyped() {
        let plan = DictationAppleCancel.plan(span: " um tell mom", contextNow: "Hi um tell mom")
        XCTAssertEqual(plan.result, .deleted)
        XCTAssertEqual(plan.deleteCount, 12)
        XCTAssertEqual(plan.removed, " um tell mom")
        XCTAssertEqual(plan.contextAfter("Hi um tell mom"), "Hi")
        XCTAssertEqual(plan.detail, "deleted 12")
    }

    func testCancelSkipsWhenTheTextNoLongerEndsWithTheSpan() {
        let plan = DictationAppleCancel.plan(span: " um tell mom", contextNow: "Hi um tell mom!")
        XCTAssertEqual(plan.result, .textChanged)
        XCTAssertEqual(plan.deleteCount, 0)
        XCTAssertEqual(plan.contextAfter("Hi um tell mom!"), "Hi um tell mom!")
        XCTAssertEqual(plan.detail, "skipped: text-changed")
        XCTAssertEqual(DictationAppleCancel.plan(span: " hi", contextNow: nil).result, .textChanged)
    }

    func testCancelSkipsAnUnknownSpanAndAnEmptyOne() {
        XCTAssertEqual(DictationAppleCancel.plan(span: nil, contextNow: "Hi there").result, .contextLost)
        XCTAssertEqual(DictationAppleCancel.plan(span: nil, contextNow: "Hi there").deleteCount, 0)
        XCTAssertEqual(DictationAppleCancel.plan(span: "", contextNow: "Hi").result, .empty)
        XCTAssertEqual(DictationAppleCancelResult.allCases.map(\.rawValue), ["deleted", "text-changed", "context-lost", "empty"])
    }

    func testCancelUsesTheTrackersSpanFromASignalSequence() {
        var tracker = DictationAppleTracker()
        tracker.reset(context: "Hi", after: "")
        _ = tracker.observed(context: "Hi um", after: "", by: .poll, at: seconds(1))
        _ = tracker.observed(context: "Hi um tell", after: "", by: .textDidChange, at: seconds(1.3))
        XCTAssertEqual(tracker.phase, .dictating)
        let plan = DictationAppleCancel.plan(span: tracker.span, contextNow: "Hi um tell")
        XCTAssertEqual(plan.result, .deleted)
        XCTAssertEqual(plan.contextAfter("Hi um tell"), "Hi")
    }

    // MARK: Undo

    func testUndoPutsBackWhatAppleTypedAfterACleanup() {
        let contextNow = "Hi um tell mom"
        let plan = DictationAppleCleanup.plan(span: " um tell mom", contextNow: contextNow, settings: .builtIn)
        XCTAssertTrue(plan.replaces, "the built-in gate removes um")
        let contextAfter = DictationAppleCleanup.contextAfter(plan, contextNow: contextNow)
        var undo = DictationKeyboardUndo()
        XCTAssertFalse(undo.canUndo)
        undo.record(DictationKeyboardEdit(removed: String(" um tell mom".suffix(plan.deleteCount)), added: plan.insertText, contextAfter: contextAfter))
        XCTAssertTrue(undo.canUndo)
        let undone = undo.undo(contextNow: contextAfter)
        XCTAssertEqual(undone.result, .undone)
        XCTAssertEqual(undone.deleteCount, plan.insertText.count)
        XCTAssertEqual(undone.contextAfter, contextNow)
        XCTAssertFalse(undo.canUndo)
    }

    func testUndoPutsBackACancelledDictation() {
        var undo = DictationKeyboardUndo()
        undo.record(DictationKeyboardEdit(removed: " um tell mom", added: "", contextAfter: "Hi"))
        let undone = undo.undo(contextNow: "Hi")
        XCTAssertEqual(undone.result, .undone)
        XCTAssertEqual(undone.deleteCount, 0)
        XCTAssertEqual(undone.insertText, " um tell mom")
        XCTAssertEqual(undone.contextAfter, "Hi um tell mom")
    }

    func testUndoSkipsWhenTheTextChangedAndDropsOlderEdits() {
        var undo = DictationKeyboardUndo()
        undo.record(DictationKeyboardEdit(removed: " a", added: "", contextAfter: "Hi"))
        undo.record(DictationKeyboardEdit(removed: " b", added: "", contextAfter: "Hi"))
        let skipped = undo.undo(contextNow: "Hi there")
        XCTAssertEqual(skipped.result, .textChanged)
        XCTAssertEqual(skipped.deleteCount, 0)
        XCTAssertEqual(skipped.insertText, "")
        XCTAssertFalse(undo.canUndo)
        XCTAssertEqual(undo.undo(contextNow: "Hi").result, .nothing)
    }

    func testUndoMatchesALongTextByItsLastFortyCharacters() {
        let long = String(repeating: "x", count: 30) + "the quick brown fox jumps over the lazy dog."
        var undo = DictationKeyboardUndo()
        undo.record(DictationKeyboardEdit(removed: " um", added: "", contextAfter: long))
        // iOS's window dropped text from the front: the same last 40 characters
        let windowed = String(long.dropFirst(20))
        XCTAssertEqual(undo.undo(contextNow: windowed).result, .undone)
        var short = DictationKeyboardUndo()
        short.record(DictationKeyboardEdit(removed: " um", added: "", contextAfter: "Hi"))
        XCTAssertEqual(short.undo(contextNow: "i").result, .textChanged, "a short text must match whole")
    }

    func testUndoKeepsTheLastTen() {
        var undo = DictationKeyboardUndo()
        for index in 0..<12 {
            undo.record(DictationKeyboardEdit(removed: String(index), added: "", contextAfter: "Hi"))
        }
        XCTAssertEqual(undo.edits.count, 10)
        XCTAssertEqual(undo.edits.first?.removed, "2")
        undo.clear()
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: Reduce Motion

    func testKeysAndListeningSwapWithA250MsSpringWithoutBounce() {
        let motion = DictationKeyboardMotion.forReduceMotion(false)
        XCTAssertEqual(motion.duration, 0.25)
        XCTAssertTrue(motion.slides)
        XCTAssertEqual(motion.bounce, 0)
    }

    func testReduceMotionCrossFadesOnly() {
        let motion = DictationKeyboardMotion.forReduceMotion(true)
        XCTAssertFalse(motion.slides)
        XCTAssertLessThan(motion.duration, 0.25)
        XCTAssertEqual(motion.bounce, 0)
    }

    // MARK: Constants

    func testTheKeyboardFitsTheTopBarAndFourAppleSizedRows() {
        let rows = 4 * 42.0 + 3 * 11.0
        XCTAssertGreaterThanOrEqual(DictationKeyboardExperienceConstants.keyboardHeight, DictationKeyboardExperienceConstants.topBarHeight + rows)
        XCTAssertEqual(DictationKeyboardExperienceConstants.topBarHeight, 44, "a 44 pt tap target")
        XCTAssertEqual(DictationKeyboardExperienceConstants.cancelWatch, 3.0)
    }
}
#endif
