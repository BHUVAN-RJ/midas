import Foundation

/// One record as a Sidekick wrote it, with the Sidekick that owns it.
struct LocalRecord: Equatable, Sendable {
    let sidekickId: String
    let key: String
    let value: JSONValue
}

/// What changed in the store, so the notification engine can react to `reminder:` writes.
struct LocalRecordChange: Equatable, Sendable {
    let sidekickId: String
    let key: String
}

/// A local write or delete waiting to be backed up to the server (POST /sync/push).
struct PendingOp: Codable, Equatable, Sendable {
    let opId: String
    let sidekickId: String
    let key: String
    /// nil for a delete.
    let value: JSONValue?
    let deleted: Bool
    let clientTime: String
}

/// An op from the server (GET /sync/pull), in server sequence order.
struct RemoteOp: Equatable, Sendable {
    let seq: Int
    let opId: String
    let sidekickId: String
    let key: String
    let value: JSONValue?
    let deleted: Bool
}

/// Sidekick records kept on the phone, so Sidekicks work without a connection. Each Sidekick
/// sees only its own records; the shell (the notification engine) can read across all of them.
///
/// Every set and delete also goes into an outbox that RecordSync pushes to the server, and ops
/// pulled from the server are applied here, so a reinstall gets every record back (D4,
/// 2026-10-10). Records, outbox and pull cursor are saved together as one JSON file, rewritten
/// atomically on every change, so a record is never saved without its op.
@MainActor
final class LocalRecordStore {
    private let fileURL: URL
    // sidekickId -> key -> value
    private var recordsBySidekick: [String: [String: JSONValue]] = [:]
    private var outbox: [PendingOp] = []
    private(set) var lastPulledSeq = 0
    /// False until the first full pull from the server has finished on this install.
    private(set) var hasCompletedInitialPull = false
    private var changeObservers: [@MainActor (LocalRecordChange) -> Void] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        let savedState = Self.loadState(from: fileURL)
        self.recordsBySidekick = savedState.records
        self.outbox = savedState.outbox
        self.lastPulledSeq = savedState.lastPulledSeq
        self.hasCompletedInitialPull = savedState.hasCompletedInitialPull
    }

    /// One file per server, so a staging build and a live build never mix records. Live keeps the
    /// file name the shell used before staging existed.
    static func defaultFileURL(platformOrigin: URL = PlatformConfig.platformOrigin) -> URL {
        let supportDirectory = URL.applicationSupportDirectory
        let host = platformOrigin.host() ?? "unknown"
        if host == PlatformConfig.liveHost {
            return supportDirectory.appending(path: "midas-local-records.json")
        }
        return supportDirectory.appending(path: "midas-local-records-\(host).json")
    }

    func addChangeObserver(_ observer: @escaping @MainActor (LocalRecordChange) -> Void) {
        changeObservers.append(observer)
    }

    func set(sidekickId: String, key: String, value: JSONValue) throws {
        var sidekickRecords = recordsBySidekick[sidekickId] ?? [:]
        sidekickRecords[key] = value
        recordsBySidekick[sidekickId] = sidekickRecords
        outbox.append(Self.newPendingOp(sidekickId: sidekickId, key: key, value: value))
        try save()
        notifyObservers(sidekickId: sidekickId, key: key)
    }

    func get(sidekickId: String, key: String) -> JSONValue? {
        recordsBySidekick[sidekickId]?[key]
    }

    func delete(sidekickId: String, key: String) throws {
        let removedValue = recordsBySidekick[sidekickId]?.removeValue(forKey: key)
        guard removedValue != nil else {
            return
        }
        outbox.append(Self.newPendingOp(sidekickId: sidekickId, key: key, value: nil))
        try save()
        notifyObservers(sidekickId: sidekickId, key: key)
    }

    /// One Sidekick's records whose key starts with the prefix, sorted by key.
    func query(sidekickId: String, keyPrefix: String) -> [LocalRecord] {
        let sidekickRecords = recordsBySidekick[sidekickId] ?? [:]
        var matchingRecords: [LocalRecord] = []
        for (key, value) in sidekickRecords where key.hasPrefix(keyPrefix) {
            matchingRecords.append(LocalRecord(sidekickId: sidekickId, key: key, value: value))
        }
        matchingRecords.sort(by: Self.isOrderedByKey)
        return matchingRecords
    }

    /// Records from every Sidekick whose key starts with the prefix. Shell use only.
    func queryAllSidekicks(keyPrefix: String) -> [LocalRecord] {
        var matchingRecords: [LocalRecord] = []
        let sortedSidekickIds = recordsBySidekick.keys.sorted()
        for sidekickId in sortedSidekickIds {
            let sidekickMatches = query(sidekickId: sidekickId, keyPrefix: keyPrefix)
            matchingRecords.append(contentsOf: sidekickMatches)
        }
        return matchingRecords
    }

    // MARK: Sync (used by RecordSync only)

    var pendingOpCount: Int {
        outbox.count
    }

    /// The oldest ops not yet confirmed by the server, in the order they were written.
    func pendingOps() -> [PendingOp] {
        outbox
    }

    /// Drops ops the server has stored (or refused for good) from the outbox.
    func removeFromOutbox(opIds: Set<String>) throws {
        guard !opIds.isEmpty else {
            return
        }
        var keptOps: [PendingOp] = []
        for pendingOp in outbox where !opIds.contains(pendingOp.opId) {
            keptOps.append(pendingOp)
        }
        outbox = keptOps
        try save()
    }

    /// Applies ops pulled from the server, in order, and moves the cursor to lastSeq. A key with
    /// a local change still in the outbox keeps the local value: that change is pushed later,
    /// gets a higher sequence, and so wins on every device (last write wins by sequence).
    func applyRemote(ops: [RemoteOp], lastSeq: Int) throws {
        let keysWithPendingChanges = pendingKeys()
        var changedRecords: [LocalRecordChange] = []
        for remoteOp in ops {
            let recordId = LocalRecordChange(sidekickId: remoteOp.sidekickId, key: remoteOp.key)
            if keysWithPendingChanges.contains(Self.pendingKey(sidekickId: remoteOp.sidekickId, key: remoteOp.key)) {
                continue
            }
            if applyWithoutOutbox(remoteOp) && !changedRecords.contains(recordId) {
                changedRecords.append(recordId)
            }
        }
        lastPulledSeq = max(lastPulledSeq, lastSeq)
        try save()
        for change in changedRecords {
            notifyObservers(sidekickId: change.sidekickId, key: change.key)
        }
    }

    func markInitialPullCompleted() throws {
        hasCompletedInitialPull = true
        try save()
    }

    /// Returns whether the record actually changed.
    private func applyWithoutOutbox(_ remoteOp: RemoteOp) -> Bool {
        var sidekickRecords = recordsBySidekick[remoteOp.sidekickId] ?? [:]
        let currentValue = sidekickRecords[remoteOp.key]
        if remoteOp.deleted {
            guard currentValue != nil else {
                return false
            }
            sidekickRecords.removeValue(forKey: remoteOp.key)
        } else {
            let newValue = remoteOp.value ?? .null
            guard currentValue != newValue else {
                return false
            }
            sidekickRecords[remoteOp.key] = newValue
        }
        recordsBySidekick[remoteOp.sidekickId] = sidekickRecords
        return true
    }

    private func pendingKeys() -> Set<String> {
        var keys = Set<String>()
        for pendingOp in outbox {
            keys.insert(Self.pendingKey(sidekickId: pendingOp.sidekickId, key: pendingOp.key))
        }
        return keys
    }

    private static func pendingKey(sidekickId: String, key: String) -> String {
        "\(sidekickId)\u{0}\(key)"
    }

    private static func newPendingOp(sidekickId: String, key: String, value: JSONValue?) -> PendingOp {
        let clientTime = Date().ISO8601Format(.iso8601WithTimeZone(includingFractionalSeconds: true))
        return PendingOp(opId: UUID().uuidString, sidekickId: sidekickId, key: key, value: value, deleted: value == nil, clientTime: clientTime)
    }

    private static func isOrderedByKey(_ first: LocalRecord, _ second: LocalRecord) -> Bool {
        first.key < second.key
    }

    private func notifyObservers(sidekickId: String, key: String) {
        let change = LocalRecordChange(sidekickId: sidekickId, key: key)
        for observer in changeObservers {
            observer(change)
        }
    }

    // MARK: File

    /// The file since 2026-10-13. Before that the file was the bare records dictionary.
    private struct SavedState: Codable {
        var formatVersion = 2
        var records: [String: [String: JSONValue]]
        var outbox: [PendingOp]
        var lastPulledSeq: Int
        var hasCompletedInitialPull: Bool
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = SavedState(records: recordsBySidekick, outbox: outbox, lastPulledSeq: lastPulledSeq, hasCompletedInitialPull: hasCompletedInitialPull)
        let encodedState = try JSONEncoder().encode(state)
        try encodedState.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // A missing or unreadable file starts an empty store rather than crashing the shell. A file
    // in the old format keeps its records and queues every one of them for upload, so records
    // written before sync existed are backed up too.
    private static func loadState(from fileURL: URL) -> SavedState {
        let emptyState = SavedState(records: [:], outbox: [], lastPulledSeq: 0, hasCompletedInitialPull: false)
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return emptyState
        }
        let decoder = JSONDecoder()
        if let savedState = try? decoder.decode(SavedState.self, from: fileData) {
            return savedState
        }
        guard let oldRecords = try? decoder.decode([String: [String: JSONValue]].self, from: fileData) else {
            return emptyState
        }
        return SavedState(records: oldRecords, outbox: uploadOps(for: oldRecords), lastPulledSeq: 0, hasCompletedInitialPull: false)
    }

    private static func uploadOps(for records: [String: [String: JSONValue]]) -> [PendingOp] {
        var ops: [PendingOp] = []
        let sortedSidekickIds = records.keys.sorted()
        for sidekickId in sortedSidekickIds {
            let sidekickRecords = records[sidekickId] ?? [:]
            let sortedKeys = sidekickRecords.keys.sorted()
            for key in sortedKeys {
                ops.append(newPendingOp(sidekickId: sidekickId, key: key, value: sidekickRecords[key]))
            }
        }
        return ops
    }
}
