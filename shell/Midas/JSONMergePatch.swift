import Foundation

/// JSON Merge Patch (RFC 7396) on `JSONValue`, the shape `store.update` and every native writer
/// use to change a record (plan section 5: every writer changes the same fields the same way).
/// A field set to null is removed, an object field is merged, every other field is replaced.
/// Mirrors `mergePatch` in shell/sdk/record-schema.js; `RecordSchemaEngineTests` keeps the two
/// in step by running both on the same cases.
enum JSONMergePatch {
    static func apply(_ patch: JSONValue, to target: JSONValue?) -> JSONValue {
        guard case .object(let patchFields) = patch else {
            return patch
        }
        var resultFields: [String: JSONValue] = [:]
        if case .object(let targetFields)? = target {
            resultFields = targetFields
        }
        for (fieldName, patchValue) in patchFields {
            if patchValue == .null {
                resultFields.removeValue(forKey: fieldName)
            } else {
                resultFields[fieldName] = apply(patchValue, to: resultFields[fieldName])
            }
        }
        return .object(resultFields)
    }
}
