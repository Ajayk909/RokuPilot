import Foundation

/// A small, fully Codable JSON value. Used for Gemini requests/responses so we can
/// pass the model's content back untouched (including any thought signatures).
enum JSON: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSON])
    case array([JSON])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var arrayValue: [JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var objectValue: [String: JSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Compact text form, handy for logs and for showing tool results.
    var compactText: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let d = try? enc.encode(self) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral,
                ExpressibleByArrayLiteral, ExpressibleByBooleanLiteral,
                ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b }))
    }
    init(arrayLiteral elements: JSON...) { self = .array(elements) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
}
