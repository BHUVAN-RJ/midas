import XCTest
@testable import Midas

// Make's screens, the parts with rules (docs/mockups/make-2026-10-23.html, Confirmed; founder
// 2026-10-23/24): a question card's tap-selects / Send-sends / locks-when-answered (T2), R2's
// Built screen and the tile locking into the grid (hold 1800 ms, move 760 ms, scale 2 to 1 with a
// 94% dip), R3's "already built", and X2's rim flash and toast.

@MainActor
final class MakeMotionTests: XCTestCase {
    // MARK: T2 cards

    func testSendIsOffUntilAPickAndOffAgainOnceAnswered() {
        XCTAssertFalse(MakeQuestionCardState.canSend(isLive: true, selectedId: nil, answer: nil), "tap selects; nothing picked, nothing to send")
        XCTAssertTrue(MakeQuestionCardState.canSend(isLive: true, selectedId: "option001", answer: nil))
        let answer = MakeAnswer(cardId: "card00001", optionId: "option001", text: nil, sentAt: nil)
        XCTAssertFalse(MakeQuestionCardState.canSend(isLive: true, selectedId: "option002", answer: answer), "an answered card is locked")
        XCTAssertFalse(MakeQuestionCardState.canSend(isLive: false, selectedId: "option001", answer: nil), "the founder's read-only card never sends")
    }

    func testOnlyTheSelectionIsMarkedAndAnAnsweredCardFadesTheRest() {
        let live = MakeQuestionCardState.shownSelection(isLive: true, selectedId: "a", answer: nil)
        XCTAssertEqual(live, "a")
        XCTAssertEqual(MakeQuestionCardState.look(optionId: "a", isLive: true, shownSelection: live, isAnswered: false), .picked)
        XCTAssertEqual(MakeQuestionCardState.look(optionId: "b", isLive: true, shownSelection: live, isAnswered: false), .plain, "nothing fades before Send")

        let answer = MakeAnswer(cardId: "c", optionId: "b", text: nil, sentAt: nil)
        let answered = MakeQuestionCardState.shownSelection(isLive: false, selectedId: "a", answer: answer)
        XCTAssertEqual(answered, "b", "the sent answer shows, not a stale selection")
        XCTAssertEqual(MakeQuestionCardState.look(optionId: "b", isLive: false, shownSelection: answered, isAnswered: true), .picked)
        XCTAssertEqual(MakeQuestionCardState.look(optionId: "a", isLive: false, shownSelection: answered, isAnswered: true), .faded)

        // Answered in own words: no option is picked, all fade
        let ownWords = MakeAnswer(cardId: "c", optionId: nil, text: "Both", sentAt: nil)
        let none = MakeQuestionCardState.shownSelection(isLive: false, selectedId: nil, answer: ownWords)
        XCTAssertNil(none)
        XCTAssertEqual(MakeQuestionCardState.look(optionId: "a", isLive: false, shownSelection: none, isAnswered: true), .faded)
    }

    func testDesignLettersAndPictureSize() {
        XCTAssertEqual(MakeCard.letter(at: 0), "A")
        XCTAssertEqual(MakeCard.letter(at: 2), "C")
        XCTAssertEqual(MakeQuestionCardSpec.designWidth, 150)
        XCTAssertEqual(MakeQuestionCardSpec.designHeight, 285)
    }

    // MARK: R2

    func testBuiltTimingIsHold1800Move760() {
        XCTAssertEqual(MakeBuiltMotion.hold, 1.8, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltMotion.move, 0.76, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltMotion.total, 3.06, accuracy: 0.0001)
    }

    func testTheTileHoldsThenMovesScalingTwoToOneWithANinetyFourPercentDip() {
        let start = CGPoint(x: 201, y: 290)
        let end = CGPoint(x: 120, y: 170)
        let holding = MakeBuiltMotion.frame(at: 1.0, start: start, end: end)
        XCTAssertEqual(holding.center, start)
        XCTAssertEqual(holding.scale, 2, accuracy: 0.0001)
        XCTAssertEqual(holding.layerOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(holding.labelOpacity, 0, accuracy: 0.0001)

        // 82% of the move: at the slot, at the bottom of the dip
        let dip = MakeBuiltMotion.frame(at: MakeBuiltMotion.hold + MakeBuiltMotion.move * 0.82, start: start, end: end)
        XCTAssertEqual(dip.center.x, end.x, accuracy: 0.01)
        XCTAssertEqual(dip.center.y, end.y, accuracy: 0.01)
        XCTAssertEqual(dip.scale, 0.94, accuracy: 0.0001)
        XCTAssertEqual(dip.layerOpacity, 0, accuracy: 0.0001, "the Built screen is gone by 40% of the move")

        let locked = MakeBuiltMotion.frame(at: MakeBuiltMotion.hold + MakeBuiltMotion.move, start: start, end: end)
        XCTAssertEqual(locked.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(locked.center.x, end.x, accuracy: 0.01)

        let labelled = MakeBuiltMotion.frame(at: MakeBuiltMotion.hold + MakeBuiltMotion.move + MakeBuiltMotion.labelFade, start: start, end: end)
        XCTAssertEqual(labelled.labelOpacity, 1, accuracy: 0.0001)

        // Half way through the move the tile is between, and still larger than its slot
        let middle = MakeBuiltMotion.frame(at: MakeBuiltMotion.hold + MakeBuiltMotion.move * 0.41, start: start, end: end)
        XCTAssertLessThan(middle.center.x, start.x)
        XCTAssertGreaterThan(middle.center.x, end.x)
        XCTAssertGreaterThan(middle.scale, 1)
        XCTAssertLessThan(middle.scale, 2)
    }

    func testWithoutASlotTheTileStaysAndFadesWithTheScreen() {
        let start = CGPoint(x: 201, y: 290)
        let frame = MakeBuiltMotion.frame(at: MakeBuiltMotion.hold + MakeBuiltMotion.move, start: start, end: nil)
        XCTAssertEqual(frame.center, start)
        XCTAssertEqual(frame.layerOpacity, 0, accuracy: 0.0001)
    }

    func testTheBuiltTileStartsCentredTwiceTheGridSize() {
        let center = MakeBuiltMotion.startCenter(screenWidth: 402)
        XCTAssertEqual(center.x, 201)
        XCTAssertEqual(center.y, 230 + 60, "top 230 pt, 120 pt tall")
    }

    func testTheGridKeepsTheNewSlotEmptyUntilTheTileLocksIn() {
        let stage = MakeBuiltStage()
        let entry = SidekickEntry(id: "plants", name: "Plants", symbolName: "leaf", backgroundHex: "#9CAF88", version: "1")
        let started = Date(timeIntervalSince1970: 1_000)
        stage.play(entry: entry, plan: "Water", now: started, reduceMotion: false)
        XCTAssertEqual(stage.showing?.entry, entry)
        XCTAssertTrue(stage.hidesTile("plants", at: started.addingTimeInterval(1)))
        XCTAssertFalse(stage.hidesTile("reminders", at: started.addingTimeInterval(1)), "only the new Sidekick's slot")
        XCTAssertFalse(stage.hidesTile("plants", at: started.addingTimeInterval(2.6)))

        stage.recordSlot("plants", frame: CGRect(x: 10, y: 20, width: 60, height: 60))
        XCTAssertEqual(stage.slotFrames["plants"], CGRect(x: 10, y: 20, width: 60, height: 60))

        // An older run's end does not stop a newer one
        stage.finish(startedAt: started.addingTimeInterval(-5))
        XCTAssertNotNil(stage.showing)
        stage.finish(startedAt: started)
        XCTAssertNil(stage.showing)
    }

    // MARK: R3

    func testAlreadyBuiltPopsTheTileLandsTheCheckAndFlashesTheEdge() {
        XCTAssertEqual(MakeBuiltCardMotion.tileScale(0), 0.86, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.tileScale(0.45), 1.06, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.tileScale(1), 1, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.checkScale(0.2), 0, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.checkScale(0.6), 1.2, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.checkScale(1), 1, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.edgeOpacity(0.3), 1, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.edgeOpacity(1), 0, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.amount(seconds: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MakeBuiltCardMotion.amount(seconds: 0.9), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(MakeBuiltCardMotion.amount(seconds: 0.3), 0.33, "eased out: quick, then settling")
    }

    // MARK: X2

    func testTheRimFlashesIn900MsAndTheToastShowsFor2600Ms() {
        XCTAssertEqual(RepairUnavailableSpec.rimOpacity(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(RepairUnavailableSpec.rimOpacity(at: 0.27), 1, accuracy: 0.0001)
        XCTAssertEqual(RepairUnavailableSpec.rimOpacity(at: 0.9), 0, accuracy: 0.0001)
        XCTAssertEqual(RepairUnavailableSpec.toastOpacity(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(RepairUnavailableSpec.toastOpacity(at: 1.3), 1, accuracy: 0.0001)
        XCTAssertEqual(RepairUnavailableSpec.toastOpacity(at: 2.6), 0, accuracy: 0.0001)
        XCTAssertEqual(RepairUnavailableSpec.toastOpacity(at: -1), 0, accuracy: 0.0001)
    }

    func testTheToastSaysEditIsNotAvailable() {
        XCTAssertEqual(MakeCopy.notAvailable(), "Edit not available for this Sidekick.")
        XCTAssertEqual(MakeCopy.notAvailable(repairWord: "Change"), "Change not available for this Sidekick.", "the new word for repair swaps in one place")
    }

    func testOneSwipeFlashesTapsThePhoneAndLogsOnce() {
        let flash = RepairUnavailableFlash()
        var logged: [String] = []
        var taps = 0
        func log(_ sidekickId: String) {
            logged.append(sidekickId)
        }
        func tap() {
            taps += 1
        }
        flash.log = log
        flash.haptic = tap
        let started = Date(timeIntervalSince1970: 500)
        XCTAssertFalse(flash.isShowing)
        flash.play(sidekickId: MakeSidekick.id, now: started)
        XCTAssertTrue(flash.isShowing)
        XCTAssertEqual(logged, [MakeSidekick.id])
        XCTAssertEqual(taps, 1)
        XCTAssertEqual(flash.secondsIn(at: started.addingTimeInterval(1)), 1, accuracy: 0.0001)
        flash.finish(startedAt: started)
        XCTAssertFalse(flash.isShowing)
    }
}
