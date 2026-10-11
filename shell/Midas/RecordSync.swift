import Foundation
import Observation

struct PushResult: Equatable, Sendable {
    /// Stored by the server, now or by an earlier push of the same op.
    let acceptedOpIds: [String]
    /// Refused for good (malformed or too large); retrying would never succeed.
    let rejectedOpIds: [String]
}

struct PullPage: Equatable, Sendable {
    let ops: [RemoteOp]
    let lastSeq: Int
    let more: Bool
}

enum RecordSyncError: Error, Equatable {
    case signInRequired
    case badResponse
    case serverError(statusCode: Int)
}

protocol RecordSyncAPI: Sendable {
    func push(ops: [PendingOp]) async throws -> PushResult
    func pull(after seq: Int) async throws -> PullPage
}

/// Keeps the phone's records backed up on the server (D4, 2026-10-10). Pushes the outbox, then
/// pulls every op the phone has not seen. Runs on launch, on return to the foreground, and about
/// a second after a write. A failure (no connection) leaves everything in the outbox for the
/// next try; nothing is lost on the phone.
@MainActor
@Observable
final class RecordSync {
    /// Matches the backend's limits (src/sync.ts), with headroom for the op fields.
    nonisolated static let maxOpsPerPush = 100
    nonisolated static let maxValueBytesPerPush = 900 * 1024
    static let writeDelay: Duration = .seconds(1)

    private(set) var isSyncing = false
    private(set) var lastSyncFailed = false

    private let store: LocalRecordStore
    private let api: RecordSyncAPI
    private var scheduledSync: Task<Void, Never>?

    init(store: LocalRecordStore, api: RecordSyncAPI) {
        self.store = store
        self.api = api
    }

    /// Pushes after a short delay, so a burst of writes goes up as one push.
    func startSyncingAfterWrites() {
        store.addChangeObserver(handleStoreChange)
    }

    private func handleStoreChange(_ change: LocalRecordChange) {
        // Changes applied from a pull add nothing to the outbox, so they do not trigger a sync.
        guard store.pendingOpCount > 0 else {
            return
        }
        scheduledSync?.cancel()
        scheduledSync = Task { @MainActor in
            try? await Task.sleep(for: Self.writeDelay)
            guard !Task.isCancelled else {
                return
            }
            await self.syncNow()
        }
    }

    /// Push everything, then pull everything. Returns whether both finished. A call made while a
    /// sync is running waits for that sync and gets its result, so the restore screen and the
    /// launch sync never report each other as a failure.
    @discardableResult
    func syncNow() async -> Bool {
        if let runningSync {
            return await runningSync.value
        }
        let newSync = Task { @MainActor in
            await self.runSyncRounds()
        }
        runningSync = newSync
        isSyncing = true
        let didFinish = await newSync.value
        runningSync = nil
        isSyncing = false
        return didFinish
    }

    private var runningSync: Task<Bool, Never>?

    // A write that lands while ops are being pulled is pushed in another round rather than
    // waiting for the next trigger. Bounded so a Sidekick writing nonstop cannot keep it going.
    private func runSyncRounds() async -> Bool {
        let maxRounds = 3
        for _ in 0..<maxRounds {
            do {
                try await pushOutbox()
                try await pullAll()
            } catch {
                lastSyncFailed = true
                return false
            }
            if store.pendingOpCount == 0 {
                break
            }
        }
        lastSyncFailed = false
        return true
    }

    /// On a fresh install, records must be back before the folder shows (2026-10-10).
    /// Returns true once the first full pull has finished on this install, now or earlier.
    func completeInitialSync() async -> Bool {
        if store.hasCompletedInitialPull {
            Task { @MainActor in
                await self.syncNow()
            }
            return true
        }
        guard await syncNow() else {
            return false
        }
        try? store.markInitialPullCompleted()
        return store.hasCompletedInitialPull
    }

    private func pushOutbox() async throws {
        while store.pendingOpCount > 0 {
            let batch = Self.nextBatch(from: store.pendingOps())
            let result = try await api.push(ops: batch)
            var doneOpIds = Set(result.acceptedOpIds)
            doneOpIds.formUnion(result.rejectedOpIds)
            guard !doneOpIds.isEmpty else {
                throw RecordSyncError.badResponse
            }
            try store.removeFromOutbox(opIds: doneOpIds)
        }
    }

    private func pullAll() async throws {
        while true {
            let page = try await api.pull(after: store.lastPulledSeq)
            try store.applyRemote(ops: page.ops, lastSeq: page.lastSeq)
            if !page.more {
                return
            }
        }
    }

    /// The oldest ops that fit in one push: at most maxOpsPerPush, and at most
    /// maxValueBytesPerPush of values (always at least one op).
    nonisolated static func nextBatch(from pendingOps: [PendingOp]) -> [PendingOp] {
        var batch: [PendingOp] = []
        var batchBytes = 0
        for pendingOp in pendingOps {
            let opBytes = valueByteCount(pendingOp.value)
            let isFull = batch.count == maxOpsPerPush || batchBytes + opBytes > maxValueBytesPerPush
            if !batch.isEmpty && isFull {
                break
            }
            batch.append(pendingOp)
            batchBytes += opBytes
        }
        return batch
    }

    nonisolated static func valueByteCount(_ value: JSONValue?) -> Int {
        guard let value, let encodedValue = try? JSONEncoder().encode(value) else {
            return 0
        }
        return encodedValue.count
    }
}

/// POST /sync/push and GET /sync/pull with the user's session.
struct RemoteRecordSyncAPI: RecordSyncAPI {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func push(ops: [PendingOp]) async throws -> PushResult {
        let request = try Self.pushRequest(platformOrigin: platformOrigin, ops: ops, token: sessionToken())
        let responseBody = try await send(request)
        return try Self.pushResult(from: responseBody)
    }

    func pull(after seq: Int) async throws -> PullPage {
        let request = Self.pullRequest(platformOrigin: platformOrigin, after: seq, token: sessionToken())
        let responseBody = try await send(request)
        return try Self.pullPage(from: responseBody)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (responseBody, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 {
            throw RecordSyncError.signInRequired
        }
        guard statusCode == 200 else {
            throw RecordSyncError.serverError(statusCode: statusCode)
        }
        return responseBody
    }

    private struct PushBody: Encodable {
        struct Op: Encodable {
            let opId: String
            let sidekickId: String
            let key: String
            let value: JSONValue?
            let deleted: Bool
            let clientTime: String

            // A write always sends "value" (null included); a delete never does.
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(opId, forKey: .opId)
                try container.encode(sidekickId, forKey: .sidekickId)
                try container.encode(key, forKey: .key)
                try container.encode(deleted, forKey: .deleted)
                try container.encode(clientTime, forKey: .clientTime)
                if !deleted {
                    try container.encode(value ?? .null, forKey: .value)
                }
            }

            enum CodingKeys: String, CodingKey {
                case opId, sidekickId, key, value, deleted, clientTime
            }
        }
        let ops: [Op]
    }

    static func pushRequest(platformOrigin: URL, ops: [PendingOp], token: String?) throws -> URLRequest {
        var request = URLRequest(url: platformOrigin.appending(path: "sync/push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var bodyOps: [PushBody.Op] = []
        for pendingOp in ops {
            let bodyOp = PushBody.Op(opId: pendingOp.opId, sidekickId: pendingOp.sidekickId, key: pendingOp.key, value: pendingOp.value, deleted: pendingOp.deleted, clientTime: pendingOp.clientTime)
            bodyOps.append(bodyOp)
        }
        request.httpBody = try JSONEncoder().encode(PushBody(ops: bodyOps))
        return request
    }

    static func pullRequest(platformOrigin: URL, after seq: Int, token: String?) -> URLRequest {
        let pullURL = platformOrigin.appending(path: "sync/pull")
        let afterItem = URLQueryItem(name: "after", value: String(seq))
        var request = URLRequest(url: pullURL.appending(queryItems: [afterItem]))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private struct PushReply: Decodable {
        struct Rejection: Decodable {
            let opId: JSONValue?
        }
        let accepted: [String]
        let rejected: [Rejection]
    }

    static func pushResult(from responseBody: Data) throws -> PushResult {
        guard let reply = try? JSONDecoder().decode(PushReply.self, from: responseBody) else {
            throw RecordSyncError.badResponse
        }
        var rejectedOpIds: [String] = []
        for rejection in reply.rejected {
            if let opId = rejection.opId?.stringValue {
                rejectedOpIds.append(opId)
            }
        }
        return PushResult(acceptedOpIds: reply.accepted, rejectedOpIds: rejectedOpIds)
    }

    private struct PullReply: Decodable {
        struct Op: Decodable {
            let seq: Int
            let opId: String
            let sidekickId: String
            let key: String
            let value: JSONValue?
            let deleted: Bool
        }
        let ops: [Op]
        let lastSeq: Int
        let more: Bool
    }

    static func pullPage(from responseBody: Data) throws -> PullPage {
        guard let reply = try? JSONDecoder().decode(PullReply.self, from: responseBody) else {
            throw RecordSyncError.badResponse
        }
        var ops: [RemoteOp] = []
        for replyOp in reply.ops {
            // A write whose value is JSON null decodes as nil here; it is still a write of null.
            let value: JSONValue? = replyOp.deleted ? nil : (replyOp.value ?? .null)
            ops.append(RemoteOp(seq: replyOp.seq, opId: replyOp.opId, sidekickId: replyOp.sidekickId, key: replyOp.key, value: value, deleted: replyOp.deleted))
        }
        return PullPage(ops: ops, lastSeq: reply.lastSeq, more: reply.more)
    }
}
