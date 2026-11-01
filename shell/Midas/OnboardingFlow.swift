import Foundation
import Observation

// Onboarding, start to end (founder, 2026-10-31, docs/briefs/onboarding-build.md): on a new install
// the black hole intro comes first, then sign in (WelcomeView: name, passkey), then the four teaching
// cards. Once per user: never shown to anyone already signed in.

/// Which screen the shell shows.
enum OnboardingStage: Equatable {
    /// Checking a stored session with the server
    case checking
    /// The first-open black hole, before sign in
    case intro
    /// Name and passkey (WelcomeView)
    case welcome
    /// The four teaching cards, right after the first sign in
    case teach
    /// The Sidekicks
    case home
}

/// Which onboarding screens this install has already been through.
struct OnboardingMemory {
    static let introSeenKey = "midas.onboarding.introSeen"
    static let teachSeenKey = "midas.onboarding.teachSeen"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var introSeen: Bool {
        defaults.bool(forKey: Self.introSeenKey)
    }

    var teachSeen: Bool {
        defaults.bool(forKey: Self.teachSeenKey)
    }

    func markIntroSeen() {
        defaults.set(true, forKey: Self.introSeenKey)
    }

    func markTeachSeen() {
        defaults.set(true, forKey: Self.teachSeenKey)
    }
}

enum OnboardingRules {
    /// The screen for this sign-in state and what this install has seen.
    /// - Signed out: the intro until Get Started has been tapped once, then the welcome screen.
    /// - Signed in: the teaching cards once, but only after this install went through the intro
    ///   (a new user). Anyone signed in who never saw the intro was a user before onboarding
    ///   existed: straight home.
    static func stage(for state: AuthState, introSeen: Bool, teachSeen: Bool) -> OnboardingStage {
        switch state {
        case .checking:
            return .checking
        case .signedOut:
            return introSeen ? .welcome : .intro
        case .signedIn:
            return introSeen && !teachSeen ? .teach : .home
        }
    }

    /// A signed-in user who never saw the intro (an update from a build without onboarding) is
    /// marked as having seen both, so signing out later never shows them the intro.
    static func marksExistingUser(for state: AuthState, introSeen: Bool) -> Bool {
        if case .signedIn = state {
            return !introSeen
        }
        return false
    }
}

/// The shell's onboarding state, kept in sync with the sign-in state.
@MainActor
@Observable
final class OnboardingProgress {
    private(set) var introSeen: Bool
    private(set) var teachSeen: Bool
    @ObservationIgnored private let memory: OnboardingMemory

    init(memory: OnboardingMemory = OnboardingMemory()) {
        self.memory = memory
        self.introSeen = memory.introSeen
        self.teachSeen = memory.teachSeen
    }

    func stage(for state: AuthState) -> OnboardingStage {
        OnboardingRules.stage(for: state, introSeen: introSeen, teachSeen: teachSeen)
    }

    /// Called whenever the sign-in state changes.
    func noteAuthState(_ state: AuthState) {
        guard OnboardingRules.marksExistingUser(for: state, introSeen: introSeen) else {
            return
        }
        memory.markIntroSeen()
        memory.markTeachSeen()
        introSeen = true
        teachSeen = true
    }

    /// Get Started on the intro's popup.
    func finishIntro() {
        memory.markIntroSeen()
        introSeen = true
    }

    /// Continue on the last teaching card.
    func finishTeach() {
        memory.markTeachSeen()
        teachSeen = true
    }
}
