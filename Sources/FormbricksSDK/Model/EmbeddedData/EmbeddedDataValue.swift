import Foundation

/// A value a host app may attach to future responses with ``Formbricks/setEmbeddedData(_:)``.
///
/// Confined to the four scalars the Embedded Data ingest contract can store. A closed enum rather
/// than `Any` on purpose: the bag is serialized into the survey WebView's payload, so an
/// unrepresentable value would not be a dropped field but a `JSONSerialization` failure that takes
/// the whole survey down with it.
///
/// Supports literal syntax in dictionaries, so the common call reads as plain data:
///
/// ```swift
/// Formbricks.setEmbeddedData([
///     "plan": "pro",
///     "seats": 25,
///     "isTrial": false,
///     "screen": nil,        // removes the key
/// ])
/// ```
///
/// Dates serialize as ISO 8601, which is what the ingest contract accepts for a `date` field.
public enum EmbeddedDataValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)

    /// A `JSONSerialization`-safe representation, or `nil` for a value that cannot be serialized.
    ///
    /// The `nil` case is not defensive habit. `JSONSerialization` **throws** on a non-finite
    /// `Double`, and the payload it would have refused is the whole survey's props blob — so a
    /// single `.number(.nan)` would mean no survey rather than one missing field. The store rejects
    /// those at the door and logs; this is the second line of the same rule.
    var jsonValue: Any? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.isFinite ? value : nil
        case .bool(let value):
            return value
        case .date(let value):
            return ISO8601DateFormatter().string(from: value)
        }
    }
}

// MARK: - Literal conformances for ergonomic dictionary syntax

extension EmbeddedDataValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension EmbeddedDataValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension EmbeddedDataValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension EmbeddedDataValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}
