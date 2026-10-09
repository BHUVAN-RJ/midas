import Foundation
import Observation

enum AuthState: Equatable {
    case checking
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
    /// network failure keeps the token and shows the welcome screen until the next launch.
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
            errorMessage = "Could not reach Midas. Check your connection."
            state = .signedOut
        }
    }

    func createAccount(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter your name."
            return
        }
        await runFlow {
            let challenge = try await self.api.registrationChallenge(name: trimmedName)
            let registration = try await self.passkeys.createPasskey(for: challenge)
            return try await self.api.completeRegistration(challengeId: challenge.challengeId, registration: registration)
        }
    }

    func signInWithPasskey() async {
        await runFlow {
            let challenge = try await self.api.loginChallenge()
            let assertion = try await self.passkeys.signIn(with: challenge)
            return try await self.api.completeLogin(challengeId: challenge.challengeId, assertion: assertion)
        }
    }

    private func runFlow(_ flow: () async throws -> AuthSession) async {
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
            errorMessage = "That passkey is not linked to a Midas account."
        } catch {
            errorMessage = "Something went wrong. Try again."
        }
    }
}
