import SwiftUI
import UIKit
import XCTest
@testable import Midas

// The Editing tag cycles its word (founder, 2026-11-23, docs/PRODUCT.md on main 130a76a): while a
// code repair runs, the tag word cycles Reading… → Editing… → Checking… → Finishing… (about 2.5 s
// each, looping); the orb and the X stay. A question, Changed, Couldn't fix and Tap to update keep
// their own words. Founder: "Right now, it's always editing. Let's make sure that we have a few
// states and it cycles between those states."

@MainActor
final class RepairTagCycleTests: XCTestCase {
    private let editing = RepairTagDisplay.repairing(count: 1, takingLonger: false)

    // MARK: Words and timing

    func testWordsAreTheFoundersFourInOrder() {
        XCTAssertEqual(RepairTagCycle.words, ["Reading…", "Editing…", "Checking…", "Finishing…"])
        XCTAssertEqual(RepairTagCycle.stepSeconds, 2.5, accuracy: 0.001)
    }

    func testWordsFollowEachOtherEveryStep() {
        XCTAssertEqual(RepairTagCycle.word(at: 0), "Reading…")
        XCTAssertEqual(RepairTagCycle.word(at: 2.4), "Reading…")
        XCTAssertEqual(RepairTagCycle.word(at: 2.5), "Editing…")
        XCTAssertEqual(RepairTagCycle.word(at: 4.9), "Editing…")
        XCTAssertEqual(RepairTagCycle.word(at: 5.0), "Checking…")
        XCTAssertEqual(RepairTagCycle.word(at: 7.6), "Finishing…")
    }

    func testCycleLoopsBackToReading() {
        XCTAssertEqual(RepairTagCycle.word(at: 10.0), "Reading…")
        XCTAssertEqual(RepairTagCycle.word(at: 12.6), "Editing…")
        XCTAssertEqual(RepairTagCycle.word(at: 10 * 60 - 0.1), "Finishing…", "still turning after many loops")
    }

    func testBeforeTheStartItIsTheFirstWord() {
        XCTAssertEqual(RepairTagCycle.word(at: -3), "Reading…", "during On it the cycle has not started")
    }

    func testCountFollowsTheWordWhenASecondEditWaits() {
        XCTAssertEqual(RepairTagCycle.word(at: 0, count: 2), "Reading… 2")
        XCTAssertEqual(RepairTagCycle.word(at: 2.6, count: 2), "Editing… 2")
        XCTAssertEqual(RepairTagCycle.word(at: 0, count: 1), "Reading…")
    }

    // MARK: Crossfade and Reduce Motion

    func testNewWordCrossfadesIn() {
        let midFade = RepairTagCycle.look(at: 2.5 + RepairTagCycle.crossFadeSeconds / 2, reduceMotion: false)
        XCTAssertEqual(midFade.from, "Reading…")
        XCTAssertEqual(midFade.to, "Editing…")
        XCTAssertGreaterThan(midFade.mix, 0)
        XCTAssertLessThan(midFade.mix, 1)
        let settled = RepairTagCycle.look(at: 2.5 + RepairTagCycle.crossFadeSeconds + 0.05, reduceMotion: false)
        XCTAssertEqual(settled, RepairTagCycle.Look(from: "Editing…", to: "Editing…", mix: 1))
    }

    func testLoopCrossfadesFromFinishingToReading() {
        let looping = RepairTagCycle.look(at: 10.05, reduceMotion: false)
        XCTAssertEqual(looping.from, "Finishing…")
        XCTAssertEqual(looping.to, "Reading…")
    }

    func testFirstWordShowsWithoutFade() {
        XCTAssertEqual(RepairTagCycle.look(at: 0.05, reduceMotion: false), RepairTagCycle.Look(from: "Reading…", to: "Reading…", mix: 1))
    }

    func testReduceMotionStillCyclesWithoutCrossfade() {
        let changing = RepairTagCycle.look(at: 2.55, reduceMotion: true)
        XCTAssertEqual(changing, RepairTagCycle.Look(from: "Editing…", to: "Editing…", mix: 1))
        XCTAssertEqual(RepairTagCycle.look(at: 5.05, reduceMotion: true).to, "Checking…")
    }

    // MARK: Width

    func testWordsWidthFitsTheLongestWordSoTheTagDoesNotJump() {
        let font = UIFont.systemFont(ofSize: RepairTagSpec.fontSize, weight: .semibold)
        var widest: CGFloat = 0
        for word in RepairTagCycle.words {
            let measured = (word as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
            XCTAssertGreaterThanOrEqual(RepairTagCycle.wordsWidth(), measured, word)
            widest = max(widest, measured)
        }
        XCTAssertEqual(RepairTagCycle.wordsWidth(), widest, "no wider than the longest word")
        XCTAssertGreaterThan(RepairTagCycle.wordsWidth(count: 2), RepairTagCycle.wordsWidth(), "room for the count")
    }

    // MARK: When it plays

    func testCyclesOnlyWhileACodeRepairRuns() {
        XCTAssertTrue(RepairTagCycle.cycles(editing))
        XCTAssertTrue(RepairTagCycle.cycles(.repairing(count: 2, takingLonger: false)))
        XCTAssertFalse(RepairTagCycle.cycles(.repairing(count: 1, takingLonger: true)), "Taking longer keeps its words")
        let others: [RepairTagDisplay] = [
            .repairMode,
            .question,
            .changed,
            .undone,
            .couldntFix,
            .fixed(onPage: true, summary: nil),
            .fixed(onPage: false, summary: nil),
            .alreadyThere(summary: nil),
            .laneMessage("Not something I can change")
        ]
        for display in others {
            XCTAssertFalse(RepairTagCycle.cycles(display), "\(display)")
        }
    }

    func testOnItAndLayerWordsDoNotCycle() {
        XCTAssertTrue(RepairTagCycle.plays(display: editing, shownWords: editing.words))
        XCTAssertFalse(RepairTagCycle.plays(display: editing, shownWords: RepairTagCopy.onIt), "On it shows first after Send")
        XCTAssertFalse(RepairTagCycle.plays(display: .repairMode, shownWords: RepairAskBackCopy.oneQuestion))
    }

    func testStopsCyclingWhenTheStateLeavesEditing() {
        let running = RepairTagView(display: editing, onTap: {}, onCancel: {})
        XCTAssertTrue(running.cyclesWords)
        let question = RepairTagView(display: .question, onTap: {}, onCancel: {})
        XCTAssertFalse(question.cyclesWords)
        let tapToUpdate = RepairTagView(display: .fixed(onPage: true, summary: nil), onTap: {})
        XCTAssertFalse(tapToUpdate.cyclesWords)
        let deeperLook = RepairTagView(display: .couldntFix, onTap: {}, onCancel: {})
        XCTAssertFalse(deeperLook.cyclesWords)
        let changed = RepairTagView(display: .changed, onTap: {}, onUndo: {})
        XCTAssertFalse(changed.cyclesWords)
    }

    func testOtherStatesKeepTheirOwnWords() {
        XCTAssertEqual(RepairTagDisplay.question.words, "1 question")
        XCTAssertEqual(RepairTagDisplay.changed.words, "Changed")
        XCTAssertEqual(RepairTagDisplay.couldntFix.words, "Taking a Deeper Look")
        XCTAssertEqual(RepairTagDisplay.fixed(onPage: true, summary: nil).words, "Edit done. Tap to update")
    }

    // MARK: The X stays

    func testXStaysOnTheCyclingTag() {
        let running = RepairTagView(display: editing, onTap: {}, onCancel: {}, cycleStartedAt: Date())
        XCTAssertTrue(running.cyclesWords)
        XCTAssertTrue(running.showsCancel, "the X stays while the words cycle")
        let queued = RepairTagView(display: .repairing(count: 2, takingLonger: false), onTap: {}, onCancel: {}, cycleStartedAt: nil)
        XCTAssertTrue(queued.showsCancel)
    }

    func testXCancelsTheCyclingTag() {
        var cancelled = 0
        let running = RepairTagView(display: editing, onTap: {}, onCancel: { cancelled += 1 }, cycleStartedAt: Date())
        running.onCancel?()
        XCTAssertEqual(cancelled, 1)
    }

    // MARK: Start

    func testCycleStartsRightAfterOnIt() {
        let sent = Date(timeIntervalSinceReferenceDate: 1_000)
        let start = RepairTagCycle.startDate(lastSendAt: sent, pendingSentAt: nil)
        XCTAssertEqual(start, sent.addingTimeInterval(RepairTagSpec.onItSeconds))
    }

    func testCycleOnReturnCountsFromTheEditsSend() {
        let pendingSent = Date(timeIntervalSinceReferenceDate: 500)
        XCTAssertEqual(RepairTagCycle.startDate(lastSendAt: nil, pendingSentAt: pendingSent), pendingSent.addingTimeInterval(RepairTagSpec.onItSeconds))
        let screenSent = Date(timeIntervalSinceReferenceDate: 900)
        XCTAssertEqual(RepairTagCycle.startDate(lastSendAt: screenSent, pendingSentAt: pendingSent), screenSent.addingTimeInterval(RepairTagSpec.onItSeconds), "this screen's Send wins")
        XCTAssertNil(RepairTagCycle.startDate(lastSendAt: nil, pendingSentAt: nil))
    }
}
