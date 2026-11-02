import SwiftUI
import XCTest
@testable import Midas

// Sign in on the Midas popup (founder, 2026-11-01: "We're merging 1 and 2 into one";
// docs/mockups/onboarding-signin-popup-2026-11-01.html): after the typed line the popup shows a
// name, Get Started and Sign In; the icons behind blur a little as "Midas" comes in; the popup
// lifts above the keyboard; the teaching cards still follow the sign in.

@MainActor
final class OnboardingSignInPopupTests: XCTestCase {
    private let spec = OnboardingIntroSpec.self
    private var defaults: UserDefaults!
    private let suiteName = "OnboardingSignInPopupTests"
    private let user = MidasUser(id: "u1", name: "Bhuvan")

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Words

    func testThePopupUsesTheWelcomeScreensWords() {
        XCTAssertEqual(OnboardingIntroCopy.namePlaceholder, "Name")
        XCTAssertEqual(OnboardingIntroCopy.button, "Get Started")
        XCTAssertEqual(OnboardingIntroCopy.signIn, "Sign In")
        XCTAssertEqual(OnboardingIntroCopy.namePlaceholder, WelcomeCopy.namePlaceholder)
        XCTAssertEqual(OnboardingIntroCopy.signIn, WelcomeCopy.returningUserButton)
    }

    // MARK: Get Started needs a name

    func testGetStartedWaitsForAName() {
        XCTAssertFalse(OnboardingSignInRules.canGetStarted(name: "", isWorking: false))
        XCTAssertFalse(OnboardingSignInRules.canGetStarted(name: "   ", isWorking: false))
        XCTAssertTrue(OnboardingSignInRules.canGetStarted(name: "Bhuvan", isWorking: false))
        // Not twice while a sign in is running
        XCTAssertFalse(OnboardingSignInRules.canGetStarted(name: "Bhuvan", isWorking: true))
    }

    // MARK: The popup

    func testThePopupIsTallerAndStillStartsAt297() {
        let sim = OnboardingIntroSim(size: spec.designSize, safeTop: 62)
        XCTAssertEqual(sim.cardFrame.minY, 297, accuracy: 0.01)
        XCTAssertEqual(sim.cardFrame.height, 344)
        XCTAssertLessThan(sim.cardFrame.maxY, spec.designSize.height - 100)
    }

    func testTheFormComesInAfterTheLineIsTyped() {
        let typingDone = spec.lineStart + spec.typingSeconds
        XCTAssertEqual(OnboardingPopupLook.motion(at: typingDone).button, 0)
        XCTAssertEqual(OnboardingPopupLook.motion(at: spec.buttonStart + spec.buttonFade).button, 1, accuracy: 0.001)
    }

    func testThePopupLiftsAboveTheKeyboardAndOnlyThen() {
        let sim = OnboardingIntroSim(size: spec.designSize, safeTop: 62)
        let card = sim.cardFrame
        let screen = spec.designSize.height
        XCTAssertEqual(OnboardingPopupLift.offset(card: card, screenHeight: screen, keyboardHeight: 0), 0)
        let lift = OnboardingPopupLift.offset(card: card, screenHeight: screen, keyboardHeight: 336)
        XCTAssertLessThan(lift, 0)
        XCTAssertEqual(card.maxY + lift, screen - 336 - spec.cardAboveKeyboard, accuracy: 0.01)
        // A keyboard that does not reach the popup never pushes it down
        XCTAssertEqual(OnboardingPopupLift.offset(card: card, screenHeight: screen, keyboardHeight: 100), 0)
    }

    // MARK: The blur behind

    func testIconsBlurAsMidasComesIn() {
        XCTAssertEqual(OnboardingPopupLook.motion(at: -1).backBlur, 0)
        XCTAssertEqual(OnboardingPopupLook.motion(at: spec.wordmarkStart).backBlur, 0, accuracy: 0.001)
        let midway = OnboardingPopupLook.motion(at: spec.wordmarkStart + spec.wordFade / 2).backBlur
        XCTAssertGreaterThan(midway, 0)
        XCTAssertLessThan(midway, spec.backBlur)
        XCTAssertEqual(OnboardingPopupLook.motion(at: spec.buttonStart).backBlur, spec.backBlur, accuracy: 0.001)
        XCTAssertEqual(spec.backBlur, 4)
        // The calm version blurs too, once its popup is in
        XCTAssertEqual(OnboardingCalmTimeline.popup(at: 30).backBlur, spec.backBlur, accuracy: 0.001)
    }

    // MARK: Order of screens

    func testSigningInFromThePopupKeepsTheIntroThenShowsTheCards() {
        let progress = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertEqual(progress.stage(for: .signedOut), .intro)
        progress.signInFromIntro()
        // Passkey sheet up, or closed: still the popup, not the welcome screen
        XCTAssertEqual(progress.stage(for: .signedOut), .intro)
        progress.noteAuthState(.signedIn(user))
        XCTAssertEqual(progress.stage(for: .signedIn(user)), .teach)
        progress.finishTeach()
        XCTAssertEqual(progress.stage(for: .signedIn(user)), .home)
    }

    func testAfterSigningOutTheWelcomeScreenShowsNotTheIntro() {
        let progress = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        progress.signInFromIntro()
        progress.noteAuthState(.signedIn(user))
        progress.finishTeach()
        // Sign Out in the same launch
        let relaunched = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertEqual(relaunched.stage(for: .signedOut), .welcome)
    }

    func testClosingTheAppBeforeSigningInShowsTheWelcomeScreenNextTime() {
        let first = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        first.signInFromIntro()
        let next = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertEqual(next.stage(for: .signedOut), .welcome)
        // Signing in there still brings the cards, once
        XCTAssertEqual(next.stage(for: .signedIn(user)), .teach)
    }
}
