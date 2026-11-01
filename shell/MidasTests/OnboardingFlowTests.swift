import XCTest
@testable import Midas

// Onboarding (founder, 2026-10-31; docs/briefs/onboarding-build.md): the black hole intro once per
// user before sign in, then WelcomeView, then the four teaching cards; never shown to anyone
// already signed in. These checks cover the order, the once-per-user memory, the intro's physics
// and timings, the Reduce Motion version and the words.

@MainActor
final class OnboardingFlowTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingFlowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private let user = MidasUser(id: "u1", name: "Bhuvan")

    // MARK: Order of screens

    func testStagesFollowSignInStateAndMemory() {
        XCTAssertEqual(OnboardingRules.stage(for: .checking, introSeen: false, teachSeen: false), .checking)
        XCTAssertEqual(OnboardingRules.stage(for: .signedOut, introSeen: false, teachSeen: false), .intro)
        XCTAssertEqual(OnboardingRules.stage(for: .signedOut, introSeen: true, teachSeen: false), .welcome)
        XCTAssertEqual(OnboardingRules.stage(for: .signedOut, introSeen: true, teachSeen: true), .welcome)
        XCTAssertEqual(OnboardingRules.stage(for: .signedIn(user), introSeen: true, teachSeen: false), .teach)
        XCTAssertEqual(OnboardingRules.stage(for: .signedIn(user), introSeen: true, teachSeen: true), .home)
        // Signed in without ever seeing the intro: a user from before onboarding, straight home
        XCTAssertEqual(OnboardingRules.stage(for: .signedIn(user), introSeen: false, teachSeen: false), .home)
    }

    func testOnlySignedInUsersWhoNeverSawTheIntroAreMarkedExisting() {
        XCTAssertTrue(OnboardingRules.marksExistingUser(for: .signedIn(user), introSeen: false))
        XCTAssertFalse(OnboardingRules.marksExistingUser(for: .signedIn(user), introSeen: true))
        XCTAssertFalse(OnboardingRules.marksExistingUser(for: .signedOut, introSeen: false))
        XCTAssertFalse(OnboardingRules.marksExistingUser(for: .checking, introSeen: false))
    }

    func testNewUserGoesIntroWelcomeTeachHome() {
        let progress = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertEqual(progress.stage(for: .signedOut), .intro)
        progress.finishIntro()
        XCTAssertEqual(progress.stage(for: .signedOut), .welcome)
        progress.noteAuthState(.signedIn(user))
        XCTAssertEqual(progress.stage(for: .signedIn(user)), .teach)
        progress.finishTeach()
        XCTAssertEqual(progress.stage(for: .signedIn(user)), .home)
    }

    func testOnboardingIsRememberedAcrossLaunches() {
        let first = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        first.finishIntro()
        let second = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertEqual(second.stage(for: .signedOut), .welcome)
        XCTAssertEqual(second.stage(for: .signedIn(user)), .teach)
        second.finishTeach()
        let third = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertEqual(third.stage(for: .signedIn(user)), .home)
        XCTAssertTrue(defaults.bool(forKey: OnboardingMemory.introSeenKey))
        XCTAssertTrue(defaults.bool(forKey: OnboardingMemory.teachSeenKey))
    }

    func testExistingSignedInUserNeverSeesIntroOrCardsEvenAfterSigningOut() {
        let progress = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        progress.noteAuthState(.signedIn(user))
        XCTAssertEqual(progress.stage(for: .signedIn(user)), .home)
        XCTAssertEqual(progress.stage(for: .signedOut), .welcome)
        let relaunched = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        XCTAssertEqual(relaunched.stage(for: .signedOut), .welcome)
        XCTAssertEqual(relaunched.stage(for: .signedIn(user)), .home)
    }

    func testSigningOutDoesNotMarkAnything() {
        let progress = OnboardingProgress(memory: OnboardingMemory(defaults: defaults))
        progress.noteAuthState(.signedOut)
        progress.noteAuthState(.checking)
        XCTAssertFalse(progress.introSeen)
        XCTAssertFalse(progress.teachSeen)
        XCTAssertEqual(progress.stage(for: .signedOut), .intro)
    }

    // MARK: The intro's physics

    private func makeSim() -> OnboardingIntroSim {
        OnboardingIntroSim(size: CGSize(width: 402, height: 874), safeTop: 62)
    }

    func testHeldPressReachesTheGridInAboutTwoAndAHalfSeconds() {
        var sim = makeSim()
        sim.press(at: CGPoint(x: 201, y: 437))
        sim.advance(by: 2.3)
        XCTAssertNotEqual(sim.mode, .home, "too fast: the brief has touch to grid at about 2.5 s")
        sim.advance(by: 0.4)
        XCTAssertEqual(sim.mode, .home)
        XCTAssertEqual(sim.burstTaps, 1)
    }

    func testAfterTheBlastEveryIconSitsInItsSlotInColour() {
        var sim = makeSim()
        sim.press(at: CGPoint(x: 120, y: 500))
        sim.advance(by: 3.2)
        XCTAssertEqual(sim.mode, .home)
        for body in sim.bodies {
            let slot = sim.gridSlot(body.index)
            XCTAssertEqual(body.position.x, slot.x, accuracy: 0.01)
            XCTAssertEqual(body.position.y, slot.y, accuracy: 0.01)
            XCTAssertEqual(body.colourIn, 1, accuracy: 0.001)
            XCTAssertEqual(body.rotation, 0, accuracy: 0.001)
            XCTAssertTrue(body.isPolished)
            XCTAssertFalse(body.isInside)
        }
        XCTAssertEqual(sim.holeRadius, 0)
        XCTAssertEqual(sim.labelsAlpha, 1, accuracy: 0.001)
    }

    func testIconsStayGreyWhileFloatingAndCharging() {
        var sim = makeSim()
        sim.advance(by: 1)
        sim.press(at: CGPoint(x: 201, y: 437))
        sim.advance(by: 1)
        XCTAssertEqual(sim.mode, .charging)
        for body in sim.bodies {
            XCTAssertFalse(body.isPolished)
            XCTAssertEqual(body.colourIn, 0)
        }
    }

    func testLettingGoEarlyCollapsesBackToFloating() {
        var sim = makeSim()
        sim.press(at: CGPoint(x: 201, y: 437))
        sim.advance(by: 0.6)
        XCTAssertGreaterThan(sim.holeRadius, 6)
        sim.liftFinger()
        sim.advance(by: 1)
        XCTAssertEqual(sim.mode, .idle)
        XCTAssertEqual(sim.holeRadius, 0)
        XCTAssertEqual(sim.burstTaps, 0)
        XCTAssertTrue(sim.bodies.allSatisfy(Self.isFloatingGrey))
        // A second hold still works
        sim.press(at: CGPoint(x: 201, y: 437))
        sim.advance(by: 3)
        XCTAssertEqual(sim.mode, .home)
    }

    private static func isFloatingGrey(_ body: OnboardingIntroBody) -> Bool {
        !body.isInside && !body.isPolished && body.colourIn == 0
    }

    func testRumbleBuildsWithTheChargeAndStopsAfterTheBurst() {
        var sim = makeSim()
        sim.press(at: CGPoint(x: 201, y: 437))
        sim.advance(by: 0.1)
        let early = sim.rumble
        sim.advance(by: 1.0)
        let late = sim.rumble
        XCTAssertGreaterThan(early, 0.14)
        XCTAssertGreaterThan(late, early)
        sim.advance(by: 2)
        XCTAssertLessThan(sim.rumble, 0.01)
    }

    func testGridAndPopupMatchTheIPhone16ProLayout() {
        let sim = makeSim()
        XCTAssertEqual(sim.gridSlot(0).y, 190, accuracy: 0.01)
        XCTAssertEqual(sim.gridSlot(4).y, 293, accuracy: 0.01)
        XCTAssertEqual(sim.gridSlot(0).x, 62.25, accuracy: 0.01)
        XCTAssertEqual(sim.gridSlot(3).x, 339.75, accuracy: 0.01)
        let card = sim.cardFrame
        XCTAssertEqual(card.minX, 24)
        XCTAssertEqual(card.minY, 297, accuracy: 0.01)
        XCTAssertEqual(card.width, 354)
        XCTAssertEqual(card.height, 252)
    }

    func testSameSeedSameRun() {
        var first = makeSim()
        var second = makeSim()
        first.press(at: CGPoint(x: 150, y: 400))
        second.press(at: CGPoint(x: 150, y: 400))
        first.advance(by: 1.2)
        second.advance(by: 1.2)
        for index in first.bodies.indices {
            XCTAssertEqual(first.bodies[index].position, second.bodies[index].position)
        }
    }

    // MARK: The popup's beats

    func testPopupBeatsMatchTheBrief() {
        XCTAssertEqual(OnboardingIntroSpec.wordmarkStart, 0.49, accuracy: 0.001)
        XCTAssertEqual(OnboardingIntroSpec.lineStart, 1.54, accuracy: 0.001)
        XCTAssertEqual(OnboardingIntroSpec.buttonStart, 2.69, accuracy: 0.001)
        // Get Started starts to show about 6.1 s after the touch
        let landing = OnboardingIntroSpec.chargeSeconds + OnboardingIntroSpec.fullSeconds + OnboardingIntroSpec.flightSeconds + 7 * OnboardingIntroSpec.flyStagger
        let getStarted = landing + OnboardingIntroSpec.popupWait + OnboardingIntroSpec.buttonStart
        XCTAssertEqual(getStarted, 6.1, accuracy: 0.05)
    }

    func testPopupLookRisesInOrder() {
        XCTAssertEqual(OnboardingPopupLook.motion(at: -1), OnboardingPopupLook())
        let beforeWords = OnboardingPopupLook.motion(at: 0.4)
        XCTAssertGreaterThan(beforeWords.glass, 0)
        XCTAssertEqual(beforeWords.wordmark, 0)
        let wordmarkOnly = OnboardingPopupLook.motion(at: 1.3)
        XCTAssertEqual(wordmarkOnly.wordmark, 1, accuracy: 0.001)
        XCTAssertEqual(wordmarkOnly.line, 0)
        let noButtonYet = OnboardingPopupLook.motion(at: 2.6)
        XCTAssertEqual(noButtonYet.line, 1, accuracy: 0.001)
        XCTAssertEqual(noButtonYet.button, 0)
        let done = OnboardingPopupLook.motion(at: 10)
        XCTAssertEqual(done, OnboardingPopupLook(glass: 1, wordmark: 1, line: 1, button: 1))
    }

    func testPopupClockStartsAfterTheWait() {
        var sim = makeSim()
        XCTAssertEqual(sim.popupClock, -1)
        sim.press(at: CGPoint(x: 201, y: 437))
        sim.advance(by: 2.6)
        XCTAssertEqual(sim.mode, .home)
        XCTAssertLessThan(sim.popupClock, 0)
        sim.advance(by: 1.0)
        XCTAssertGreaterThan(sim.popupClock, 0)
    }

    // MARK: Reduce Motion

    func testCalmVersionFadesIconsThenPopupThenButton() {
        XCTAssertEqual(OnboardingCalmTimeline.colourIn(icon: 0, at: 0), 0)
        XCTAssertEqual(OnboardingCalmTimeline.colourIn(icon: 7, at: 0.2), 0)
        let iconsDone = OnboardingCalmTimeline.iconsDone
        for index in OnboardingIntroSpec.apps.indices {
            XCTAssertEqual(OnboardingCalmTimeline.colourIn(icon: index, at: iconsDone), 1, accuracy: 0.001)
        }
        XCTAssertEqual(OnboardingCalmTimeline.popup(at: iconsDone).glass, 0)
        let popupIn = OnboardingCalmTimeline.popupStart + OnboardingCalmTimeline.popupFade
        let atPopup = OnboardingCalmTimeline.popup(at: popupIn)
        XCTAssertEqual(atPopup.glass, 1, accuracy: 0.001)
        XCTAssertEqual(atPopup.wordmark, 1, accuracy: 0.001)
        XCTAssertEqual(atPopup.line, 1, accuracy: 0.001)
        XCTAssertEqual(atPopup.button, 0)
        XCTAssertEqual(OnboardingCalmTimeline.popup(at: popupIn + 0.6).button, 1, accuracy: 0.001)
    }

    // MARK: Words

    func testIntroWords() {
        XCTAssertEqual(OnboardingIntroCopy.prompt, "Touch and Hold")
        XCTAssertEqual(OnboardingIntroCopy.wordmark, "Midas")
        XCTAssertEqual(OnboardingIntroCopy.line, "The personal touch your apps needed")
        XCTAssertFalse(OnboardingIntroCopy.line.hasSuffix("."))
        XCTAssertEqual(OnboardingIntroCopy.button, "Get Started")
        let names = OnboardingIntroSpec.apps.map(\.name)
        XCTAssertEqual(names, ["Reminders", "Water", "Habits", "Money", "To-Do", "Study", "Meds", "Sleep"])
    }

    func testTeachingCardWords() {
        XCTAssertEqual(OnboardingTeachCopy.editTitle, "Edit Any Sidekick")
        XCTAssertEqual(OnboardingTeachCopy.backTitle, "Go Back")
        XCTAssertEqual(OnboardingTeachCopy.makeTitle, "Make a Sidekick")
        XCTAssertEqual(OnboardingTeachCopy.deleteTitle, "Delete a Sidekick")
        XCTAssertEqual(OnboardingTeachCopy.nextButton, "Next")
        XCTAssertEqual(OnboardingTeachCopy.continueButton, "Continue")
    }
}
