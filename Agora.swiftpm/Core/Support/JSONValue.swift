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
    /// "12,50", "1.234,56", "12.5" or "12" to a number like the backend does; nil when it is not one. For amounts
    /// stored on the server; what people type goes through `typed`.
    static func parse(_ raw: String) -> Double? {
        var text = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains(",") {
            // German format: dots group thousands, the comma is the decimal separator
            text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Double(text)
    }

    // sign, whole (digits, or groups of three after one to three digits), the group separator, the decimal point and
    // the cents (one or two digits, or "-" / "--" for none); ASCII digits only, like \d in JavaScript
    private static let typedPattern = try! NSRegularExpression(pattern: #"^([+-]?)([0-9]+|[0-9]{1,3}([.,])[0-9]{3}(?:\3[0-9]{3})*)?(?:([.,])([0-9]{1,2}|-{1,2})?)?$"#)
    private static let currency = try! NSRegularExpression(pattern: "€|euro?", options: .caseInsensitive)

    /// An amount as people type it, by the same rules as the web app (assets/finance.js) and Android: "1.234,56",
    /// "1,234.56", "1234,56", "1234.56", "1 234,56", "50 €", "50 EUR", "50,-", ",50". One or two digits after the
    /// last "." or "," are the cents, groups of three digits before it thousands. A lone "1.500" or "1,500" is 1500 in
    /// one language and 1.5 in the other: nil, it is not guessed (`parse` read it as 1,50 €).
    static func typed(_ raw: String?) -> Double? {
        let compact = String((raw ?? "").unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init))
        let text = currency.stringByReplacingMatches(in: compact, range: NSRange(compact.startIndex..., in: compact), withTemplate: "")
        guard let match = typedPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              text.contains(where: \.isASCIIDigit) else { return nil }
        func group(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
        let (sign, whole, separator, point, cents) = (group(1), group(2), group(3), group(4), group(5))
        // The cents need the other separator ("1.234.56"), and a single group of three could be cents ("1.500")
        if !separator.isEmpty && (point == separator || (point.isEmpty && whole.components(separatedBy: separator).count == 2)) {
            return nil
        }
        let digits = whole.filter(\.isASCIIDigit)
        let fraction = !cents.isEmpty && cents.allSatisfy(\.isASCIIDigit) ? cents : "0"
        return Double("\(sign)\(digits.isEmpty ? "0" : digits).\(fraction)")
    }

    /// Something was typed, but not an amount that can be read unambiguously.
    static func isUnclear(_ raw: String) -> Bool { !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && typed(raw) == nil }

    /// What an amount field keeps of the input: digits, "," and "." (like Android's AmountField).
    static func typeable(_ input: String) -> String { input.filter { $0.isASCIIDigit || $0 == "," || $0 == "." } }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
