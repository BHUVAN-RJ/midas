import Foundation

/// One of the user's Sidekicks as POST /voice/jess takes it (backend/src/jess.ts JessSidekick):
/// its agent block from manifest.json and its tools.js context() of the records on the phone.
struct JessSidekickPayload: Encodable, Equatable, Sendable {
    let id: String
    let name: String
    let version: String?
    let agent: JSONValue
    let context: JSONValue
}

/// POST /voice/jess body.
struct JessRouteRequest: Encodable, Equatable, Sendable {
    let transcript: String
    let now: String
    let timeZone: String
    let locale: String
    let sidekicks: [JessSidekickPayload]
    let app: VoiceParseApp
    let listenMs: Int
}

/// What the router answered. `done` names the Sidekick tool to run with its checked input (the
/// when already worked out); `repair` was queued for the repair agent; `notDone` carries the
/// server's reason (for the log only, never shown); `unreachable` is no network, a timeout or an
/// answer the phone could not read.
enum JessRouteReply: Equatable, Sendable {
    case done(sidekickId: String, tool: String, input: JSONValue, logId: String?)
    case repair(sidekickId: String, logId: String?)
    case notDone(reason: String)
    case unreachable
}

/// What the phone did with a `done`, reported back for the log (POST /voice/jess/outcome).
enum JessPhoneOutcome: Equatable, Sendable {
    case applied
    case refused(reason: String)
    case failed(reason: String)
}

protocol JessRouting: Sendable {
    func route(_ request: JessRouteRequest) async -> JessRouteReply
    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async
}

private struct JessRouteAnswer: Decodable {
    let status: String
    let sidekickId: String?
    let tool: String?
    let input: JSONValue?
    let reason: String?
    let logId: String?
}

private struct JessOutcomeBody: Encodable {
    let logId: String
    let outcome: String
    let reason: String?
}

/// POST /voice/jess and /voice/jess/outcome with the user's session.
struct RemoteJessRouter: JessRouting {
    /// The server waits at most 4 s per model call and tries once more; this covers both and the trip.
    static let requestTimeout: TimeInterval = 15

    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func route(_ request: JessRouteRequest) async -> JessRouteReply {
        guard let token = sessionToken(), let urlRequest = try? Self.urlRequest(platformOrigin: platformOrigin, path: "voice/jess", body: request, token: token) else {
            return .unreachable
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.reply(statusCode: statusCode, data: data)
        } catch {
            return .unreachable
        }
    }

    /// Best effort: a lost outcome only leaves the log row without it.
    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async {
        guard let token = sessionToken(), let urlRequest = try? Self.urlRequest(platformOrigin: platformOrigin, path: "voice/jess/outcome", body: Self.outcomeBody(logId: logId, outcome: outcome), token: token) else {
            return
        }
        _ = try? await session.data(for: urlRequest)
    }

    static func urlRequest(platformOrigin: URL, path: String, body: some Encodable, token: String) throws -> URLRequest {
        var request = URLRequest(url: platformOrigin.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func reply(statusCode: Int, data: Data) -> JessRouteReply {
        guard statusCode == 200, let answer = try? JSONDecoder().decode(JessRouteAnswer.self, from: data) else {
            return .unreachable
        }
        switch answer.status {
        case "done":
            guard let sidekickId = answer.sidekickId, let tool = answer.tool, let input = answer.input else {
                return .unreachable
            }
            return .done(sidekickId: sidekickId, tool: tool, input: input, logId: answer.logId)
        case "repair":
            guard let sidekickId = answer.sidekickId else {
                return .unreachable
            }
            return .repair(sidekickId: sidekickId, logId: answer.logId)
        default:
            return .notDone(reason: answer.reason ?? "unknown")
        }
    }

    fileprivate static func outcomeBody(logId: String, outcome: JessPhoneOutcome) -> JessOutcomeBody {
        switch outcome {
        case .applied:
            return JessOutcomeBody(logId: logId, outcome: "applied", reason: nil)
        case .refused(let reason):
            return JessOutcomeBody(logId: logId, outcome: "refused", reason: reason)
        case .failed(let reason):
            return JessOutcomeBody(logId: logId, outcome: "failed", reason: reason)
        }
    }
}
