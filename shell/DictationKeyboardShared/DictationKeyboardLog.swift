#if MIDAS_TEST_BUILD
// Build 35: the keyboard log (TEST BUILD, founder 2026-11-19; branch agent/dictation-test, never
// merged; docs/briefs/dictation-keyboard-test.md, "Build 35"). Compiled into the Midas Test app and
// the MidasKeyboard extension.
//
// The keyboard appends each step to a small ring log in the App Group (the last 50: time, event,
// detail): appeared, the route chosen and why, full access, microphone permission, each microphone
// step with its result or error, the extension's memory, disappeared. Midas Test saves the whole
// log as one `log:keyboard` record of the Dictation Sidekick (`dictation.log`) when it opens or is
// notified; the Dictation page shows it newest first.
import Darwin
import Foundation
import os

/// One line of the keyboard log.
struct DictationKeyboardLogEntry: Codable, Equatable, Sendable {
    let at: Date
    /// What happened: "appeared", "route", "mic step", "probe", "queue failed", "disappeared", ...
    let event: String
    let detail: String
}

/// The ring log's rules and its record.
enum DictationKeyboardLog {
    /// The log keeps this many entries, oldest dropped first.
    static let maxEntries = 50
    /// The manifest's maxLength for an event and a detail.
    static let maxEventCharacters = 40
    static let maxDetailCharacters = 300
    /// The one record Midas Test writes (manifest `log:`, `dictation.log`).
    static let recordKey = "log:keyboard"
    static let logFile = "keyboard-log.json"

    /// The entries with one more, cut to its limits; the oldest dropped past `maxEntries`.
    static func appending(_ entry: DictationKeyboardLogEntry, to entries: [DictationKeyboardLogEntry]) -> [DictationKeyboardLogEntry] {
        let shortened = DictationKeyboardLogEntry(at: entry.at, event: String(entry.event.prefix(maxEventCharacters)),
                                                  detail: String(entry.detail.prefix(maxDetailCharacters)))
        var updated = entries
        updated.append(shortened)
        let overflow = updated.count - maxEntries
        if overflow > 0 {
            updated.removeFirst(overflow)
        }
        return updated
    }

    /// The `log:keyboard` record: the entries oldest first (the page turns them round), and when.
    static func recordValue(_ entries: [DictationKeyboardLogEntry], updatedAt: Date) -> JSONValue {
        var lines: [JSONValue] = []
        for entry in entries.suffix(maxEntries) {
            lines.append(.object([
                "at": .string(DictationProbeRecord.timestamp(entry.at)),
                "event": .string(String(entry.event.prefix(maxEventCharacters))),
                "detail": .string(String(entry.detail.prefix(maxDetailCharacters))),
            ]))
        }
        return .object([
            "updatedAt": .string(DictationProbeRecord.timestamp(updatedAt)),
            "entries": .array(lines),
        ])
    }

    /// "footprint 23.4 MB, available 41.0 MB": the extension's own memory and what iOS still allows
    /// it (a keyboard is ended near its limit). "unknown" where iOS gives no number.
    static func memoryDetail() -> String {
        let footprint = footprintBytes().map(megabytes) ?? "unknown"
        let available = os_proc_available_memory()
        let availableText = available > 0 ? megabytes(UInt64(available)) : "unknown"
        return "footprint \(footprint), available \(availableText)"
    }

    private static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // The task's physical footprint, as Xcode's memory gauge shows it
    private static func footprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), integerPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return info.phys_footprint
    }
}

extension DictationKeyboardMailbox {
    func readLog() -> [DictationKeyboardLogEntry] {
        let fileURL = folder.appending(path: DictationKeyboardLog.logFile)
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return DictationKeyboardHandoff.decode([DictationKeyboardLogEntry].self, from: data) ?? []
    }

    /// One more line in the ring log (the whole file replaced at once).
    func appendLog(_ entry: DictationKeyboardLogEntry) throws {
        let updated = DictationKeyboardLog.appending(entry, to: readLog())
        let data = try DictationKeyboardHandoff.encode(updated)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appending(path: DictationKeyboardLog.logFile), options: .atomic)
    }
}
#endif
