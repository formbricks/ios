import Foundation

/// Represents a user attribute value that can be a string, number, or date.
///
/// Attribute types are determined by the Swift value type:
/// - String values → string attribute
/// - Number values → number attribute
/// - Date values → date attribute (converted to ISO string)
///
/// On first write to a new attribute, the type is set based on the value type.
/// On subsequent writes, the value must match the existing attribute type.
public enum AttributeValue: Codable, Equatable {
    case string(String)
    case number(Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                AttributeValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or Number for AttributeValue"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }

    /// The string representation of this attribute value, if it is a string.
    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// The numeric representation of this attribute value, if it is a number.
    public var numberValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    /// Creates an `AttributeValue` from a `String`.
    public static func from(_ value: String) -> AttributeValue {
        return .string(value)
    }

    /// Creates an `AttributeValue` from a `Double`.
    public static func from(_ value: Double) -> AttributeValue {
        return .number(value)
    }

    /// Creates an `AttributeValue` from an `Int`.
    public static func from(_ value: Int) -> AttributeValue {
        return .number(Double(value))
    }

    /// Creates an `AttributeValue` from a `Date`, converting it to an ISO 8601 string.
    /// The backend will detect the ISO 8601 format and treat it as a date type.
    public static func from(_ value: Date) -> AttributeValue {
        return .string(ISO8601DateFormatter().string(from: value))
    }
}
