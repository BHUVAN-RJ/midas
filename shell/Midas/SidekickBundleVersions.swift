import Foundation

/// Which bundle each open Sidekick is running: the `X-Midas-Bundle-Version` and
/// `X-Midas-Bundle-Scope` (`user` | `base`) headers from its last bundle load. A repair report
/// names them so the runner starts from the copy the reporter was looking at. Recorded by the
/// bundle loader (wired by the lead); read on send. Lock-based so the loader can record from any
/// thread.
final class SidekickBundleVersions: @unchecked Sendable {
    struct Entry: Equatable, Sendable {
        let version: String
        let scope: String
    }

    static let shared = SidekickBundleVersions()
    static let scopeHeader = "X-Midas-Bundle-Scope"
    static let unknownVersion = "unknown"
    static let unknownScope = "unknown"

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func record(sidekickId: String, version: String, scope: String?) {
        let entry = Entry(version: version, scope: scope ?? Self.unknownScope)
        lock.lock()
        entries[sidekickId] = entry
        lock.unlock()
    }

    func entry(forSidekickId sidekickId: String) -> Entry {
        lock.lock()
        let found = entries[sidekickId]
        lock.unlock()
        return found ?? Entry(version: Self.unknownVersion, scope: Self.unknownScope)
    }
}
