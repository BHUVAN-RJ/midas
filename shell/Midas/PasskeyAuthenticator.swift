import AuthenticationServices
import UIKit

enum PasskeyError: Error, Equatable {
    case canceled
    case failed(String)
}

/// The system passkey sheet, behind a protocol so the auth flow can be tested without it.
@MainActor
protocol PasskeyAuthenticating {
    func createPasskey(for challenge: RegistrationChallenge) async throws -> PasskeyRegistration
    func signIn(with challenge: LoginChallenge) async throws -> PasskeyAssertion
}

/// Wraps ASAuthorizationController in async calls. One request at a time.
@MainActor
final class SystemPasskeyAuthenticator: NSObject, PasskeyAuthenticating {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func createPasskey(for challenge: RegistrationChallenge) async throws -> PasskeyRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: challenge.relyingPartyId)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge.challenge,
            name: challenge.userName,
            userID: challenge.userId
        )
        let authorization = try await perform(request)
        guard
            let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
            let attestationObject = credential.rawAttestationObject
        else {
            throw PasskeyError.failed("unexpected credential type")
        }
        return PasskeyRegistration(
            credentialId: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            attestationObject: attestationObject
        )
    }

    func signIn(with challenge: LoginChallenge) async throws -> PasskeyAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: challenge.relyingPartyId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge.challenge)
        let authorization = try await perform(request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw PasskeyError.failed("unexpected credential type")
        }
        return PasskeyAssertion(
            credentialId: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData,
            signature: credential.signature,
            userHandle: credential.userID
        )
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        if continuation != nil {
            throw PasskeyError.failed("a passkey request is already open")
        }
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { pendingContinuation in
            continuation = pendingContinuation
            controller.performRequests()
        }
    }

    private func finish(with result: Result<ASAuthorization, Error>) {
        let pendingContinuation = continuation
        continuation = nil
        pendingContinuation?.resume(with: result)
    }
}

extension SystemPasskeyAuthenticator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            finish(with: .success(authorization))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let authorizationError = error as? ASAuthorizationError
        let passkeyError: PasskeyError = authorizationError?.code == .canceled
            ? .canceled
            : .failed(error.localizedDescription)
        MainActor.assumeIsolated {
            finish(with: .failure(passkeyError))
        }
    }
}

extension SystemPasskeyAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let keyWindow = windowScenes.flatMap(\.windows).first(where: \.isKeyWindow)
            return keyWindow ?? ASPresentationAnchor()
        }
    }
}
