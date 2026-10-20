import Foundation

/// A voice reminder as a record of the Reminders Sidekick (reminders.item in
/// sidekicks/reminders/manifest.json), built the way the page's `recordFromItem(item, null)` builds
/// a new item: key `reminder:<12 base36>`, `$type`, `title`, `notes` only if there are notes,
/// `list` only if one was named, `done: false`, `timeZone`, `createdAt`, and if dated `at`,
/// `allDay` and `repeat` only if it repeats. A field is left out instead of written as null.
enum VoiceReminderRecord {
    static let sidekickId = "reminders"
    static let keyPrefix = "reminder:"
    static let typeName = "reminders.item"
    static let listPrefix = "list:"
    static let idLength = 12
    private static let idAlphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// 12 base36 characters from a secure random source, as the page's `newId()` makes them.
    static func newId() -> String {
        var generator = SystemRandomNumberGenerator()
        var id = ""
        for _ in 0..<idLength {
            let byte = UInt8.random(in: 0...255, using: &generator)
            id.append(idAlphabet[Int(byte) % idAlphabet.count])
        }
        return id
    }

    static func key(id: String) -> String {
        keyPrefix + id
    }

    static func value(for reminder: VoiceResolvedReminder, createdAt: Date) -> JSONValue {
        var fields: [String: JSONValue] = [
            "$type": .string(typeName),
            "title": .string(reminder.title),
            "done": .bool(false),
            "timeZone": .string(reminder.timeZone),
            "createdAt": .string(ReminderRecord.formatDate(createdAt)),
        ]
        if let notes = reminder.notes, !notes.isEmpty {
            fields["notes"] = .string(notes)
        }
        if let list = reminder.list, !list.isEmpty {
            fields["list"] = .string(list)
        }
        if let at = reminder.at {
            fields["at"] = .string(at)
            fields["allDay"] = .bool(reminder.allDay)
            if let repeatRule = reminder.repeat {
                fields["repeat"] = repeatValue(repeatRule)
            }
        }
        return .object(fields)
    }

    static func repeatValue(_ repeatRule: VoiceReminderRepeat) -> JSONValue {
        var fields: [String: JSONValue] = ["every": .string(repeatRule.every)]
        if let interval = repeatRule.interval, interval > 1 {
            fields["interval"] = .number(Double(interval))
        }
        if let weekdays = repeatRule.weekdays, !weekdays.isEmpty {
            var weekdayValues: [JSONValue] = []
            for weekday in weekdays {
                weekdayValues.append(.number(Double(weekday)))
            }
            fields["weekdays"] = .array(weekdayValues)
        }
        return .object(fields)
    }

    /// The user's Reminders lists from the phone's store: the model's list choices and the
    /// recogniser's hint words.
    @MainActor
    static func lists(in store: LocalRecordStore) -> [VoiceReminderList] {
        let records = store.query(sidekickId: sidekickId, keyPrefix: listPrefix)
        var lists: [VoiceReminderList] = []
        for record in records {
            guard let name = record.value["name"]?.stringValue, !name.isEmpty else {
                continue
            }
            let listId = String(record.key.dropFirst(listPrefix.count))
            lists.append(VoiceReminderList(id: listId, name: name))
        }
        return lists
    }

    /// Saves the reminder through the one shell writer, so the store's gate checks it against the
    /// user's own copy of the Reminders schema; the notification engine books it as usual.
    @MainActor
    @discardableResult
    static func save(_ reminder: VoiceResolvedReminder, writer: RecordWriter, now: Date, id: String = newId()) throws -> String {
        let recordKey = key(id: id)
        try writer.update(sidekickId: sidekickId, key: recordKey, patch: value(for: reminder, createdAt: now))
        return recordKey
    }
}
