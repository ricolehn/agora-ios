import Foundation

/// Untyped JSON, used where the app reads, changes and writes back whole database records (people, requests,
/// donations) and must keep fields it does not know.
enum JSONValue: Codable, Hashable, Sendable {
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
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers go out without ".0" (ids and timestamps are compared as text by the web client)
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 { try container.encode(Int64(value)) } else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        get { if case .object(let object) = self { return object[key] } else { return nil } }
        set {
            guard case .object(var object) = self else { return }
            object[key] = newValue
            self = .object(object)
        }
    }

    var objectValue: [String: JSONValue]? { if case .object(let object) = self { return object } else { return nil } }

    var arrayValue: [JSONValue]? { if case .array(let array) = self { return array } else { return nil } }

    /// Text of a primitive (numbers without trailing ".0"), nil for null, arrays and objects.
    var text: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value): return value == "true" ? true : value == "false" ? false : nil
        default: return nil
        }
    }

    /// Amounts: numbers or (legacy) German decimal strings like "12,50".
    var amount: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Amount.parse(value)
        default: return nil
        }
    }

    var isNull: Bool { if case .null = self { return true } else { return false } }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last })) }
    init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    static func of(_ value: String?) -> JSONValue { value.map { .string($0) } ?? .null }
    static func of(_ value: Double) -> JSONValue { .number(value) }
    static func of(_ value: Int) -> JSONValue { .number(Double(value)) }
    static func of(_ value: Bool) -> JSONValue { .bool(value) }
    static func of(_ values: [String]) -> JSONValue { .array(values.map { .string($0) }) }
}

enum Amount {
    /// "12,50", "1.234,56", "12.5" or "12" to a number like the backend does; nil when it is not one.
    static func parse(_ raw: String) -> Double? {
        var text = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains(",") {
            // German format: dots group thousands, the comma is the decimal separator
            text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Double(text)
    }
}
