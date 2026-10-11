import Foundation
import Observation

// Native import of Apple Reminders (founder, 2026-10-09 and 2026-10-10). A Sidekick never calls
// a native API: it writes a request record, the shell asks the user, reads Reminders on the phone
// with EventKit and writes the result back into that Sidekick's own records.
//
//   Sidekick writes  request:<id>        { kind: "import.apple-reminders", status: "pending" }
//   shell writes     import:<id>:<nnnn>  one part of the export (each under the 64 KB record cap)
//   shell updates    request:<id>        { status: "done" | "denied" | "cancelled" | "failed", ... }
//
// The export has the same shape as the Mac export the page already reads (lists, reminders),
// plus "origin": "iphone", which tells the page that the phone's version wins.

// MARK: What the phone gives us, as plain values

struct PhoneReminderList: Equatable, Sendable {
    let id: String
    let title: String
    let colorHex: String?
}

struct PhoneReminderDue: Equatable, Sendable {
    let allDay: Bool
    /// "YYYY-MM-DD"
    let date: String
    /// "HH:mm", nil when all day.
    let time: String?
    let timeZone: String?
    /// ISO 8601 with offset, nil when all day.
    let instant: String?
}

struct PhoneReminderAlarm: Equatable, Sendable {
    let absoluteDate: String?
    let relativeOffsetSeconds: Double?
}

struct PhoneRecurrenceDay: Equatable, Sendable {
    /// 1 (Sunday) to 7 (Saturday), as Apple counts.
    let weekday: Int
    /// 0 when the rule means every such weekday.
    let weekNumber: Int
}

struct PhoneRecurrenceRule: Equatable, Sendable {
    /// "daily", "weekly", "monthly" or "yearly"
    let frequency: String
    let interval: Int
    let daysOfWeek: [PhoneRecurrenceDay]?
    let daysOfMonth: [Int]?
    let monthsOfYear: [Int]?
    let weeksOfYear: [Int]?
    let daysOfYear: [Int]?
    let setPositions: [Int]?
    let endDate: String?
    let endOccurrenceCount: Int?
}

struct PhoneReminder: Equatable, Sendable {
    let id: String
    let externalId: String
    let listId: String
    let title: String
    let notes: String?
    let url: String?
    let completed: Bool
    let completionDate: String?
    let creationDate: String?
    let lastModifiedDate: String?
    let priority: Int
    let due: PhoneReminderDue?
    let alarms: [PhoneReminderAlarm]
    let recurrence: [PhoneRecurrenceRule]
}

// MARK: The export, as JSON in the Mac export's shape

enum AppleRemindersExport {
    static let source = "apple-reminders"
    static let origin = "iphone"
    /// Parts stay well under the 64 KB record cap, leaving room for the part fields.
    static let partByteBudget = 60_000
    /// A single reminder's notes are cut to this many characters so it always fits in a part.
    static let maxNotesCharacters = 20_000

    static func listJSON(_ list: PhoneReminderList) -> JSONValue {
        let color: JSONValue = list.colorHex.map(JSONValue.string) ?? .null
        return .object(["id": .string(list.id), "title": .string(list.title), "color": color])
    }

    static func reminderJSON(_ reminder: PhoneReminder) -> JSONValue {
        var alarms: [JSONValue] = []
        for alarm in reminder.alarms {
            alarms.append(alarmJSON(alarm))
        }
        var rules: [JSONValue] = []
        for rule in reminder.recurrence {
            rules.append(ruleJSON(rule))
        }
        let notes = reminder.notes.map(shortenedNotes)
        return .object([
            "id": .string(reminder.id),
            "externalId": .string(reminder.externalId),
            "listId": .string(reminder.listId),
            "title": .string(reminder.title),
            "notes": optionalString(notes),
            "url": optionalString(reminder.url),
            "completed": .bool(reminder.completed),
            "completionDate": optionalString(reminder.completionDate),
            "creationDate": optionalString(reminder.creationDate),
            "lastModifiedDate": optionalString(reminder.lastModifiedDate),
            "priority": .number(Double(reminder.priority)),
            "due": reminder.due.map(dueJSON) ?? .null,
            "alarms": .array(alarms),
            "recurrence": .array(rules),
        ])
    }

    /// The export split into parts, each one record under the cap. Lists and the export's own
    /// fields go in the first part; reminders keep their order across parts.
    static func parts(lists: [PhoneReminderList], reminders: [PhoneReminder], exportedAt: String, timeZone: String) -> [JSONValue] {
        var listValues: [JSONValue] = []
        for list in lists {
            listValues.append(listJSON(list))
        }
        var groups: [[JSONValue]] = [[]]
        var groupBytes = headerByteCount(lists: listValues, exportedAt: exportedAt, timeZone: timeZone)
        for reminder in reminders {
            let reminderValue = reminderJSON(reminder)
            // +1 for the comma between array elements
            let reminderBytes = RecordSync.valueByteCount(reminderValue) + 1
            let currentGroupIsEmpty = groups[groups.count - 1].isEmpty
            if groupBytes + reminderBytes > partByteBudget && !currentGroupIsEmpty {
                groups.append([])
                groupBytes = headerByteCount(lists: [], exportedAt: exportedAt, timeZone: timeZone)
            }
            groups[groups.count - 1].append(reminderValue)
            groupBytes += reminderBytes
        }
        var partValues: [JSONValue] = []
        for (index, group) in groups.enumerated() {
            let partLists = index == 0 ? listValues : []
            let part = partJSON(index: index, count: groups.count, lists: partLists, reminders: group, exportedAt: exportedAt, timeZone: timeZone)
            partValues.append(part)
        }
        return partValues
    }

    static func partKey(requestId: String, index: Int) -> String {
        let paddedIndex = String(format: "%04d", index)
        return "import:\(requestId):\(paddedIndex)"
    }

    private static func partJSON(index: Int, count: Int, lists: [JSONValue], reminders: [JSONValue], exportedAt: String, timeZone: String) -> JSONValue {
        return .object([
            "source": .string(source),
            "origin": .string(origin),
            "exportedAt": .string(exportedAt),
            "timeZone": .string(timeZone),
            "part": .number(Double(index)),
            "parts": .number(Double(count)),
            "lists": .array(lists),
            "reminders": .array(reminders),
        ])
    }

    private static func headerByteCount(lists: [JSONValue], exportedAt: String, timeZone: String) -> Int {
        let emptyPart = partJSON(index: 9999, count: 9999, lists: lists, reminders: [], exportedAt: exportedAt, timeZone: timeZone)
        return RecordSync.valueByteCount(emptyPart)
    }

    private static func shortenedNotes(_ notes: String) -> String {
        guard notes.count > maxNotesCharacters else {
            return notes
        }
        return String(notes.prefix(maxNotesCharacters))
    }

    private static func optionalString(_ text: String?) -> JSONValue {
        guard let text else {
            return .null
        }
        return .string(text)
    }

    private static func optionalNumbers(_ numbers: [Int]?) -> JSONValue {
        guard let numbers, !numbers.isEmpty else {
            return .null
        }
        var values: [JSONValue] = []
        for number in numbers {
            values.append(.number(Double(number)))
        }
        return .array(values)
    }

    private static func dueJSON(_ due: PhoneReminderDue) -> JSONValue {
        return .object([
            "allDay": .bool(due.allDay),
            "date": .string(due.date),
            "time": optionalString(due.time),
            "timeZone": optionalString(due.timeZone),
            "instant": optionalString(due.instant),
        ])
    }

    private static func alarmJSON(_ alarm: PhoneReminderAlarm) -> JSONValue {
        let offset: JSONValue = alarm.relativeOffsetSeconds.map(JSONValue.number) ?? .null
        return .object(["absoluteDate": optionalString(alarm.absoluteDate), "relativeOffsetSeconds": offset])
    }

    private static func ruleJSON(_ rule: PhoneRecurrenceRule) -> JSONValue {
        var daysOfWeek: JSONValue = .null
        if let days = rule.daysOfWeek, !days.isEmpty {
            var dayValues: [JSONValue] = []
            for day in days {
                dayValues.append(.object(["weekday": .number(Double(day.weekday)), "weekNumber": .number(Double(day.weekNumber))]))
            }
            daysOfWeek = .array(dayValues)
        }
        var end: JSONValue = .null
        if rule.endDate != nil || rule.endOccurrenceCount != nil {
            var count: JSONValue = .null
            if let occurrenceCount = rule.endOccurrenceCount {
                count = .number(Double(occurrenceCount))
            }
            end = .object(["date": optionalString(rule.endDate), "occurrenceCount": count])
        }
        return .object([
            "frequency": .string(rule.frequency),
            "interval": .number(Double(rule.interval)),
            "daysOfWeek": daysOfWeek,
            "daysOfMonth": optionalNumbers(rule.daysOfMonth),
            "monthsOfYear": optionalNumbers(rule.monthsOfYear),
            "weeksOfYear": optionalNumbers(rule.weeksOfYear),
            "daysOfYear": optionalNumbers(rule.daysOfYear),
            "setPositions": optionalNumbers(rule.setPositions),
            "end": end,
        ])
    }
}

// MARK: Reading Reminders on the phone

enum PhoneRemindersError: Error, Equatable {
    case readFailed
}

/// Where the reminders come from: EventKit on a phone, a fake in tests.
@MainActor
protocol PhoneRemindersSource {
    /// Asks iOS for full access to Reminders (the system alert shows once); true if granted.
    func requestAccess() async -> Bool
    func readAll() async throws -> (lists: [PhoneReminderList], reminders: [PhoneReminder])
}

// MARK: Request records

/// One import a Sidekick asked for, waiting for the user's answer in the Midas sheet.
struct AppleRemindersImportRequest: Identifiable, Equatable, Sendable {
    let sidekickId: String
    let requestKey: String

    var id: String {
        sidekickId + "|" + requestKey
    }

    var requestId: String {
        String(requestKey.dropFirst(ShellRequests.keyPrefix.count))
    }
}

enum ShellRequests {
    static let keyPrefix = "request:"
    static let importAppleRemindersKind = "import.apple-reminders"
}

/// Receives request records written by Sidekicks, shows the import sheet, and carries out the
/// import the user agreed to. Results go only into the records of the Sidekick that asked.
@MainActor
@Observable
final class AppleRemindersImportCenter {
    /// The request the sheet is showing; nil when no sheet.
    var shownRequest: AppleRemindersImportRequest?
    private(set) var isImporting = false

    @ObservationIgnored private let store: LocalRecordStore
    @ObservationIgnored private let source: PhoneRemindersSource
    @ObservationIgnored private let now: @MainActor () -> Date

    init(store: LocalRecordStore, source: PhoneRemindersSource, now: @escaping @MainActor () -> Date = Date.init) {
        self.store = store
        self.source = source
        self.now = now
    }

    /// Called by the store channel after a Sidekick writes a `request:` record.
    func handleRequestWritten(sidekickId: String, key: String, value: JSONValue) {
        guard value["status"]?.stringValue == "pending" else {
            return
        }
        guard value["kind"]?.stringValue == ShellRequests.importAppleRemindersKind else {
            finish(sidekickId: sidekickId, requestKey: key, status: "failed", extraFields: ["error": .string("unknown request")])
            return
        }
        let request = AppleRemindersImportRequest(sidekickId: sidekickId, requestKey: key)
        if let previousRequest = shownRequest, previousRequest != request {
            finish(sidekickId: previousRequest.sidekickId, requestKey: previousRequest.requestKey, status: "cancelled", extraFields: [:])
        }
        shownRequest = request
    }

    /// "Not now", or the sheet swiped away.
    func cancelShownRequest() {
        guard let request = shownRequest, !isImporting else {
            return
        }
        shownRequest = nil
        finish(sidekickId: request.sidekickId, requestKey: request.requestKey, status: "cancelled", extraFields: [:])
    }

    /// "Continue": iOS permission, read, write the parts, mark the request done.
    func runShownRequest() async {
        guard let request = shownRequest, !isImporting else {
            return
        }
        isImporting = true
        defer {
            isImporting = false
            shownRequest = nil
        }
        let isAllowed = await source.requestAccess()
        guard isAllowed else {
            finish(sidekickId: request.sidekickId, requestKey: request.requestKey, status: "denied", extraFields: [:])
            return
        }
        do {
            let phoneData = try await source.readAll()
            let exportedAt = ISO8601DateFormatter.deviceZone.string(from: now())
            let deviceZone = TimeZone.current.identifier
            let partValues = AppleRemindersExport.parts(lists: phoneData.lists, reminders: phoneData.reminders, exportedAt: exportedAt, timeZone: deviceZone)
            for (index, partValue) in partValues.enumerated() {
                let partKey = AppleRemindersExport.partKey(requestId: request.requestId, index: index)
                try store.set(sidekickId: request.sidekickId, key: partKey, value: partValue)
            }
            let partPrefix = "import:\(request.requestId):"
            let doneFields: [String: JSONValue] = [
                "parts": .number(Double(partValues.count)),
                "prefix": .string(partPrefix),
                "lists": .number(Double(phoneData.lists.count)),
                "reminders": .number(Double(phoneData.reminders.count)),
            ]
            finish(sidekickId: request.sidekickId, requestKey: request.requestKey, status: "done", extraFields: doneFields)
        } catch {
            finish(sidekickId: request.sidekickId, requestKey: request.requestKey, status: "failed", extraFields: ["error": .string("could not read Reminders")])
        }
    }

    /// Rewrites the request record with its outcome, keeping what the Sidekick put in it.
    private func finish(sidekickId: String, requestKey: String, status: String, extraFields: [String: JSONValue]) {
        var fields: [String: JSONValue] = [:]
        if case .object(let existingFields) = store.get(sidekickId: sidekickId, key: requestKey) {
            fields = existingFields
        }
        fields["status"] = .string(status)
        fields["finishedAt"] = .string(ISO8601DateFormatter.deviceZone.string(from: now()))
        for (fieldName, fieldValue) in extraFields {
            fields[fieldName] = fieldValue
        }
        try? store.set(sidekickId: sidekickId, key: requestKey, value: .object(fields))
    }
}

extension ISO8601DateFormatter {
    /// "2026-10-10T21:30:00-07:00", the form the Mac export uses.
    static var deviceZone: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }
}
