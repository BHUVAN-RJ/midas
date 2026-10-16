import Foundation

/// Any JSON value a Sidekick stores. Records are opaque to the shell except the reserved
/// `reminder:` prefix, which the notification engine reads.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else {
            let objectValue = try container.decode([String: JSONValue].self)
            self = .object(objectValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let boolValue):
            try container.encode(boolValue)
        case .number(let numberValue):
            try container.encode(numberValue)
        case .string(let stringValue):
            try container.encode(stringValue)
        case .array(let arrayValue):
            try container.encode(arrayValue)
        case .object(let objectValue):
            try container.encode(objectValue)
        }
    }

    subscript(fieldName: String) -> JSONValue? {
        guard case .object(let fields) = self else {
            return nil
        }
        return fields[fieldName]
    }

    var stringValue: String? {
        guard case .string(let text) = self else {
            return nil
        }
        return text
    }

    var numberValue: Double? {
        guard case .number(let number) = self else {
            return nil
        }
        return number
    }

    var boolValue: Bool? {
        guard case .bool(let flag) = self else {
            return nil
        }
        return flag
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let elements) = self else {
            return nil
        }
        return elements
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let fields) = self else {
            return nil
        }
        return fields
    }
}
