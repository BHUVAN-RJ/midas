import Foundation

// Work log entries are links (founder, 2026-10-31; approved mockup
// docs/mockups/jess-worklog-links-2026-10-31.html). A done card on jess's Workdesk remembers
// which records its Sidekick changed: the record key, whether it was new, edited or deleted, and
// the old value for an edit or a delete. A tap on the card opens that Sidekick over jess at the
// first change; the page marks it in Volt (shell/sdk/midas-store.js `store.focus()`).

/// One record a jess task changed.
struct JessChange: Codable, Equatable, Sendable {
    enum Op: String, Codable, Sendable {
        case new
        case edit
        case delete
    }

    let key: String
    let op: Op
    /// The value before the change: an edit's old value, a deleted record (for Undo). Nil for new.
    var before: JSONValue? = nil

    /// What the page reads from the store channel's `focus` op.
    var json: JSONValue {
        var fields: [String: JSONValue] = ["key": .string(key), "op": .string(op.rawValue)]
        if let before {
            fields["before"] = before
        }
        return .object(fields)
    }
}

/// The Sidekick a done task changed, and its changes in the order the tool wrote them.
struct JessChangeLink: Codable, Equatable, Sendable {
    let sidekickId: String
    let changes: [JessChange]

    /// The record the page opens at.
    var first: JessChange? {
        changes.first
    }

    /// The link for a tool's ops, from the records as they were just before the ops were written:
    /// a set on a key that was there is an edit, any other set is new, a delete keeps the old value.
    /// Nil when the ops changed nothing.
    static func make(sidekickId: String, ops: [SidekickToolOp], recordsBefore: [LocalRecord]) -> JessChangeLink? {
        var valuesBefore: [String: JSONValue] = [:]
        for record in recordsBefore {
            valuesBefore[record.key] = record.value
        }
        var changes: [JessChange] = []
        var seenKeys: Set<String> = []
        for op in ops {
            let change = change(for: op, valuesBefore: valuesBefore)
            // One entry per record: a key written twice by one tool keeps its first meaning
            guard !seenKeys.contains(change.key) else {
                continue
            }
            seenKeys.insert(change.key)
            changes.append(change)
        }
        if changes.isEmpty {
            return nil
        }
        return JessChangeLink(sidekickId: sidekickId, changes: changes)
    }

    private static func change(for op: SidekickToolOp, valuesBefore: [String: JSONValue]) -> JessChange {
        switch op {
        case .set(let key, _):
            if let oldValue = valuesBefore[key] {
                return JessChange(key: key, op: .edit, before: oldValue)
            }
            return JessChange(key: key, op: .new)
        case .delete(let key):
            return JessChange(key: key, op: .delete, before: valuesBefore[key])
        }
    }

    /// Where a tap opens, with the record store as it is now: at the first change, or at the top
    /// with "Already Deleted" when a new or edited record was deleted since. A deleted record that
    /// is back (Undo, or made again) is marked where it now is.
    func target(currentValue: (_ key: String) -> JSONValue?) -> JessLinkTarget {
        guard let first else {
            return JessLinkTarget(sidekickId: sidekickId, focus: nil, isGone: false)
        }
        let exists = currentValue(first.key) != nil
        switch first.op {
        case .new, .edit:
            if !exists {
                return JessLinkTarget(sidekickId: sidekickId, focus: nil, isGone: true)
            }
            return JessLinkTarget(sidekickId: sidekickId, focus: first, isGone: false)
        case .delete:
            if exists {
                return JessLinkTarget(sidekickId: sidekickId, focus: JessChange(key: first.key, op: .new), isGone: false)
            }
            return JessLinkTarget(sidekickId: sidekickId, focus: first, isGone: false)
        }
    }
}

/// What one tap on a linked card opens.
struct JessLinkTarget: Equatable, Sendable {
    let sidekickId: String
    /// Handed to the page once through the store channel; nil opens the page at its top.
    let focus: JessChange?
    /// The record was deleted since: the page opens at its top with "Already Deleted".
    let isGone: Bool
}

/// Words on the opened Sidekick (docs/WRITING.md: say it, stop).
enum JessLinkCopy {
    static let alreadyDeleted = "Already Deleted"
}

extension JessResultCard {
    /// Done cards with a change are links; repair, grow, Not Done and waiting cards are not
    /// (founder, 2026-10-31: repair and grow "stay as is").
    var opensChange: Bool {
        guard case .done = kind else {
            return false
        }
        return link != nil
    }
}
