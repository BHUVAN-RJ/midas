import Foundation

struct MidasUser: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

struct AuthSession: Codable, Equatable, Sendable {
    let token: String
    let user: MidasUser
}

/// What the shell needs from POST /auth/register/options.
struct RegistrationChallenge: Equatable, Sendable {
    let challengeId: String
    let challenge: Data
    let userId: Data
    let userName: String
    let relyingPartyId: String
}

/// What the shell needs from POST /auth/login/options.
struct LoginChallenge: Equatable, Sendable {
    let challengeId: String
    let challenge: Data
    let relyingPartyId: String
}

/// The raw fields of a new passkey, as ASAuthorization returns them.
struct PasskeyRegistration: Equatable, Sendable {
    let credentialId: Data
    let clientDataJSON: Data
    let attestationObject: Data
}

/// The raw fields of a passkey sign-in, as ASAuthorization returns them.
struct PasskeyAssertion: Equatable, Sendable {
    let credentialId: Data
    let clientDataJSON: Data
    let authenticatorData: Data
    let signature: Data
    let userHandle: Data
}

enum AuthAPIError: Error, Equatable {
    case signInRequired
    case badResponse
    case server(status: Int, message: String)
}

protocol AuthAPI: Sendable {
    func registrationChallenge(name: String) async throws -> RegistrationChallenge
    func completeRegistration(challengeId: String, registration: PasskeyRegistration) async throws -> AuthSession
    func loginChallenge() async throws -> LoginChallenge
    func completeLogin(challengeId: String, assertion: PasskeyAssertion) async throws -> AuthSession
    func currentUser(token: String) async throws -> MidasUser
}

/// Builds the JSON bodies the backend's WebAuthn verification expects
/// (RegistrationResponseJSON / AuthenticationResponseJSON).
enum WebAuthnPayload {
    static func registration(challengeId: String, registration: PasskeyRegistration) -> [String: Any] {
        let credentialId = Base64URL.encode(registration.credentialId)
        let response: [String: Any] = [
            "clientDataJSON": Base64URL.encode(registration.clientDataJSON),
            "attestationObject": Base64URL.encode(registration.attestationObject),
            "transports": ["internal", "hybrid"],
        ]
        let credential: [String: Any] = [
            "id": credentialId,
            "rawId": credentialId,
            "type": "public-key",
            "clientExtensionResults": [String: Any](),
            "response": response,
        ]
        return ["challengeId": challengeId, "credential": credential]
    }

    static func assertion(challengeId: String, assertion: PasskeyAssertion) -> [String: Any] {
        let credentialId = Base64URL.encode(assertion.credentialId)
        let response: [String: Any] = [
            "clientDataJSON": Base64URL.encode(assertion.clientDataJSON),
            "authenticatorData": Base64URL.encode(assertion.authenticatorData),
            "signature": Base64URL.encode(assertion.signature),
            "userHandle": Base64URL.encode(assertion.userHandle),
        ]
        let credential: [String: Any] = [
            "id": credentialId,
            "rawId": credentialId,
            "type": "public-key",
            "clientExtensionResults": [String: Any](),
            "response": response,
        ]
        return ["challengeId": challengeId, "credential": credential]
    }
}

/// Parses the options replies. Only the fields the shell uses are read.
enum AuthOptionsParser {
    static func registration(from data: Data) throws -> RegistrationChallenge {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let challengeId = root["challengeId"] as? String,
            let options = root["options"] as? [String: Any],
            let challengeText = options["challenge"] as? String,
            let challenge = Base64URL.decode(challengeText),
            let user = options["user"] as? [String: Any],
            let userIdText = user["id"] as? String,
            let userId = Base64URL.decode(userIdText),
            let userName = user["name"] as? String,
            let relyingParty = options["rp"] as? [String: Any],
            let relyingPartyId = relyingParty["id"] as? String
        else {
            throw AuthAPIError.badResponse
        }
        return RegistrationChallenge(
            challengeId: challengeId,
            challenge: challenge,
            userId: userId,
            userName: userName,
            relyingPartyId: relyingPartyId
        )
    }

    static func login(from data: Data) throws -> LoginChallenge {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let challengeId = root["challengeId"] as? String,
            let options = root["options"] as? [String: Any],
            let challengeText = options["challenge"] as? String,
            let challenge = Base64URL.decode(challengeText),
            let relyingPartyId = options["rpId"] as? String
        else {
            throw AuthAPIError.badResponse
        }
        return LoginChallenge(challengeId: challengeId, challenge: challenge, relyingPartyId: relyingPartyId)
    }
}

struct RemoteAuthAPI: AuthAPI {
    let platformOrigin: URL
    let session: URLSession

    private struct MeReply: Decodable {
        let user: MidasUser
    }

    func registrationChallenge(name: String) async throws -> RegistrationChallenge {
        let data = try await post(path: "auth/register/options", body: ["name": name])
        return try AuthOptionsParser.registration(from: data)
    }

    func completeRegistration(challengeId: String, registration: PasskeyRegistration) async throws -> AuthSession {
        let body = WebAuthnPayload.registration(challengeId: challengeId, registration: registration)
        let data = try await post(path: "auth/register/verify", body: body)
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func loginChallenge() async throws -> LoginChallenge {
        let data = try await post(path: "auth/login/options", body: [:])
        return try AuthOptionsParser.login(from: data)
    }

    func completeLogin(challengeId: String, assertion: PasskeyAssertion) async throws -> AuthSession {
        let body = WebAuthnPayload.assertion(challengeId: challengeId, assertion: assertion)
        let data = try await post(path: "auth/login/verify", body: body)
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func currentUser(token: String) async throws -> MidasUser {
        var request = URLRequest(url: platformOrigin.appendingPathComponent("auth/me"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        return try JSONDecoder().decode(MeReply.self, from: data).user
    }

    private func post(path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: platformOrigin.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.badResponse
        }
        if httpResponse.statusCode == 401 {
            throw AuthAPIError.signInRequired
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw AuthAPIError.server(status: httpResponse.statusCode, message: message)
        }
        return data
    }
}
