import Foundation

/// Represents a user attribute value that can be a string, number, or date.
///
/// Attribute types are determined by the Swift value type:
/// - String values -> string attribute
/// - Number values -> number attribute
/// - Date values -> date attribute (converted to ISO string)
///
/// On first write to a new attribute, the type is set based on the value type.
/// On subsequent writes, the value must match the existing attribute type.
///
/// Supports literal syntax in dictionaries:
/// ```swift
/// let attributes: [String: AttributeValue] = [
///     "name": "John",
///     "age": 30,
///     "score": 9.5
/// ]
/// ```
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
}

// MARK: - Literal conformances for ergonomic dictionary syntax

extension AttributeValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AttributeValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension AttributeValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}
