import SwiftUI
import XCTest
@testable import Midas

// Onboarding changes approved 2026-11-01 (docs/mockups/onboarding-icons-ios27-2026-11-01.html,
// founder: "Okay, this is it, wire it in"): the line is typed with a pause after "The personal
// touch", Get Started waits for the typing, the grid sits 16 pt under the status bar while the
// popup stays where it was, and the icons use Apple's continuous corner.

@MainActor
final class OnboardingTypedLineTests: XCTestCase {
    private let spec = OnboardingIntroSpec.self

    // MARK: Typing the line

    func testNothingIsTypedBeforeTheLineStarts() {
        XCTAssertEqual(OnboardingLineTyping.letters(at: -1), 0)
        XCTAssertEqual(OnboardingLineTyping.letters(at: spec.lineStart), 0)
    }

    func testTheFirstLetterShowsAsSoonAsTypingStarts() {
        let justAfterStart = spec.lineStart + 0.001
        XCTAssertEqual(OnboardingLineTyping.letters(at: justAfterStart), 1)
    }

    func testTypingPausesAfterThePersonalTouch() {
        let firstCount = OnboardingIntroCopy.lineFirstPart.count
        let firstDone = spec.lineStart + CGFloat(firstCount) * spec.secondsPerLetter
        // Inside the pause the first part is all there and nothing more
        let midPause = firstDone + spec.pauseAfterFirstPart / 2
        XCTAssertEqual(OnboardingLineTyping.letters(at: midPause), firstCount)
        let parts = OnboardingLineTyping.split(letters: OnboardingLineTyping.letters(at: midPause))
        XCTAssertEqual(parts.typed, "The personal touch")
        // After the pause the next letter comes
        let afterPause = firstDone + spec.pauseAfterFirstPart + 0.001
        XCTAssertEqual(OnboardingLineTyping.letters(at: afterPause), firstCount + 1)
    }

    func testThePauseIsAboutAFifthOfASecond() {
        XCTAssertEqual(spec.pauseAfterFirstPart, 0.2, accuracy: 0.001)
        XCTAssertTrue(OnboardingIntroCopy.line.hasPrefix(OnboardingIntroCopy.lineFirstPart))
    }

    func testTheWholeLineIsTypedBeforeGetStarted() {
        let typingDone = spec.lineStart + spec.typingSeconds
        XCTAssertEqual(OnboardingLineTyping.letters(at: typingDone), OnboardingIntroCopy.line.count)
        XCTAssertLessThan(typingDone, spec.buttonStart)
        // Get Started has not started while letters are still coming
        let lastLetters = typingDone - spec.secondsPerLetter
        XCTAssertLessThan(OnboardingLineTyping.letters(at: lastLetters), OnboardingIntroCopy.line.count)
        XCTAssertEqual(OnboardingPopupLook.motion(at: lastLetters).button, 0)
        XCTAssertEqual(OnboardingLineTyping.letters(at: 30), OnboardingIntroCopy.line.count)
    }

    func testTheSplitKeepsTheWholeLineSoItNeverShifts() {
        for count in 0...OnboardingIntroCopy.line.count {
            let parts = OnboardingLineTyping.split(letters: count)
            XCTAssertEqual(parts.typed + parts.rest, OnboardingIntroCopy.line)
            XCTAssertEqual(parts.typed.count, count)
        }
        let beyond = OnboardingLineTyping.split(letters: 999)
        XCTAssertEqual(beyond.rest, "")
    }

    func testTheLineIsShownOnceTypingStartsNotFaded() {
        XCTAssertEqual(OnboardingPopupLook.motion(at: spec.lineStart - 0.01).line, 0)
        XCTAssertEqual(OnboardingPopupLook.motion(at: spec.lineStart + 0.01).line, 1)
    }

    func testTheCalmVersionShowsTheWholeLineAtOnce() {
        let driver = OnboardingIntroDriver()
        driver.startCalm(at: Date())
        XCTAssertEqual(driver.lineLetters, OnboardingIntroCopy.line.count)
    }

    func testTheLineWords() {
        XCTAssertEqual(OnboardingIntroCopy.line, "The personal touch your apps need")
        XCTAssertFalse(OnboardingIntroCopy.line.contains("."))
    }

    // MARK: Layout

    func testTheGridSitsSixteenPointsUnderTheStatusBarOnAnyPhone() {
        for safeTop in [CGFloat(47), 59, 62] {
            let sim = OnboardingIntroSim(size: spec.designSize, safeTop: safeTop)
            let firstRowTop = sim.gridSlot(0).y - spec.iconSize / 2
            XCTAssertEqual(firstRowTop - safeTop, 16, accuracy: 0.01)
        }
    }

    func testThePopupStaysWhereItWasWhenTheGridMovedUp() {
        let sim = OnboardingIntroSim(size: spec.designSize, safeTop: 62)
        XCTAssertEqual(sim.cardFrame.minY, 297, accuracy: 0.01)
        // The second row's labels end above the popup
        let secondRowLabelBottom = sim.gridSlot(spec.columns).y + spec.iconSize / 2 + 6 + 15
        XCTAssertLessThan(secondRowLabelBottom, sim.cardFrame.minY)
    }

    // MARK: Icons

    func testIconTilesUseTheHomeGridsContinuousCorner() {
        XCTAssertEqual(OnboardingIconArt.cornerRatio, SidekickIconShape.cornerRatio)
        let half: CGFloat = 30
        let tile = OnboardingIconArt.tilePath(half: half)
        let side = half * 2
        let bounds = CGRect(x: -half, y: -half, width: side, height: side)
        let expected = RoundedRectangle(cornerRadius: side * SidekickIconShape.cornerRatio, style: .continuous).path(in: bounds)
        XCTAssertEqual(tile.boundingRect, expected.boundingRect)
        // Same outline: points near the corner fall inside or outside both alike
        let probes = [CGPoint(x: 29, y: 29), CGPoint(x: 27, y: 27), CGPoint(x: 25, y: 25), CGPoint(x: 29, y: 0), CGPoint(x: 29.9, y: 20)]
        for probe in probes {
            XCTAssertEqual(tile.contains(probe), expected.contains(probe), "\(probe)")
        }
        // Not a sharp square, and not the old 16% plain corner: (27, 27) sits outside the curve
        XCTAssertFalse(tile.contains(CGPoint(x: 27, y: 27)))
    }

    func testTheIconImagesStayReadyOnTheDriver() {
        // The canvas reads the icons from the driver; view state was read stale and drew nothing
        let driver = OnboardingIntroDriver()
        XCTAssertFalse(driver.images.isReady)
        driver.images = OnboardingIconImages.render(for: .light, displayScale: 2)
        XCTAssertTrue(driver.images.isReady)
        XCTAssertEqual(driver.images.colour.count, OnboardingIntroSpec.apps.count)
    }
}
