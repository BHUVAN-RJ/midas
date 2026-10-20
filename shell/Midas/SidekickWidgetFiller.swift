import Foundation

// Fills a `widget:<name>` description (shell/Midas/SidekickWidgetDescription.swift) from the
// Sidekick's records: works out each source, replaces the bindings and turns the pieces into the
// filled pieces the widget draws (shell/Shared/SidekickWidgetShared.swift). Pure: the records come
// in as a list, so tests need no store.

struct SidekickWidgetFiller: Sendable {
    let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// The widget, filled for now and for the next midnight. A description the checker refuses is
    /// kept as unusable, so a placed widget shows "Open Midas" rather than vanishing.
    func fill(sidekickId: String, sidekickName: String, record: LocalRecord, sidekickRecords: [LocalRecord], now: Date) -> FilledSidekickWidget {
        let widgetId = String(record.key.dropFirst(SidekickWidgetShared.recordPrefix.count))
        let description = record.value
        let name = description["name"]?.stringValue ?? widgetId
        guard SidekickWidgetDescription.validationError(description) == nil else {
            return FilledSidekickWidget(sidekickId: sidekickId, sidekickName: sidekickName, widgetId: widgetId, name: name,
                                        tintHex: nil, isUsable: false, looks: [])
        }
        let tintHex = description["tint"].flatMap(Self.hexForTint)
        let startOfToday = calendar.startOfDay(for: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let context = FillContext(sidekickId: sidekickId, tintHex: tintHex)
        let lookNow = look(description: description, sidekickRecords: sidekickRecords, at: now, context: context)
        let lookAtMidnight = look(description: description, sidekickRecords: sidekickRecords, at: nextMidnight, context: context)
        return FilledSidekickWidget(sidekickId: sidekickId, sidekickName: sidekickName, widgetId: widgetId, name: name,
                                    tintHex: tintHex, isUsable: true, looks: [lookNow, lookAtMidnight])
    }

    private struct FillContext {
        let sidekickId: String
        let tintHex: String?
    }

    private func look(description: JSONValue, sidekickRecords: [LocalRecord], at moment: Date, context: FillContext) -> FilledWidgetLook {
        let scope = sourceValues(description: description, sidekickRecords: sidekickRecords, at: moment)
        let small = description["small"].flatMap { sizePiece in filledPiece(sizePiece, scope: scope, context: context) }
        let medium = description["medium"].flatMap { sizePiece in filledPiece(sizePiece, scope: scope, context: context) }
        let large = description["large"].flatMap { sizePiece in filledPiece(sizePiece, scope: scope, context: context) }
        return FilledWidgetLook(from: moment, small: small, medium: medium, large: large)
    }

    // MARK: Sources

    /// Each source's value at `moment`, by source name.
    func sourceValues(description: JSONValue, sidekickRecords: [LocalRecord], at moment: Date) -> [String: JSONValue] {
        guard case .object(let sourcesById)? = description["sources"] else {
            return [:]
        }
        var scope: [String: JSONValue] = [:]
        for (sourceId, source) in sourcesById {
            scope[sourceId] = sourceValue(source, sidekickRecords: sidekickRecords, at: moment)
        }
        return scope
    }

    private func sourceValue(_ source: JSONValue, sidekickRecords: [LocalRecord], at moment: Date) -> JSONValue {
        if let key = source["record"]?.stringValue {
            return singleRecordValue(key: key, sidekickRecords: sidekickRecords)
        }
        let prefix = source["records"]?.stringValue ?? ""
        let matchingRecords = Self.records(sidekickRecords, prefix: prefix, matching: source["where"])
        let limit = Int(source["limit"]?.numberValue ?? 20)
        switch source["when"]?.stringValue {
        case "today":
            return todayValue(reminderRecords: withHourlyTimes(matchingRecords), sidekickRecords: sidekickRecords, at: moment, limit: limit)
        case "upcoming":
            return upcomingValue(reminderRecords: withHourlyTimes(matchingRecords), sidekickRecords: sidekickRecords, at: moment, limit: limit)
        default:
            return recordsValue(matchingRecords, sumField: source["sum"]?.stringValue, limit: limit)
        }
    }

    /// Every hourly item's extra times as in-memory records (`reminder:<id>@HHMM`, never stored), so each
    /// dose counts in Today and Upcoming (plan section 4: hourly doses still count once they are
    /// fields). A tick on one lands on the item (SidekickWidgetPublisher.targetKey).
    private func withHourlyTimes(_ reminderRecords: [LocalRecord]) -> [LocalRecord] {
        let expansion = ReminderExpansion(schedule: ReminderSchedule(calendar: calendar))
        var expandedRecords: [LocalRecord] = []
        for record in reminderRecords {
            expandedRecords.append(record)
            expandedRecords.append(contentsOf: expansion.slotRecords(of: record))
        }
        return expandedRecords
    }

    /// Records under a prefix whose fields equal every `where` value.
    static func records(_ sidekickRecords: [LocalRecord], prefix: String, matching whereValue: JSONValue?) -> [LocalRecord] {
        var matchingRecords: [LocalRecord] = []
        for record in sidekickRecords where record.key.hasPrefix(prefix) {
            if matches(record.value, whereValue: whereValue) {
                matchingRecords.append(record)
            }
        }
        return matchingRecords
    }

    private static func matches(_ value: JSONValue, whereValue: JSONValue?) -> Bool {
        guard case .object(let conditions)? = whereValue else {
            return true
        }
        for (field, expected) in conditions where value[field] != expected {
            return false
        }
        return true
    }

    private func singleRecordValue(key: String, sidekickRecords: [LocalRecord]) -> JSONValue {
        for record in sidekickRecords where record.key == key {
            return Self.item(from: record)
        }
        return .null
    }

    /// A record as an item: its fields and its `key`.
    private static func item(from record: LocalRecord) -> JSONValue {
        var fields: [String: JSONValue] = [:]
        if case .object(let recordFields) = record.value {
            fields = recordFields
        } else {
            fields["value"] = record.value
        }
        fields["key"] = .string(record.key)
        return .object(fields)
    }

    /// { items, count, next, sum?, values? } for plain records.
    private func recordsValue(_ matchingRecords: [LocalRecord], sumField: String?, limit: Int) -> JSONValue {
        var items: [JSONValue] = []
        var values: [JSONValue] = []
        var sum = 0.0
        for record in matchingRecords {
            items.append(Self.item(from: record))
            if let sumField, let number = record.value[sumField]?.numberValue {
                sum += number
                values.append(.number(number))
            }
        }
        var fields: [String: JSONValue] = [
            "items": .array(Array(items.prefix(limit))),
            "count": .number(Double(items.count)),
            "next": items.first ?? .null,
        ]
        if sumField != nil {
            fields["sum"] = .number(sum)
            fields["values"] = .array(values)
        }
        return .object(fields)
    }

    /// Today's reminders, as the Reminders widget decides Today: { items (open, in time order),
    /// open, done (done today), count (open + done), next (the first open one) }.
    private func todayValue(reminderRecords: [LocalRecord], sidekickRecords: [LocalRecord], at moment: Date, limit: Int) -> JSONValue {
        let listRecords = Self.records(sidekickRecords, prefix: "list:", matching: nil)
        let planner = TodayReminderPlanner(calendar: calendar)
        let todayReminders = planner.reminders(reminderRecords: reminderRecords, listRecords: listRecords, now: moment)
        var recordsById: [String: LocalRecord] = [:]
        for record in reminderRecords {
            recordsById[String(record.key.dropFirst(ReminderRecord.keyPrefix.count))] = record
        }
        var items: [JSONValue] = []
        for todayReminder in todayReminders {
            guard let record = recordsById[todayReminder.id] else {
                continue
            }
            items.append(reminderItem(record: record, moment: todayReminder.at, allDay: todayReminder.allDay, colorHex: todayReminder.colorHex))
        }
        let doneCount = doneTodayCount(reminderRecords: reminderRecords, at: moment)
        let fields: [String: JSONValue] = [
            "items": .array(Array(items.prefix(limit))),
            "open": .number(Double(items.count)),
            "done": .number(Double(doneCount)),
            "count": .number(Double(items.count + doneCount)),
            "next": items.first ?? .null,
        ]
        return .object(fields)
    }

    /// Reminders dealt with on the day of `moment`: a one-time one completed that day, a repeat
    /// whose Done was tapped that day.
    private func doneTodayCount(reminderRecords: [LocalRecord], at moment: Date) -> Int {
        var doneCount = 0
        for record in reminderRecords {
            let value = record.value
            let isRepeat = value["repeat"] != nil && value["repeat"] != .null
            let doneMoment: Date?
            if isRepeat {
                doneMoment = ReminderRecord.parseDate(value["lastDoneAt"])
            } else if value["done"]?.boolValue == true {
                doneMoment = ReminderRecord.parseDate(value["completedAt"])
            } else {
                doneMoment = nil
            }
            if let doneMoment, calendar.isDate(doneMoment, inSameDayAs: moment) {
                doneCount += 1
            }
        }
        return doneCount
    }

    /// Reminders still to come after `moment`, each at its next time, in time order: { items,
    /// count, next }.
    private func upcomingValue(reminderRecords: [LocalRecord], sidekickRecords: [LocalRecord], at moment: Date, limit: Int) -> JSONValue {
        let listRecords = Self.records(sidekickRecords, prefix: "list:", matching: nil)
        let colorsByListId = TodayReminderPlanner.listColors(listRecords: listRecords)
        let schedule = ReminderSchedule(calendar: calendar)
        var upcoming: [(moment: Date, record: LocalRecord)] = []
        for storedRecord in reminderRecords {
            guard let reminder = ReminderRecord.parse(sidekickId: storedRecord.sidekickId, key: storedRecord.key, value: storedRecord.value),
                  !reminder.done else {
                continue
            }
            guard let nextMoment = nextMoment(of: reminder, value: storedRecord.value, after: moment, schedule: schedule) else {
                continue
            }
            upcoming.append((moment: nextMoment, record: storedRecord))
        }
        upcoming.sort(by: Self.isEarlier)
        var items: [JSONValue] = []
        for entry in upcoming.prefix(limit) {
            let listId = entry.record.value["list"]?.stringValue
            let colorHex = TodayReminderPlanner.circleColorHex(listId: listId, colorsByListId: colorsByListId)
            let allDay = entry.record.value["allDay"]?.boolValue ?? false
            items.append(reminderItem(record: entry.record, moment: entry.moment, allDay: allDay, colorHex: colorHex))
        }
        let fields: [String: JSONValue] = [
            "items": .array(items),
            "count": .number(Double(upcoming.count)),
            "next": items.first ?? .null,
        ]
        return .object(fields)
    }

    private static func isEarlier(_ first: (moment: Date, record: LocalRecord), _ second: (moment: Date, record: LocalRecord)) -> Bool {
        if first.moment != second.moment {
            return first.moment < second.moment
        }
        return first.record.key < second.record.key
    }

    private func nextMoment(of reminder: ReminderRecord, value: JSONValue, after moment: Date, schedule: ReminderSchedule) -> Date? {
        guard reminder.repeatRule != nil else {
            let effectiveMoment = TodayReminderPlanner.later(reminder.at, reminder.snoozedUntil)
            return effectiveMoment > moment ? effectiveMoment : nil
        }
        let handledThrough = TodayReminderPlanner.handledThrough(record: reminder, value: value)
        let searchFrom = max(moment, handledThrough)
        return schedule.occurrences(of: reminder, after: searchFrom, limit: 1).first
    }

    /// A reminder as an item: its record's fields, plus key, id, the moment as `at`, `time`
    /// ("9:00 AM", empty all day), `day` ("Tue"), `color` and `allDay`.
    private func reminderItem(record: LocalRecord, moment: Date, allDay: Bool, colorHex: String) -> JSONValue {
        guard case .object(var fields) = Self.item(from: record) else {
            return .null
        }
        fields["id"] = .string(String(record.key.dropFirst(ReminderRecord.keyPrefix.count)))
        fields["at"] = .string(ReminderRecord.formatDate(moment))
        fields["time"] = .string(allDay ? "" : clockText(moment))
        fields["day"] = .string(dayText(moment))
        fields["color"] = .string(colorHex)
        fields["allDay"] = .bool(allDay)
        return .object(fields)
    }

    private func clockText(_ moment: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: moment)
    }

    private func dayText(_ moment: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: moment)
    }

    // MARK: Pieces

    /// The filled piece, or nil when it is skipped: an unknown piece, an `if` that is not met, or
    /// a piece whose binding is missing (a tick with no item, a timer with no date).
    func filledPiece(_ piece: JSONValue, scope: [String: JSONValue]) -> WidgetPiece? {
        let context = FillContext(sidekickId: "", tintHex: nil)
        return filledPiece(piece, scope: scope, context: context)
    }

    private func filledPiece(_ piece: JSONValue, scope: [String: JSONValue], context: FillContext) -> WidgetPiece? {
        guard case .object(let fields) = piece else {
            return nil
        }
        guard isShown(fields: fields, scope: scope) else {
            return nil
        }
        let knownNames = fields.keys.filter(SidekickWidgetDescription.pieceNames.contains)
        guard let pieceName = knownNames.first, let content = fields[pieceName] else {
            return nil
        }
        let colorHex = fields["color"].flatMap { color in resolvedColorHex(color, scope: scope, context: context) }
        let isSecondary = fields["color"]?.stringValue == "secondary"
        switch pieceName {
        case "vstack", "hstack":
            let children = filledChildren(content, scope: scope, context: context)
            let stack = WidgetStackPiece(children: children, spacing: fields["spacing"]?.numberValue,
                                         alignment: fields["align"]?.stringValue.flatMap(WidgetAlignment.init(rawValue:)))
            return pieceName == "vstack" ? .vstack(stack) : .hstack(stack)
        case "grid":
            let children = filledChildren(content, scope: scope, context: context)
            let columns = Int(fields["columns"]?.numberValue ?? 2)
            return .grid(WidgetGridPiece(children: children, columns: columns, spacing: fields["spacing"]?.numberValue))
        case "list":
            return filledList(content: content, fields: fields, scope: scope, context: context)
        case "spacer":
            return .spacer
        case "divider":
            return .divider
        case "text":
            let text = SidekickWidgetBinding.interpolate(content.stringValue ?? "", scope: scope)
            let style = fields["style"]?.stringValue.flatMap(WidgetTextStyle.init(rawValue:)) ?? .body
            let lineLimit = Int(fields["lines"]?.numberValue ?? 1)
            return .text(WidgetTextPiece(text: text, style: style, colorHex: colorHex, isSecondary: isSecondary, lineLimit: lineLimit))
        case "symbol":
            let symbolName = SidekickWidgetBinding.interpolate(content.stringValue ?? "", scope: scope)
            guard !symbolName.isEmpty else {
                return nil
            }
            return .symbol(WidgetSymbolPiece(name: symbolName, colorHex: colorHex ?? context.tintHex, size: fields["size"]?.numberValue ?? 16))
        case "bar", "ring", "dots":
            return filledMeter(pieceName: pieceName, content: content, scope: scope, colorHex: colorHex ?? context.tintHex)
        case "chart":
            return filledChart(content: content, scope: scope, colorHex: colorHex ?? context.tintHex)
        case "timer":
            guard let target = ReminderRecord.parseDate(resolvedValue(content, scope: scope)) else {
                return nil
            }
            let style = fields["style"]?.stringValue.flatMap(WidgetTimerStyle.init(rawValue:)) ?? .relative
            let textStyle = fields["font"]?.stringValue.flatMap(WidgetTextStyle.init(rawValue:)) ?? .body
            return .timer(WidgetTimerPiece(target: target, style: style, colorHex: colorHex, textStyle: textStyle))
        case "tick":
            guard let action = tickAction(itemBinding: content, scope: scope, context: context) else {
                return nil
            }
            let itemColor = resolvedValue(content, scope: scope)?["color"]?.stringValue
            let tickColor = colorHex ?? itemColor ?? context.tintHex
            return .tick(WidgetTickPiece(action: action, colorHex: tickColor, size: fields["size"]?.numberValue ?? 16))
        case "button":
            guard let actionValue = fields["action"], let action = tapAction(actionValue, scope: scope, context: context) else {
                return nil
            }
            let title = SidekickWidgetBinding.interpolate(content.stringValue ?? "", scope: scope)
            let symbolName = fields["icon"]?.stringValue
            return .button(WidgetButtonPiece(title: title, symbolName: symbolName, colorHex: colorHex ?? context.tintHex, action: action))
        default:
            return nil
        }
    }

    private func isShown(fields: [String: JSONValue], scope: [String: JSONValue]) -> Bool {
        if let condition = fields["if"] {
            return SidekickWidgetBinding.isTruthy(resolvedValue(condition, scope: scope))
        }
        if let condition = fields["unless"] {
            return !SidekickWidgetBinding.isTruthy(resolvedValue(condition, scope: scope))
        }
        return true
    }

    private func filledChildren(_ content: JSONValue, scope: [String: JSONValue], context: FillContext) -> [WidgetPiece] {
        var children: [WidgetPiece] = []
        for child in content.arrayValue ?? [] {
            if let filledChild = filledPiece(child, scope: scope, context: context) {
                children.append(filledChild)
            }
        }
        return children
    }

    /// One row per item (each row sees its item as `$item`), in a column; the `empty` words when
    /// there are no items.
    private func filledList(content: JSONValue, fields: [String: JSONValue], scope: [String: JSONValue], context: FillContext) -> WidgetPiece? {
        let items = resolvedValue(content, scope: scope)?.arrayValue ?? []
        let limit = Int(fields["limit"]?.numberValue ?? 20)
        guard !items.isEmpty else {
            guard let emptyText = fields["empty"]?.stringValue else {
                return nil
            }
            return .text(WidgetTextPiece(text: emptyText, style: .body, colorHex: nil, isSecondary: true, lineLimit: 1))
        }
        guard let row = fields["row"] else {
            return nil
        }
        var rows: [WidgetPiece] = []
        for item in items.prefix(limit) {
            var rowScope = scope
            rowScope["item"] = item
            if let filledRow = filledPiece(row, scope: rowScope, context: context) {
                rows.append(filledRow)
            }
        }
        let spacing = fields["spacing"]?.numberValue ?? 6
        return .vstack(WidgetStackPiece(children: rows, spacing: spacing, alignment: .leading))
    }

    private func filledMeter(pieceName: String, content: JSONValue, scope: [String: JSONValue], colorHex: String?) -> WidgetPiece? {
        let valueSource = content["value"] ?? content["done"]
        guard let value = valueSource.flatMap({ source in resolvedValue(source, scope: scope)?.numberValue }),
              let total = content["of"].flatMap({ source in resolvedValue(source, scope: scope)?.numberValue }) else {
            return nil
        }
        let label = content["label"]?.stringValue.map { labelText in SidekickWidgetBinding.interpolate(labelText, scope: scope) }
        let meter = WidgetMeterPiece(value: value, total: total, colorHex: colorHex, label: label)
        switch pieceName {
        case "bar":
            return .bar(meter)
        case "ring":
            return .ring(meter)
        default:
            return .dots(meter)
        }
    }

    private func filledChart(content: JSONValue, scope: [String: JSONValue], colorHex: String?) -> WidgetPiece? {
        let elements = resolvedValue(content, scope: scope)?.arrayValue ?? []
        var values: [Double] = []
        for element in elements.prefix(31) {
            if let number = resolvedValue(element, scope: scope)?.numberValue {
                values.append(number)
            }
        }
        guard !values.isEmpty else {
            return nil
        }
        return .chart(WidgetChartPiece(values: values, colorHex: colorHex))
    }

    /// A binding's value, or the value itself when it is not a binding.
    private func resolvedValue(_ value: JSONValue, scope: [String: JSONValue]) -> JSONValue? {
        guard let text = value.stringValue, let path = SidekickWidgetBinding.wholePath(text) else {
            return value
        }
        return SidekickWidgetBinding.resolve(path, in: scope)
    }

    // MARK: Taps

    private func tapAction(_ actionValue: JSONValue, scope: [String: JSONValue], context: FillContext) -> WidgetTapAction? {
        if actionValue["open"] != nil {
            return WidgetTapAction.open(sidekickId: context.sidekickId)
        }
        if let itemBinding = actionValue["tick"] {
            return tickAction(itemBinding: itemBinding, scope: scope, context: context)
        }
        for kind in [WidgetTapKind.increment, .toggle, .set] {
            guard let keyText = actionValue[kind.rawValue]?.stringValue else {
                continue
            }
            let key = SidekickWidgetBinding.interpolate(keyText, scope: scope)
            guard !key.isEmpty, !SidekickWidgetDescription.isProtectedKey(key) else {
                return nil
            }
            let field = actionValue["field"]?.stringValue
            let amount = kind == .increment ? (actionValue["by"]?.numberValue ?? 1) : nil
            var valueJSON: String?
            if kind == .set, let setValue = actionValue["value"], let encodedValue = try? JSONEncoder().encode(setValue) {
                valueJSON = String(decoding: encodedValue, as: UTF8.self)
            }
            return WidgetTapAction(kind: kind, sidekickId: context.sidekickId, key: key, field: field, amount: amount,
                                   valueJSON: valueJSON, occurrence: nil)
        }
        return nil
    }

    /// Ticks the item a binding points at; nil when there is no such item (nothing left today).
    private func tickAction(itemBinding: JSONValue, scope: [String: JSONValue], context: FillContext) -> WidgetTapAction? {
        guard let item = resolvedValue(itemBinding, scope: scope), let key = item["key"]?.stringValue else {
            return nil
        }
        let occurrence = ReminderRecord.parseDate(item["at"])
        return WidgetTapAction(kind: .tick, sidekickId: context.sidekickId, key: key, field: nil, amount: nil,
                               valueJSON: nil, occurrence: occurrence)
    }

    // MARK: Colours

    /// "#RRGGBB" for a colour the description names; nil for primary, secondary and unknown.
    private func resolvedColorHex(_ color: JSONValue, scope: [String: JSONValue], context: FillContext) -> String? {
        let colorText = SidekickWidgetBinding.interpolate(color.stringValue ?? "", scope: scope)
        switch colorText {
        case "", "primary", "secondary":
            return nil
        case "accent":
            return context.tintHex
        default:
            return Self.hexForColorText(colorText)
        }
    }

    static func hexForTint(_ tint: JSONValue) -> String? {
        guard let tintText = tint.stringValue else {
            return nil
        }
        return hexForColorText(tintText)
    }

    /// A list colour name or "#RGB" / "#RRGGBB" as "#RRGGBB"; nil for anything else.
    static func hexForColorText(_ colorText: String) -> String? {
        let normalized = TodayReminderPlanner.normalizedColorHex(colorText)
        let isUnknown = normalized == TodayReminderPlanner.unknownListColorHex && colorText.lowercased() != "gray"
            && colorText.uppercased() != TodayReminderPlanner.unknownListColorHex
        return isUnknown ? nil : normalized
    }
}
