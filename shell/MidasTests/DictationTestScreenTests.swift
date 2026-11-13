#if MIDAS_TEST_BUILD
// Dictation test (TEST BUILD, founder 2026-11-13; branch agent/dictation-test, never merged).
// Compiled only against a Test build: run with the "Midas Test" scheme's test action.
import FoundationModels
import XCTest
@testable import Midas

/// The cleanup instruction and prompt, the timing math, the model status mapping and the phrase
/// list of the dictation test screen.
final class DictationTestScreenTests: XCTestCase {
    // MARK: Cleanup instruction and prompt

    func testInstructionNamesEveryCleanupRule() {
        let instructions = DictationCleanup.instructions

        for filler in ["um", "uh", "like", "so"] {
            XCTAssertTrue(instructions.contains(" \(filler),") || instructions.contains(" \(filler) "), "filler \(filler) is named")
        }
        XCTAssertTrue(instructions.contains("self-corrections"))
        XCTAssertTrue(instructions.contains("\"be there at 5 no wait 6\" becomes \"Be there at 6.\""))
        XCTAssertTrue(instructions.contains("punctuation"))
        XCTAssertTrue(instructions.contains("capital letters"))
        XCTAssertTrue(instructions.contains("Keep the person's own words"))
        XCTAssertTrue(instructions.contains("Add nothing"))
        XCTAssertTrue(instructions.contains("plain text"))
    }

    func testPromptCarriesTheTrimmedRawTextVerbatim() {
        let prompt = DictationCleanup.prompt(for: "  uh tell mom im on my way \n")

        XCTAssertEqual(prompt, "Dictated text:\nuh tell mom im on my way")
    }

    func testPromptIsNilForEmptyOrBlankText() {
        XCTAssertNil(DictationCleanup.prompt(for: ""))
        XCTAssertNil(DictationCleanup.prompt(for: "   \n\t"))
    }

    func testReplyLosesWhitespaceAndWrappingQuotes() {
        XCTAssertEqual(DictationCleanup.plainText(fromReply: "\n\"Be there at 6.\"  "), "Be there at 6.")
        XCTAssertEqual(DictationCleanup.plainText(fromReply: "“Tell Mom I'm on my way.”"), "Tell Mom I'm on my way.")
        XCTAssertEqual(DictationCleanup.plainText(fromReply: "Say \"hi\" to Priya."), "Say \"hi\" to Priya.", "quotes inside the text stay")
        XCTAssertEqual(DictationCleanup.plainText(fromReply: "\""), "\"", "a lone quote is not a pair")
    }

    // MARK: Timing math

    func testTimingsFromTheFourMoments() {
        let releasedAt = Date(timeIntervalSince1970: 1_000)
        let timings = DictationTimings(
            releasedAt: releasedAt,
            rawFinalAt: releasedAt.addingTimeInterval(0.412),
            cleanupStartedAt: releasedAt.addingTimeInterval(0.450),
            cleanedAt: releasedAt.addingTimeInterval(1.200)
        )

        XCTAssertEqual(timings.releaseToRawMs, 412)
        XCTAssertEqual(timings.cleanupMs, 750)
        XCTAssertEqual(timings.totalMs, 1200, "total runs from release to cleaned text, gap included")
    }

    func testMillisecondsRoundAndNeverGoNegative() {
        let start = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(DictationTiming.milliseconds(from: start, to: start.addingTimeInterval(0.0016)), 2)
        XCTAssertEqual(DictationTiming.milliseconds(from: start, to: start.addingTimeInterval(-1)), 0)
    }

    func testRunSummaryAverageAndWorst() {
        let summary = DictationRunSummary.make(phrase: "p", durationsMs: [100, 300, 200, 150, 250])

        XCTAssertEqual(summary, DictationRunSummary(phrase: "p", averageMs: 200, worstMs: 300, runCount: 5))
    }

    func testRunSummaryAverageRounds() {
        let summary = DictationRunSummary.make(phrase: "p", durationsMs: [1, 2])

        XCTAssertEqual(summary?.averageMs, 2)
        XCTAssertEqual(summary?.worstMs, 2)
    }

    func testRunSummaryIsNilWithoutRuns() {
        XCTAssertNil(DictationRunSummary.make(phrase: "p", durationsMs: []))
    }

    // MARK: Model status

    func testEveryUnavailableReasonMapsToItsOwnStatus() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("Foundation Models needs iOS 26")
        }
        XCTAssertEqual(DictationModelStatus.from(.available), .available)
        XCTAssertEqual(DictationModelStatus.from(.unavailable(.deviceNotEligible)), .deviceNotEligible)
        XCTAssertEqual(DictationModelStatus.from(.unavailable(.appleIntelligenceNotEnabled)), .appleIntelligenceNotEnabled)
        XCTAssertEqual(DictationModelStatus.from(.unavailable(.modelNotReady)), .modelNotReady)
    }

    func testStatusLabelsSayAvailableOrTheReason() {
        XCTAssertEqual(DictationModelStatus.available.label, "Available")
        XCTAssertEqual(DictationModelStatus.deviceNotEligible.label, "Not available: device not eligible")
        XCTAssertEqual(DictationModelStatus.appleIntelligenceNotEnabled.label, "Not available: Apple Intelligence is off")
        XCTAssertEqual(DictationModelStatus.modelNotReady.label, "Not available: model not ready (downloading)")
        XCTAssertEqual(DictationModelStatus.osTooOld.label, "Not available: needs iOS 26")
        XCTAssertEqual(DictationModelStatus.unavailableOther("x").label, "Not available: x")
        XCTAssertTrue(DictationModelStatus.available.isAvailable)
        XCTAssertFalse(DictationModelStatus.modelNotReady.isAvailable)
    }

    // MARK: Phrases

    func testTheFiveFixedPhrasesInOrder() {
        XCTAssertEqual(DictationTestPhrases.all.count, 5)
        XCTAssertEqual(DictationTestPhrases.all[0], "um so like be there at 5 no wait 6")
        XCTAssertEqual(DictationTestPhrases.all[1], "uh tell mom im on my way")
        XCTAssertEqual(DictationTestPhrases.all[2], "buy eggs milk and uh bread oh and coffee")
        XCTAssertEqual(DictationTestPhrases.all[3], "send the deck to Priya and Tomasz by friday")
        XCTAssertEqual(DictationTestPhrases.all[4], DictationTestPhrases.rambling)
    }

    func testRamblingParagraphIsSixtyWords() {
        let words = DictationTestPhrases.rambling.split(separator: " ")

        XCTAssertEqual(words.count, 60)
    }

    func testRunAllRunsEachPhraseFiveTimes() {
        XCTAssertEqual(DictationTestPhrases.runAllRepeats, 5)
    }
}
#endif
