import Foundation
import JavaScriptCore

/// One change a Sidekick tool asks for: a whole record to store, or a key to remove.
enum SidekickToolOp: Equatable, Sendable {
    case set(key: String, value: JSONValue)
    case delete(key: String)
}

/// What a tool's handler gave back. `changes` are applied through `RecordWriter.apply`; a refusal
/// changes nothing (jess router, founder 2026-10-21: "cannot act → nothing changed"). `text` is the
/// handler's short line (the reminder's or list's name), `at`/`allDay` the time it set, if any.
struct SidekickToolResult: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case changes([SidekickToolOp])
        case refused(reason: String)
    }

    let outcome: Outcome
    let text: String
    let at: String?
    let allDay: Bool?
}

enum SidekickToolsError: Error, Equatable {
    case scriptFailed(String)
    case noHandler(String)
    case handlerFailed(String)
    case badResult(String)
}

/// Runs one Sidekick's `tools.js` in its own JavaScriptCore context (jess router, founder
/// 2026-10-21). The page never loads it: the shell does, with the records it already holds, and
/// applies what a handler returns through `RecordWriter`. A handler is pure, `(input, records,
/// now) -> { ops, result }` or `{ refused, result }`, and the deploy gate (backend/scripts/
/// bundle-tools.mjs sidekickToolsProblems) has checked it has no network, store or code loading.
/// Everything crosses as JSON text, like `RecordSchemaEngine`.
@MainActor
final class SidekickToolsEngine {
    private let context: JSContext

    init(source: String) throws {
        guard let context = JSContext() else {
            throw SidekickToolsError.scriptFailed("no JavaScript context")
        }
        self.context = context
        var failure: String?
        context.exceptionHandler = { _, exception in
            failure = exception?.toString() ?? "unknown error"
        }
        context.evaluateScript(source)
        context.evaluateScript(Self.bridgeSource)
        if let failure {
            throw SidekickToolsError.scriptFailed(failure)
        }
        let hasTools = context.evaluateScript("midasHasTools()")?.toBool() ?? false
        if !hasTools {
            throw SidekickToolsError.scriptFailed("tools.js sets no MidasSidekickTools with context and handlers")
        }
        context.exceptionHandler = nil
    }

    // A handler's exception comes back as { midasError } so one bad call never breaks the context.
    private static let bridgeSource = """
    function midasHasTools() {
      return typeof MidasSidekickTools === 'object' && MidasSidekickTools !== null
        && typeof MidasSidekickTools.context === 'function'
        && typeof MidasSidekickTools.handlers === 'object' && MidasSidekickTools.handlers !== null;
    }
    function midasHandlerNames() {
      return JSON.stringify(Object.keys(MidasSidekickTools.handlers).sort());
    }
    function midasRunHandler(verb, inputText, recordsText, now) {
      var handler = MidasSidekickTools.handlers[verb];
      if (typeof handler !== 'function') {
        return JSON.stringify({ midasNoHandler: verb });
      }
      try {
        return JSON.stringify(handler(JSON.parse(inputText), JSON.parse(recordsText), now));
      } catch (error) {
        return JSON.stringify({ midasError: String(error && error.message ? error.message : error) });
      }
    }
    function midasContext(recordsText, now) {
      try {
        return JSON.stringify(MidasSidekickTools.context(JSON.parse(recordsText), now));
      } catch (error) {
        return JSON.stringify({ midasError: String(error && error.message ? error.message : error) });
      }
    }
    """

    /// The verbs tools.js has handlers for, sorted.
    func handlerNames() -> [String] {
        guard let reply = decoded(call("midasHandlerNames", arguments: [])), case .array(let names) = reply else {
            return []
        }
        var verbs: [String] = []
        for name in names {
            if case .string(let verb) = name {
                verbs.append(verb)
            }
        }
        return verbs
    }

    /// The small summary of the records the router's model sees (lists, item titles and times).
    func context(records: [LocalRecord], now: Date) throws -> JSONValue {
        let reply = decoded(call("midasContext", arguments: [encodedRecords(records), ReminderRecord.formatDate(now)]))
        guard let reply else {
            throw SidekickToolsError.badResult("context gave no JSON")
        }
        if case .string(let message)? = reply["midasError"] {
            throw SidekickToolsError.handlerFailed(message)
        }
        return reply
    }

    /// Runs the handler for `verb` (the part of the tool name after "<sidekickId>.").
    func run(verb: String, input: JSONValue, records: [LocalRecord], now: Date) throws -> SidekickToolResult {
        let arguments: [Any] = [verb, encoded(input), encodedRecords(records), ReminderRecord.formatDate(now)]
        guard let reply = decoded(call("midasRunHandler", arguments: arguments)) else {
            throw SidekickToolsError.badResult("\(verb) gave no JSON")
        }
        if case .string(let missingVerb)? = reply["midasNoHandler"] {
            throw SidekickToolsError.noHandler(missingVerb)
        }
        if case .string(let message)? = reply["midasError"] {
            throw SidekickToolsError.handlerFailed(message)
        }
        return try Self.result(from: reply, verb: verb)
    }

    // MARK: Reading a handler's reply

    static func result(from reply: JSONValue, verb: String) throws -> SidekickToolResult {
        let resultPart = reply["result"]
        guard case .string(let text)? = resultPart?["text"] else {
            throw SidekickToolsError.badResult("\(verb) gave no result.text")
        }
        var at: String?
        if case .string(let atText)? = resultPart?["at"] {
            at = atText
        }
        var allDay: Bool?
        if case .bool(let allDayFlag)? = resultPart?["allDay"] {
            allDay = allDayFlag
        }
        if case .string(let reason)? = reply["refused"] {
            return SidekickToolResult(outcome: .refused(reason: reason), text: text, at: at, allDay: allDay)
        }
        guard case .array(let opValues)? = reply["ops"] else {
            throw SidekickToolsError.badResult("\(verb) gave neither ops nor refused")
        }
        var ops: [SidekickToolOp] = []
        for opValue in opValues {
            ops.append(try op(from: opValue, verb: verb))
        }
        return SidekickToolResult(outcome: .changes(ops), text: text, at: at, allDay: allDay)
    }

    private static func op(from opValue: JSONValue, verb: String) throws -> SidekickToolOp {
        guard case .string(let key)? = opValue["key"], !key.isEmpty else {
            throw SidekickToolsError.badResult("\(verb) gave an op without a key")
        }
        switch opValue["op"] {
        case .string("set")?:
            guard let value = opValue["value"], value != .null else {
                throw SidekickToolsError.badResult("\(verb) set \(key) without a value")
            }
            return .set(key: key, value: value)
        case .string("delete")?:
            return .delete(key: key)
        default:
            throw SidekickToolsError.badResult("\(verb) gave an op that is neither set nor delete")
        }
    }

    // MARK: Crossing into JavaScript

    private func call(_ functionName: String, arguments: [Any]) -> JSValue? {
        guard let function = context.objectForKeyedSubscript(functionName) else {
            return nil
        }
        return function.call(withArguments: arguments)
    }

    private func encoded(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    /// The records as tools.js reads them: [{ key, value }].
    private func encodedRecords(_ records: [LocalRecord]) -> String {
        var entries: [JSONValue] = []
        for record in records {
            entries.append(.object(["key": .string(record.key), "value": record.value]))
        }
        return encoded(.array(entries))
    }

    private func decoded(_ result: JSValue?) -> JSONValue? {
        guard let result, !result.isNull, !result.isUndefined, let text = result.toString(), let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
