import Foundation

/// The one way the shell changes a Sidekick's record (unified data plan, section 5, "Native
/// writers"): read the record, merge the patch (RFC 7396), run the store's write gate (`$type`,
/// the record's schema), check the size limit, write. The notification buttons, the Sidekick widget and
/// the Apple Reminders import all go through here with the same patches the pages produce
/// (`ReminderChange`), so a change gives the same record whoever made it. A patch touches only
/// the fields it names: unknown fields are kept.
@MainActor
final class RecordWriter {
    /// The server keeps values up to this size (backend/src/sync.ts MAX_VALUE_BYTES).
    static let maxValueBytes = SidekickStoreChannel.maxValueBytes

    private let store: LocalRecordStore

    init(store: LocalRecordStore) {
        self.store = store
    }

    /// The record as stored after the patch. A record that does not exist yet is built from the
    /// patch alone. Throws `RecordRefusal` with the reason when the result does not fit its type
    /// or is over the size limit; nothing is written then.
    @discardableResult
    func update(sidekickId: String, key: String, patch: JSONValue) throws -> JSONValue {
        let currentValue = store.get(sidekickId: sidekickId, key: key)
        let mergedValue = JSONMergePatch.apply(patch, to: currentValue)
        if RecordSync.valueByteCount(mergedValue) > Self.maxValueBytes {
            throw RecordRefusal(reason: "value is over \(Self.maxValueBytes) bytes")
        }
        try store.set(sidekickId: sidekickId, key: key, value: mergedValue)
        return store.get(sidekickId: sidekickId, key: key) ?? mergedValue
    }

    /// Applies what a Sidekick tool returned (jess router, founder 2026-10-21): whole records to
    /// store and keys to remove. Every stored value passes the write gate and the size limit
    /// before anything is written, so a tool that fails a check changes nothing; then the ops are
    /// written in order. Throws `RecordRefusal` naming the key that failed.
    func apply(sidekickId: String, ops: [SidekickToolOp]) throws {
        var checkedOps: [SidekickToolOp] = []
        for op in ops {
            switch op {
            case .set(let key, let value):
                let checkedValue: JSONValue
                do {
                    checkedValue = try store.checkedValue(sidekickId: sidekickId, key: key, value: value)
                } catch let refusal as RecordRefusal {
                    throw RecordRefusal(reason: "\(key): \(refusal.reason)")
                }
                if RecordSync.valueByteCount(checkedValue) > Self.maxValueBytes {
                    throw RecordRefusal(reason: "\(key): value is over \(Self.maxValueBytes) bytes")
                }
                checkedOps.append(.set(key: key, value: checkedValue))
            case .delete:
                checkedOps.append(op)
            }
        }
        for op in checkedOps {
            switch op {
            case .set(let key, let value):
                try store.set(sidekickId: sidekickId, key: key, value: value)
            case .delete(let key):
                try store.delete(sidekickId: sidekickId, key: key)
            }
        }
    }
}
