import Foundation
import Observation

enum AuthState: Equatable {
    case checking
    /// A stored session could not be checked because the server could not be reached. The token
    /// is kept; the shell shows "Can't Connect" with "Try Again" (build 22 dead-end sweep,
    /// 2026-11-01: was the sign-up screen until the next launch, with no way to retry).
    case cannotConnect
    case signedOut
    case signedIn(MidasUser)
}

/// Decides whether the shell shows the welcome screen or the Sidekicks, and runs the two flows:
/// new user (name, then create a passkey) and returning user (sign in with the passkey).
@MainActor
@Observable
final class AuthModel {
    private(set) var state: AuthState = .checking
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    private let api: AuthAPI
    private let store: SessionStore
    private let passkeys: PasskeyAuthenticating

    init(api: AuthAPI, store: SessionStore, passkeys: PasskeyAuthenticating) {
        self.api = api
        self.store = store
        self.passkeys = passkeys
    }

    /// On launch: a stored token is checked with the server. Only a 401 signs the user out; a
    /// network failure keeps the token and shows "Can't Connect" until Try Again reaches it.
    func start() async {
        guard let token = store.loadToken() else {
            state = .signedOut
            return
        }
        do {
            let user = try await api.currentUser(token: token)
            state = .signedIn(user)
        } catch AuthAPIError.signInRequired {
            store.clearToken()
            state = .signedOut
        } catch {
            errorMessage = AuthCopy.cannotConnect
            state = .cannotConnect
        }
    }

    /// Try Again on the "Can't Connect" screen: checks the stored session again.
    func retryStart() async {
        guard state == .cannotConnect else {
            return
        }
        errorMessage = nil
        state = .checking
        await start()
    }

    func createAccount(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = AuthCopy.nameMissing
            return
        }
        await runFlow(failureMessage: AuthCopy.createAccountFailed) {
            let challenge = try await self.api.registrationChallenge(name: trimmedName)
            let registration = try await self.passkeys.createPasskey(for: challenge)
            return try await self.api.completeRegistration(challengeId: challenge.challengeId, registration: registration)
        }
    }

    func signInWithPasskey() async {
        await runFlow(failureMessage: AuthCopy.signInFailed) {
            let challenge = try await self.api.loginChallenge()
            let assertion = try await self.passkeys.signIn(with: challenge)
            return try await self.api.completeLogin(challengeId: challenge.challengeId, assertion: assertion)
        }
    }

    /// The signed-in person, or nil.
    var user: MidasUser? {
        if case .signedIn(let signedInUser) = state {
            return signedInUser
        }
        return nil
    }

    /// Sign Out and the end of Delete Account (settings-delete, 2026-10-31): the token leaves the
    /// Keychain and the welcome screen shows. The server side is the caller's (AccountCenter).
    func signOut() {
        store.clearToken()
        errorMessage = nil
        state = .signedOut
    }

    private func runFlow(failureMessage: String, _ flow: () async throws -> AuthSession) async {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let session = try await flow()
            store.saveToken(session.token)
            state = .signedIn(session.user)
        } catch PasskeyError.canceled {
            // The user closed the passkey sheet; nothing to report.
        } catch AuthAPIError.signInRequired {
            errorMessage = AuthCopy.unknownPasskey
        } catch {
            errorMessage = failureMessage
        }
    }
}

/// Error lines on the welcome screen (docs/WRITING.md; founder approved the wording mockup
/// 2026-10-10).
enum AuthCopy {
    static let cannotConnect = "Can’t connect. Try again."
    static let nameMissing = "Enter a name."
    static let unknownPasskey = "No account for this passkey."
    static let createAccountFailed = "Can’t create account. Try again."
    static let signInFailed = "Can’t sign in. Try again."
}
