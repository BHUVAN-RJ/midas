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

/// Sidekick records kept on the phone, so Sidekicks work without a connection. Each Sidekick
/// sees only its own records; the shell (the notification engine) can read across all of them.
/// Saved as one JSON file, rewritten atomically on every change.
@MainActor
final class LocalRecordStore {
    private let fileURL: URL
    // sidekickId -> key -> value
    private var recordsBySidekick: [String: [String: JSONValue]] = [:]
    private var changeObservers: [(LocalRecordChange) -> Void] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.recordsBySidekick = Self.loadRecords(from: fileURL)
    }

    static func defaultFileURL() -> URL {
        let supportDirectory = URL.applicationSupportDirectory
        return supportDirectory.appending(path: "midas-local-records.json")
    }

    func addChangeObserver(_ observer: @escaping (LocalRecordChange) -> Void) {
        changeObservers.append(observer)
    }

    func set(sidekickId: String, key: String, value: JSONValue) throws {
        var sidekickRecords = recordsBySidekick[sidekickId] ?? [:]
        sidekickRecords[key] = value
        recordsBySidekick[sidekickId] = sidekickRecords
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

    private static func isOrderedByKey(_ first: LocalRecord, _ second: LocalRecord) -> Bool {
        first.key < second.key
    }

    private func notifyObservers(sidekickId: String, key: String) {
        let change = LocalRecordChange(sidekickId: sidekickId, key: key)
        for observer in changeObservers {
            observer(change)
        }
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encodedRecords = try JSONEncoder().encode(recordsBySidekick)
        try encodedRecords.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // A missing or unreadable file starts an empty store rather than crashing the shell.
    private static func loadRecords(from fileURL: URL) -> [String: [String: JSONValue]] {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        let decodedRecords = try? JSONDecoder().decode([String: [String: JSONValue]].self, from: fileData)
        return decodedRecords ?? [:]
    }
}
