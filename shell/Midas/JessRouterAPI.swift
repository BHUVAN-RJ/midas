import Foundation

/// One of the user's Sidekicks as POST /voice/jess takes it: its id and its tools.js context() of
/// the records on the phone. The server reads the agent block and tools from the manifest of the
/// version the user gets (founder, 2026-10-21); the phone does not send them.
struct JessSidekickPayload: Encodable, Equatable, Sendable {
    let id: String
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
/// when already worked out) and the version whose manifest it was checked against; `repair` was
/// queued for the repair agent; `grow` was filed as a feature request, and the backend runs the
/// request again once that repair is live (jess grows the Sidekick, 2026-10-21); `notDone` carries the
/// server's reason (for the log only, never shown); `unreachable` is no network, a timeout or an
/// answer the phone could not read.
enum JessRouteReply: Equatable, Sendable {
    case done(sidekickId: String, version: String? = nil, tool: String, input: JSONValue, logId: String?)
    case repair(sidekickId: String, logId: String?)
    case grow(sidekickId: String, logId: String?)
    case notDone(reason: String)
    case unreachable
}

/// What the phone did with a `done`, reported back for the log (POST /voice/jess/outcome).
enum JessPhoneOutcome: Equatable, Sendable {
    case applied
    case refused(reason: String)
    case failed(reason: String)
}

/// A request jess grew a Sidekick for, finished by the backend's re-run (GET /voice/jess/pending):
/// `done` with the handler's line for the banner, `failed` with what was said for the Not Done card.
struct JessPendingItem: Decodable, Equatable, Sendable {
    let id: String
    let sidekickId: String
    let state: String
    let text: String?
    let transcript: String
}

/// GET /voice/jess/pending and POST /voice/jess/pending/:id/seen.
protocol JessPendingAPI: Sendable {
    /// Nil when the server could not be asked (signed out, offline).
    func pending() async -> [JessPendingItem]?
    func markShown(id: String) async
}

protocol JessRouting: Sendable {
    func route(_ request: JessRouteRequest) async -> JessRouteReply
    func reportOutcome(logId: String, outcome: JessPhoneOutcome) async
}

private struct JessRouteAnswer: Decodable {
    let status: String
    let sidekickId: String?
    let version: String?
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
            return .done(sidekickId: sidekickId, version: answer.version, tool: tool, input: input, logId: answer.logId)
        case "repair":
            guard let sidekickId = answer.sidekickId else {
                return .unreachable
            }
            return .repair(sidekickId: sidekickId, logId: answer.logId)
        case "grow":
            guard let sidekickId = answer.sidekickId else {
                return .unreachable
            }
            return .grow(sidekickId: sidekickId, logId: answer.logId)
        default:
            return .notDone(reason: answer.reason ?? "unknown")
        }
    }

    static func pendingItems(statusCode: Int, data: Data) -> [JessPendingItem]? {
        guard statusCode == 200, let list = try? JSONDecoder().decode(JessPendingList.self, from: data) else {
            return nil
        }
        return list.pending
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

private struct JessPendingList: Decodable {
    let pending: [JessPendingItem]
}

private struct JessEmptyBody: Encodable {}

extension RemoteJessRouter: JessPendingAPI {
    func pending() async -> [JessPendingItem]? {
        guard let token = sessionToken() else {
            return nil
        }
        var request = URLRequest(url: platformOrigin.appending(path: "voice/jess/pending"))
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request) else {
            return nil
        }
        return Self.pendingItems(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// Best effort: a lost mark shows the same banner or card once more on the next open.
    func markShown(id: String) async {
        guard let token = sessionToken(), let urlRequest = try? Self.urlRequest(platformOrigin: platformOrigin, path: "voice/jess/pending/\(id)/seen", body: JessEmptyBody(), token: token) else {
            return
        }
        _ = try? await session.data(for: urlRequest)
    }
}
