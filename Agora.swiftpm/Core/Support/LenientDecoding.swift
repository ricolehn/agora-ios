import Foundation

/// Any string key, so models can decode with plain string literals: `c.string("id")`.
struct AnyKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Tolerant reading like the Android client (ignore unknown keys, coerce wrong or missing values to defaults):
/// the backend mixes legacy records where ids are numbers, amounts are German strings or fields are null.
extension KeyedDecodingContainer where Key == AnyKey {
    private func json(_ key: String) -> JSONValue? {
        guard let value = try? decodeIfPresent(JSONValue.self, forKey: AnyKey(key)) else { return nil }
        return value.isNull ? nil : value
    }

    func string(_ key: String, _ fallback: String = "") -> String { json(key)?.text ?? fallback }

    func optionalString(_ key: String) -> String? { json(key)?.text }

    func double(_ key: String, _ fallback: Double = 0) -> Double { json(key)?.amount ?? fallback }

    func int(_ key: String, _ fallback: Int = 0) -> Int {
        guard let value = json(key) else { return fallback }
        if case .number(let number) = value, number.isFinite { return Int(number) }
        if let text = value.text, let number = Double(text), number.isFinite { return Int(number) }
        return fallback
    }

    func int64(_ key: String, _ fallback: Int64 = 0) -> Int64 {
        guard let value = json(key) else { return fallback }
        if case .number(let number) = value, number.isFinite { return Int64(number) }
        if let text = value.text, let number = Double(text), number.isFinite { return Int64(number) }
        return fallback
    }

    func bool(_ key: String, _ fallback: Bool = false) -> Bool { json(key)?.boolValue ?? fallback }

    func strings(_ key: String) -> [String] { json(key)?.arrayValue?.compactMap(\.text) ?? [] }

    func object(_ key: String) -> [String: JSONValue] { json(key)?.objectValue ?? [:] }

    func raw(_ key: String) -> JSONValue? { json(key) }

    /// Nested model; a broken value counts as missing.
    func model<T: Decodable>(_ key: String) -> T? { try? decodeIfPresent(T.self, forKey: AnyKey(key)) }

    /// List of models; broken entries are skipped instead of failing the whole list.
    func models<T: Decodable>(_ key: String) -> [T] {
        guard let lossy = try? decodeIfPresent(LossyList<T>.self, forKey: AnyKey(key)) else { return [] }
        return lossy.items
    }
}

/// Decodes a JSON array, skipping elements that fail to decode.
struct LossyList<T: Decodable>: Decodable {
    let items: [T]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [T] = []
        while !container.isAtEnd {
            if let item = try? container.decode(T.self) {
                items.append(item)
            } else {
                _ = try? container.decode(JSONValue.self)
            }
        }
        self.items = items
    }
}

/// `/api/db` returns collections as objects keyed by id (Firebase style); some are arrays.
struct KeyedCollection<T: Decodable>: Decodable {
    let items: [T]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            items = []
        } else if let list = try? container.decode(LossyList<T>.self) {
            items = list.items
        } else if let map = try? container.decode([String: JSONValue].self) {
            let data = map.keys.sorted().compactMap { key -> Data? in
                guard let value = map[key], !value.isNull else { return nil }
                return try? JSONEncoder().encode(value)
            }
            items = data.compactMap { try? JSONDecoder().decode(T.self, from: $0) }
        } else {
            items = []
        }
    }
}
