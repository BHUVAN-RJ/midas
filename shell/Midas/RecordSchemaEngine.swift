import Foundation
import JavaScriptCore

/// The one record validator, run on the phone. Loads `shell/sdk/record-schema.js` and
/// `shell/sdk/shell-types.js`, the same files the Worker imports, into JavaScriptCore, so a page,
/// a native writer and the server check a record the same way (unified data plan, section 3:
/// one validator, not a Swift copy). Every call crosses into JavaScript as JSON text and comes
/// back as JSON text or a message.
///
/// Also loads `shell/sdk/native-types.js` when the app ships it: the record types of the Sidekicks
/// built into the shell (`make`, `make-inbox`; docs/briefs/make-contract.md section 2).
@MainActor
final class RecordSchemaEngine {
    enum LoadError: Error, Equatable {
        case scriptMissing(String)
        case scriptFailed(String)
    }

    static let validatorResourceName = "record-schema"
    static let shellTypesResourceName = "shell-types"
    static let nativeTypesResourceName = "native-types"

    private let context: JSContext
    /// The shell's own types (`widget:`, `request:`), as the script declares them.
    let shellTypes: JSONValue
    /// The built-in Sidekicks' types, by Sidekick id (`MidasNativeTypes`); empty when the app was
    /// built without native-types.js.
    let nativeTypes: [String: JSONValue]

    /// Loads the scripts from the app bundle. The shell cannot run without them, so a missing or
    /// broken script is an error the caller decides about (ShellServices stops the app).
    convenience init(bundle: Bundle = .main) throws {
        let validatorURL = bundle.url(forResource: Self.validatorResourceName, withExtension: "js")
        let shellTypesURL = bundle.url(forResource: Self.shellTypesResourceName, withExtension: "js")
        guard let validatorURL else {
            throw LoadError.scriptMissing("\(Self.validatorResourceName).js")
        }
        guard let shellTypesURL else {
            throw LoadError.scriptMissing("\(Self.shellTypesResourceName).js")
        }
        let validatorSource = try String(contentsOf: validatorURL, encoding: .utf8)
        let shellTypesSource = try String(contentsOf: shellTypesURL, encoding: .utf8)
        // Optional: until the server side of Make lands, the app may ship without it
        let nativeTypesURL = bundle.url(forResource: Self.nativeTypesResourceName, withExtension: "js")
        let nativeTypesSource = nativeTypesURL.flatMap(Self.readSource)
        try self.init(validatorSource: validatorSource, shellTypesSource: shellTypesSource, nativeTypesSource: nativeTypesSource)
    }

    private static func readSource(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    init(validatorSource: String, shellTypesSource: String, nativeTypesSource: String? = nil) throws {
        guard let context = JSContext() else {
            throw LoadError.scriptFailed("no JavaScript context")
        }
        self.context = context
        var failure: String?
        context.exceptionHandler = { _, exception in
            failure = exception?.toString() ?? "unknown error"
        }
        context.evaluateScript(validatorSource)
        context.evaluateScript(shellTypesSource)
        if let nativeTypesSource {
            context.evaluateScript(nativeTypesSource)
        }
        context.evaluateScript(Self.bridgeSource)
        if let failure {
            throw LoadError.scriptFailed(failure)
        }
        let shellTypesText = context.evaluateScript("JSON.stringify(MidasShellTypes)")?.toString() ?? ""
        guard let shellTypesData = shellTypesText.data(using: .utf8), let shellTypes = try? JSONDecoder().decode(JSONValue.self, from: shellTypesData) else {
            throw LoadError.scriptFailed("shell types are not JSON")
        }
        self.shellTypes = shellTypes
        let nativeTypesText = context.evaluateScript("JSON.stringify(typeof MidasNativeTypes === 'undefined' ? {} : MidasNativeTypes)")?.toString() ?? ""
        guard let nativeTypesData = nativeTypesText.data(using: .utf8), let nativeTypes = try? JSONDecoder().decode([String: JSONValue].self, from: nativeTypesData) else {
            throw LoadError.scriptFailed("native types are not JSON")
        }
        self.nativeTypes = nativeTypes
    }

    // Small functions that take and return JSON text, so Swift never builds JavaScript objects.
    private static let bridgeSource = """
    function midasParse(text) { return text === null || text === undefined ? null : JSON.parse(text); }
    function midasCheckRecord(typesText, key, valueText) {
      return MidasRecordSchema.checkRecord(midasParse(typesText), key, midasParse(valueText));
    }
    function midasStampType(typesText, key, valueText) {
      return JSON.stringify(MidasRecordSchema.stampType(midasParse(typesText), key, midasParse(valueText)));
    }
    function midasTypeName(typesText, key) {
      var type = MidasRecordSchema.typeForKey(midasParse(typesText), key);
      return type === null || typeof type.$type !== 'string' ? null : type.$type;
    }
    function midasMergePatch(targetText, patchText) {
      return JSON.stringify(MidasRecordSchema.mergePatch(midasParse(targetText), midasParse(patchText)));
    }
    function midasValidate(schemaText, valueText, typeName) {
      var schema = midasParse(schemaText);
      return MidasRecordSchema.validate(schema, midasParse(valueText), typeName, schema);
    }
    """

    /// Why the value cannot be stored under the key, or nil. `types` is a manifest's `types`
    /// block; nil means the Sidekick has no schemas yet and nothing is checked.
    func checkRecord(types: JSONValue?, key: String, value: JSONValue) -> String? {
        let result = call("midasCheckRecord", arguments: [encoded(types), key, encoded(value)])
        return messageOrNil(result)
    }

    /// The value with `$type` set from its key's type (unchanged when the key has no type).
    func stampType(types: JSONValue?, key: String, value: JSONValue) -> JSONValue {
        let result = call("midasStampType", arguments: [encoded(types), key, encoded(value)])
        return decoded(result) ?? value
    }

    /// The `$type` the key maps to, or nil.
    func typeName(types: JSONValue?, key: String) -> String? {
        let result = call("midasTypeName", arguments: [encoded(types), key])
        return messageOrNil(result)
    }

    /// JSON Merge Patch (RFC 7396).
    func mergePatch(target: JSONValue?, patch: JSONValue) -> JSONValue {
        let result = call("midasMergePatch", arguments: [encoded(target), encoded(patch)])
        return decoded(result) ?? patch
    }

    /// The first problem with a value against one schema, or nil.
    func validate(schema: JSONValue, value: JSONValue, typeName: String) -> String? {
        let result = call("midasValidate", arguments: [encoded(schema), encoded(value), typeName])
        return messageOrNil(result)
    }

    // MARK: Crossing into JavaScript

    private func call(_ functionName: String, arguments: [Any]) -> JSValue? {
        guard let function = context.objectForKeyedSubscript(functionName) else {
            return nil
        }
        return function.call(withArguments: arguments)
    }

    private func encoded(_ value: JSONValue?) -> Any {
        guard let value, let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else {
            return NSNull()
        }
        return text
    }

    private func decoded(_ result: JSValue?) -> JSONValue? {
        guard let result, !result.isNull, !result.isUndefined, let text = result.toString(), let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func messageOrNil(_ result: JSValue?) -> String? {
        guard let result, !result.isNull, !result.isUndefined else {
            return nil
        }
        return result.toString()
    }
}
