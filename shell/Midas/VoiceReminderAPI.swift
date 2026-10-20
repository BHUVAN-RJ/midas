import Foundation

/// One of the user's Reminders lists, as the parse route takes it (backend/src/voice-route.ts).
struct VoiceReminderList: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

/// A repeat in the Reminders page's `cleanRepeat` shape (backend/src/voice.ts CleanRepeat).
struct VoiceReminderRepeat: Codable, Equatable, Sendable {
    let every: String
    var interval: Int?
    var weekdays: [Int]?
}

/// The reminder the server worked out (backend/src/voice.ts ResolvedReminder): every date is
/// already resolved in code; `at` is the instant, null for an undated reminder.
struct VoiceResolvedReminder: Codable, Equatable, Sendable {
    let title: String
    var notes: String?
    var list: String?
    var date: String?
    var time: String?
    let allDay: Bool
    var at: String?
    var `repeat`: VoiceReminderRepeat?
    let timeZone: String
}

struct VoiceParseApp: Codable, Equatable, Sendable {
    let version: String
    let build: String
    let ios: String
    let device: String
}

/// POST /voice/reminder/parse body.
struct VoiceParseRequest: Codable, Equatable, Sendable {
    let transcript: String
    let now: String
    let timeZone: String
    let locale: String
    let lists: [VoiceReminderList]
    let app: VoiceParseApp
    let listenMs: Int
}

/// What came back. `notDone` carries the server's reason (for the log only, never shown);
/// `unreachable` is no network, a timeout or an answer the phone could not read.
enum VoiceParseResult: Equatable, Sendable {
    case done(VoiceResolvedReminder)
    case notDone(reason: String)
    case unreachable
}

protocol VoiceReminderParsing: Sendable {
    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult
}

/// The server's answer, either shape.
private struct VoiceParseAnswer: Decodable {
    let status: String
    let reminder: VoiceResolvedReminder?
    let reason: String?
}

/// POST /voice/reminder/parse with the user's session.
struct RemoteVoiceReminderAPI: VoiceReminderParsing {
    /// The server waits at most 4 s per model call and tries once more; this covers both and the trip.
    static let requestTimeout: TimeInterval = 15

    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        guard let token = sessionToken(), let urlRequest = try? Self.urlRequest(platformOrigin: platformOrigin, body: request, token: token) else {
            return .unreachable
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.result(statusCode: statusCode, data: data)
        } catch {
            return .unreachable
        }
    }

    static func urlRequest(platformOrigin: URL, body: VoiceParseRequest, token: String) throws -> URLRequest {
        var request = URLRequest(url: platformOrigin.appending(path: "voice/reminder/parse"))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func result(statusCode: Int, data: Data) -> VoiceParseResult {
        guard statusCode == 200, let answer = try? JSONDecoder().decode(VoiceParseAnswer.self, from: data) else {
            return .unreachable
        }
        if answer.status == "done", let reminder = answer.reminder {
            return .done(reminder)
        }
        return .notDone(reason: answer.reason ?? "unknown")
    }
}
