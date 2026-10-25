import Foundation

// A `widget:<name>` record as a Sidekick writes it (founder, 2026-10-13, plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html; how to write one: docs/WIDGETS.md):
//
//     { name: "Meds today",
//       tint?: "#9CAF88",
//       sources?: { today: { records: "reminder:", when: "today", where?: { $type: "care.item", list: "medicine" } } },
//       small?: <piece>, medium?: <piece>, large?: <piece> }        // at least one size
//
// A piece is an object with one piece name: vstack, hstack, grid, list, spacer, divider, text,
// symbol, bar, ring, dots, chart, timer, tick, button. A piece with no name the shell knows is
// skipped (a newer Sidekick on an older shell). Strings starting with `$` are bindings to the
// sources ("$today.next.title"); text can hold bindings among words ("$today.open left").
// The checker below runs when the Sidekick writes the record, so a broken description is refused
// at once with the reason.

enum SidekickWidgetDescription {
    static let sizeNames = ["small", "medium", "large"]
    static let pieceNames: Set<String> = [
        "vstack", "hstack", "grid", "list", "spacer", "divider", "text", "symbol", "bar", "ring", "dots",
        "chart", "timer", "tick", "button",
    ]
    static let actionNames: Set<String> = ["open", "tick", "increment", "toggle", "set"]
    static let textStyleNames: Set<String> = ["title", "headline", "body", "caption", "number"]
    static let timerStyleNames: Set<String> = ["countdown", "relative", "time"]
    static let alignmentNames: Set<String> = ["leading", "center", "trailing", "top", "bottom"]
    /// Colour names beside the list colours: the primary text colour, the grey for less important
    /// text, and the description's tint.
    static let extraColorNames: Set<String> = ["primary", "secondary", "accent"]

    /// Record prefixes a tap may never write: other shell contracts. Ticks on `reminder:` go
    /// through `tick`, which writes them as the notification's Done does.
    static let protectedPrefixes = ["widget:", "request:", "reminder:"]

    static let maximumPieces = 150
    static let maximumDepth = 12
    static let maximumChildren = 40
    static let maximumSources = 8
    static let maximumTextLength = 200
    static let maximumNameLength = 40

    /// Why the description cannot be used; nil when it can.
    static func validationError(_ value: JSONValue) -> String? {
        guard case .object(let fields) = value else {
            return "widget must be an object"
        }
        guard let name = fields["name"]?.stringValue, !name.isEmpty, name.count <= maximumNameLength else {
            return "widget needs a name of 1 to \(maximumNameLength) characters"
        }
        if let tint = fields["tint"], colorError(tint) != nil {
            return "tint is not a colour"
        }
        if let sources = fields["sources"], let sourcesError = sourcesValidationError(sources) {
            return sourcesError
        }
        var sizeCount = 0
        var pieceCounter = PieceCounter()
        for sizeName in sizeNames {
            guard let sizePiece = fields[sizeName] else {
                continue
            }
            sizeCount += 1
            if let pieceError = pieceValidationError(sizePiece, depth: 0, insideList: false, counter: &pieceCounter) {
                return "\(sizeName): \(pieceError)"
            }
        }
        guard sizeCount > 0 else {
            return "widget needs small, medium or large"
        }
        return nil
    }

    // MARK: Sources

    private static func sourcesValidationError(_ sources: JSONValue) -> String? {
        guard case .object(let sourcesById) = sources else {
            return "sources must be an object"
        }
        guard sourcesById.count <= maximumSources else {
            return "at most \(maximumSources) sources"
        }
        for (sourceId, source) in sourcesById {
            guard isBindingName(sourceId), sourceId != "item" else {
                return "source name \(sourceId) must be letters, digits or _ and not item"
            }
            if let sourceError = sourceValidationError(source) {
                return "source \(sourceId): \(sourceError)"
            }
        }
        return nil
    }

    private static func sourceValidationError(_ source: JSONValue) -> String? {
        guard case .object(let fields) = source else {
            return "must be an object"
        }
        if let recordKey = fields["record"] {
            guard let key = recordKey.stringValue, !key.isEmpty else {
                return "record must be a key"
            }
            return nil
        }
        guard let prefix = fields["records"]?.stringValue else {
            return "needs records (a key prefix) or record (a key)"
        }
        if let streak = fields["streak"] {
            guard fields["when"] == nil else {
                return "streak and when cannot be used together"
            }
            if let streakError = streakValidationError(streak) {
                return streakError
            }
        }
        if let when = fields["when"] {
            guard let whenName = when.stringValue, whenName == "today" || whenName == "upcoming" else {
                return "when must be today or upcoming"
            }
            guard prefix == ReminderRecord.keyPrefix else {
                return "when works with records: \"reminder:\" only"
            }
        }
        if let whereValue = fields["where"] {
            guard case .object = whereValue else {
                return "where must be an object of field values"
            }
        }
        if let sumField = fields["sum"], sumField.stringValue == nil {
            return "sum must be a field name"
        }
        if let limit = fields["limit"], !isWholeNumber(limit, from: 1, through: 50) {
            return "limit must be 1 to 50"
        }
        return nil
    }

    /// `streak: { field, goal, dayGoalField? }` (hydration plan W3): records keyed by day
    /// (`water:2026-10-25`), `field` against `goal` (a number or a binding).
    private static func streakValidationError(_ streak: JSONValue) -> String? {
        guard case .object(let streakFields) = streak else {
            return "streak must be { field, goal }"
        }
        guard let field = streakFields["field"]?.stringValue, !field.isEmpty else {
            return "streak needs field"
        }
        guard let goal = streakFields["goal"], isNumberOrBinding(goal) else {
            return "streak goal must be a number or a binding"
        }
        if let dayGoalField = streakFields["dayGoalField"] {
            guard let dayGoalFieldName = dayGoalField.stringValue, !dayGoalFieldName.isEmpty else {
                return "streak dayGoalField must be a field name"
            }
        }
        return nil
    }

    // MARK: Pieces

    struct PieceCounter {
        var count = 0
    }

    private static func pieceValidationError(_ piece: JSONValue, depth: Int, insideList: Bool, counter: inout PieceCounter) -> String? {
        guard depth <= maximumDepth else {
            return "pieces nested deeper than \(maximumDepth)"
        }
        guard case .object(let fields) = piece else {
            return "a piece must be an object"
        }
        counter.count += 1
        guard counter.count <= maximumPieces else {
            return "more than \(maximumPieces) pieces"
        }
        let knownNames = fields.keys.filter(pieceNames.contains)
        guard knownNames.count <= 1 else {
            return "a piece has more than one kind: \(knownNames.sorted().joined(separator: ", "))"
        }
        if let condition = fields["if"] ?? fields["unless"], !isBinding(condition) {
            return "if and unless take a binding"
        }
        if let color = fields["color"], let error = colorError(color) {
            return error
        }
        // A piece the shell does not know is skipped when drawn.
        guard let pieceName = knownNames.first, let content = fields[pieceName] else {
            return nil
        }
        switch pieceName {
        case "vstack", "hstack", "grid":
            return stackValidationError(pieceName: pieceName, content: content, fields: fields, depth: depth, insideList: insideList, counter: &counter)
        case "list":
            return listValidationError(content: content, fields: fields, depth: depth, insideList: insideList, counter: &counter)
        case "spacer", "divider":
            return nil
        case "text":
            return textValidationError(content: content, fields: fields)
        case "symbol":
            guard let symbolName = content.stringValue, !symbolName.isEmpty else {
                return "symbol takes an SF Symbol name"
            }
            return nil
        case "bar", "ring", "dots":
            return meterValidationError(pieceName: pieceName, content: content)
        case "chart":
            return chartValidationError(content: content)
        case "timer":
            return timerValidationError(content: content, fields: fields)
        case "tick":
            guard isBinding(content) else {
                return "tick takes an item binding, like $item"
            }
            return nil
        case "button":
            return buttonValidationError(content: content, fields: fields)
        default:
            return nil
        }
    }

    private static func stackValidationError(pieceName: String, content: JSONValue, fields: [String: JSONValue], depth: Int,
                                             insideList: Bool, counter: inout PieceCounter) -> String? {
        guard let children = content.arrayValue else {
            return "\(pieceName) takes a list of pieces"
        }
        guard children.count <= maximumChildren else {
            return "\(pieceName) holds more than \(maximumChildren) pieces"
        }
        if pieceName == "grid" {
            guard let columns = fields["columns"], isWholeNumber(columns, from: 1, through: 8) else {
                return "grid needs columns, 1 to 8"
            }
        }
        if let spacing = fields["spacing"], !isNumber(spacing, from: 0, through: 40) {
            return "spacing must be 0 to 40"
        }
        if let alignment = fields["align"] {
            guard let alignmentName = alignment.stringValue, alignmentNames.contains(alignmentName) else {
                return "align must be leading, center, trailing, top or bottom"
            }
        }
        for child in children {
            if let childError = pieceValidationError(child, depth: depth + 1, insideList: insideList, counter: &counter) {
                return childError
            }
        }
        return nil
    }

    private static func listValidationError(content: JSONValue, fields: [String: JSONValue], depth: Int, insideList: Bool,
                                            counter: inout PieceCounter) -> String? {
        guard !insideList else {
            return "a list cannot hold another list"
        }
        guard isBinding(content) else {
            return "list takes a binding to items, like $today.items"
        }
        guard let row = fields["row"] else {
            return "list needs a row piece"
        }
        if let limit = fields["limit"], !isWholeNumber(limit, from: 1, through: 20) {
            return "limit must be 1 to 20"
        }
        if let empty = fields["empty"], empty.stringValue == nil {
            return "empty takes words"
        }
        if let spacing = fields["spacing"], !isNumber(spacing, from: 0, through: 40) {
            return "spacing must be 0 to 40"
        }
        return pieceValidationError(row, depth: depth + 1, insideList: true, counter: &counter)
    }

    private static func textValidationError(content: JSONValue, fields: [String: JSONValue]) -> String? {
        guard let text = content.stringValue, text.count <= maximumTextLength else {
            return "text takes words, up to \(maximumTextLength) characters"
        }
        if let style = fields["style"] {
            guard let styleName = style.stringValue, textStyleNames.contains(styleName) else {
                return "style must be title, headline, body, caption or number"
            }
        }
        if let lines = fields["lines"], !isWholeNumber(lines, from: 1, through: 6) {
            return "lines must be 1 to 6"
        }
        if let format = fields["format"] {
            guard let formatName = format.stringValue, WidgetUnitFormat(rawValue: formatName) != nil else {
                return "format must be ml, l or oz"
            }
        }
        return nil
    }

    private static func meterValidationError(pieceName: String, content: JSONValue) -> String? {
        guard case .object(let meterFields) = content else {
            return "\(pieceName) takes { value, of }"
        }
        guard let value = meterFields["value"] ?? meterFields["done"], isNumberOrBinding(value) else {
            return "\(pieceName) needs value: a number or a binding"
        }
        guard let total = meterFields["of"], isNumberOrBinding(total) else {
            return "\(pieceName) needs of: a number or a binding"
        }
        if let label = meterFields["label"], label.stringValue == nil {
            return "label takes words"
        }
        return nil
    }

    private static func chartValidationError(content: JSONValue) -> String? {
        if isBinding(content) {
            return nil
        }
        guard let values = content.arrayValue, values.count <= 31 else {
            return "chart takes up to 31 numbers or a binding"
        }
        for value in values where !isNumberOrBinding(value) {
            return "chart takes numbers"
        }
        return nil
    }

    private static func timerValidationError(content: JSONValue, fields: [String: JSONValue]) -> String? {
        let isDate = ReminderRecord.parseDate(content) != nil
        guard isBinding(content) || isDate else {
            return "timer takes a date or a binding to one"
        }
        if let style = fields["style"] {
            guard let styleName = style.stringValue, timerStyleNames.contains(styleName) else {
                return "timer style must be countdown, relative or time"
            }
        }
        return nil
    }

    private static func buttonValidationError(content: JSONValue, fields: [String: JSONValue]) -> String? {
        guard let title = content.stringValue, !title.isEmpty, title.count <= 30 else {
            return "button takes a title of 1 to 30 characters"
        }
        if let icon = fields["icon"], icon.stringValue == nil {
            return "icon takes an SF Symbol name"
        }
        guard let action = fields["action"] else {
            return "button needs an action"
        }
        return actionValidationError(action)
    }

    static func actionValidationError(_ action: JSONValue) -> String? {
        guard case .object(let fields) = action else {
            return "action must be an object"
        }
        let actionKinds = fields.keys.filter(actionNames.contains)
        guard actionKinds.count == 1, let actionName = actionKinds.first, let target = fields[actionName] else {
            return "action needs one of open, tick, increment, toggle, set"
        }
        switch actionName {
        case "open":
            return nil
        case "tick":
            guard isBinding(target) else {
                return "tick takes an item binding, like $today.next"
            }
            return nil
        default:
            guard let key = target.stringValue, !key.isEmpty else {
                return "\(actionName) takes a record key"
            }
            if isProtectedKey(key) {
                return "\(actionName) cannot write \(key)"
            }
            guard let field = fields["field"]?.stringValue, !field.isEmpty else {
                return "\(actionName) needs field"
            }
            if actionName == "increment", let step = fields["by"], step.numberValue == nil {
                return "by must be a number"
            }
            if actionName == "set" && fields["value"] == nil {
                return "set needs value"
            }
            return nil
        }
    }

    // MARK: Small checks

    static func isProtectedKey(_ key: String) -> Bool {
        for protectedPrefix in protectedPrefixes where key.hasPrefix(protectedPrefix) {
            return true
        }
        return false
    }

    /// Letters, digits and _, not starting with a digit.
    static func isBindingName(_ name: String) -> Bool {
        guard let firstCharacter = name.first, !firstCharacter.isNumber else {
            return false
        }
        for character in name where !(character.isLetter || character.isNumber || character == "_") {
            return false
        }
        return true
    }

    /// A whole string that is one binding: "$today.next.title".
    static func isBinding(_ value: JSONValue) -> Bool {
        guard let text = value.stringValue else {
            return false
        }
        return SidekickWidgetBinding.wholePath(text) != nil
    }

    private static func isNumberOrBinding(_ value: JSONValue) -> Bool {
        return value.numberValue != nil || isBinding(value)
    }

    private static func isNumber(_ value: JSONValue, from lowest: Double, through highest: Double) -> Bool {
        guard let number = value.numberValue else {
            return false
        }
        return number >= lowest && number <= highest
    }

    private static func isWholeNumber(_ value: JSONValue, from lowest: Double, through highest: Double) -> Bool {
        guard let number = value.numberValue, number.rounded() == number else {
            return false
        }
        return number >= lowest && number <= highest
    }

    /// Nil for a colour the shell can draw: a list colour name, primary, secondary, accent, "#RGB",
    /// "#RRGGBB", or a binding (checked when filled).
    static func colorError(_ color: JSONValue) -> String? {
        guard let colorText = color.stringValue else {
            return "color must be a name or #RRGGBB"
        }
        if isBinding(color) || extraColorNames.contains(colorText) {
            return nil
        }
        if TodayReminderPlanner.listColorHexByName[colorText.lowercased()] != nil {
            return nil
        }
        let digits = colorText.dropFirst()
        let isHex = colorText.hasPrefix("#") && (digits.count == 3 || digits.count == 6) && digits.allSatisfy(\.isHexDigit)
        guard isHex else {
            return "color \(colorText) is not a colour name or #RRGGBB"
        }
        return nil
    }
}

/// A text's `format` (hydration plan W2, founder 2026-10-25): its number bindings are amounts in
/// millilitres, shown in the unit the person picked. Written the same way on every phone
/// (en_US digits), as the rest of the widget's numbers.
enum WidgetUnitFormat: String, Sendable {
    case ml
    case l
    case oz

    /// Millilitres in one US fluid ounce.
    static let millilitresPerOunce = 29.5735295625

    /// 1250 → "1,250 ml", "1.25 L" (up to two decimals, no trailing zeros), "42 oz" (whole).
    func text(millilitres: Double) -> String {
        switch self {
        case .ml:
            return Self.numberText(millilitres.rounded(), fractionDigits: 0) + " ml"
        case .l:
            return Self.numberText(millilitres / 1000, fractionDigits: 2) + " L"
        case .oz:
            return Self.numberText((millilitres / Self.millilitresPerOunce).rounded(), fractionDigits: 0) + " oz"
        }
    }

    private static func numberText(_ number: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}

/// `$name.field.field` paths inside strings.
enum SidekickWidgetBinding {
    /// The path of a string that is exactly one binding ("$today.next" → ["today", "next"]); nil
    /// otherwise.
    static func wholePath(_ text: String) -> [String]? {
        guard text.hasPrefix("$") else {
            return nil
        }
        let path = String(text.dropFirst())
        let components = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let firstComponent = components.first, SidekickWidgetDescription.isBindingName(firstComponent) else {
            return nil
        }
        for component in components where component.isEmpty || !isPathComponent(component) {
            return nil
        }
        return components
    }

    private static func isPathComponent(_ component: String) -> Bool {
        for character in component where !(character.isLetter || character.isNumber || character == "_") {
            return false
        }
        return true
    }

    /// Each binding in running text, with where it sits. A binding ends at the first character that
    /// is not a letter, digit, _ or a dot followed by one of those ("$today.open." ends before the
    /// last dot).
    static func bindings(in text: String) -> [(range: Range<String.Index>, path: [String])] {
        var found: [(range: Range<String.Index>, path: [String])] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "$" else {
                index = text.index(after: index)
                continue
            }
            let pathStart = text.index(after: index)
            var pathEnd = pathStart
            while pathEnd < text.endIndex {
                let character = text[pathEnd]
                if character.isLetter || character.isNumber || character == "_" {
                    pathEnd = text.index(after: pathEnd)
                    continue
                }
                let nextIndex = text.index(after: pathEnd)
                let dotStartsComponent = character == "." && nextIndex < text.endIndex && isWordCharacter(text[nextIndex])
                guard dotStartsComponent else {
                    break
                }
                pathEnd = nextIndex
            }
            let pathText = String(text[pathStart..<pathEnd])
            if let path = wholePath("$" + pathText) {
                found.append((range: index..<pathEnd, path: path))
            }
            index = pathEnd > pathStart ? pathEnd : pathStart
        }
        return found
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        return character.isLetter || character.isNumber || character == "_"
    }

    /// The value at a path: a source or `item`, then fields of objects, positions in arrays, and
    /// `count` of an array.
    static func resolve(_ path: [String], in scope: [String: JSONValue]) -> JSONValue? {
        guard let firstComponent = path.first, var current = scope[firstComponent] else {
            return nil
        }
        for component in path.dropFirst() {
            switch current {
            case .object(let fields):
                guard let fieldValue = fields[component] else {
                    return nil
                }
                current = fieldValue
            case .array(let elements):
                if component == "count" {
                    current = .number(Double(elements.count))
                    continue
                }
                guard let position = Int(component), elements.indices.contains(position) else {
                    return nil
                }
                current = elements[position]
            default:
                return nil
            }
        }
        return current
    }

    /// Text for a value among words: strings as they are, whole numbers without decimals, other
    /// numbers to one decimal, nothing for null, true/false or objects.
    static func displayText(_ value: JSONValue?) -> String {
        guard let value else {
            return ""
        }
        switch value {
        case .string(let text):
            return text
        case .number(let number):
            if number.rounded() == number && abs(number) < 1e15 {
                return String(Int64(number))
            }
            return String(format: "%.1f", number)
        default:
            return ""
        }
    }

    /// Replaces every binding in running text with its value. With a unit format, numbers are
    /// read as millilitres and shown in that unit ("1,250 ml", "1.25 L", "42 oz").
    static func interpolate(_ text: String, scope: [String: JSONValue], unitFormat: WidgetUnitFormat? = nil) -> String {
        let foundBindings = bindings(in: text)
        guard !foundBindings.isEmpty else {
            return text
        }
        var result = ""
        var cursor = text.startIndex
        for foundBinding in foundBindings {
            result += text[cursor..<foundBinding.range.lowerBound]
            let value = resolve(foundBinding.path, in: scope)
            if let unitFormat, let millilitres = value?.numberValue {
                result += unitFormat.text(millilitres: millilitres)
            } else {
                result += displayText(value)
            }
            cursor = foundBinding.range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// Whether a value counts as present for `if`: not null, false, 0, "" or an empty list.
    static func isTruthy(_ value: JSONValue?) -> Bool {
        guard let value else {
            return false
        }
        switch value {
        case .null:
            return false
        case .bool(let flag):
            return flag
        case .number(let number):
            return number != 0
        case .string(let text):
            return !text.isEmpty
        case .array(let elements):
            return !elements.isEmpty
        case .object:
            return true
        }
    }
}
