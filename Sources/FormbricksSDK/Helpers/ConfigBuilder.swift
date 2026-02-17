import Foundation

/// The configuration object for the Formbricks SDK.
@objc(FormbricksConfig) public class FormbricksConfig: NSObject {
    let appUrl: String
    let environmentId: String
    let userId: String?
    let attributes: [String: AttributeValue]?
    let logLevel: LogLevel
    /// Optional custom service, injected via Builder
    let customService: FormbricksServiceProtocol?
    
    init(appUrl: String, environmentId: String, userId: String?, attributes: [String: AttributeValue]?, logLevel: LogLevel, customService: FormbricksServiceProtocol?) {
            self.appUrl = appUrl
            self.environmentId = environmentId
            self.userId = userId
            self.attributes = attributes
            self.logLevel = logLevel
            self.customService = customService
    }
    
    /// The builder class for the FormbricksConfig object.
    @objc(FormbricksConfigBuilder) public class Builder: NSObject {
        var appUrl: String
        var environmentId: String
        var userId: String?
        var attributes: [String: AttributeValue] = [:]
        var logLevel: LogLevel = .error
        /// Optional custom service, injected via Builder
        var customService: FormbricksServiceProtocol?
        
        @objc public init(appUrl: String, environmentId: String) {
            self.appUrl = appUrl
            self.environmentId = environmentId
        }
        
        /// Sets the user id for the Builder object.
        @objc public func set(userId: String) -> Builder {
            self.userId = userId
            return self
        }
        
        /// Sets the attributes for the Builder object.
        ///
        /// Thanks to `ExpressibleByStringLiteral`, `ExpressibleByIntegerLiteral`,
        /// and `ExpressibleByFloatLiteral` conformances on `AttributeValue`,
        /// you can use literal syntax:
        /// ```swift
        /// .set(attributes: ["name": "John", "age": 30])
        /// ```
        public func set(attributes: [String: AttributeValue]) -> Builder {
            self.attributes = attributes
            return self
        }

        /// Sets the attributes for the Builder object using string values (Obj-C compatible).
        @objc public func set(stringAttributes: [String: String]) -> Builder {
            self.attributes = stringAttributes.mapValues { .string($0) }
            return self
        }
        
        /// Adds a string attribute to the Builder object (Obj-C compatible).
        @objc public func add(attribute: String, forKey key: String) -> Builder {
            self.attributes[key] = .string(attribute)
            return self
        }
        
        /// Sets the log level for the Builder object.
        @objc public func setLogLevel(_ logLevel: LogLevel) -> Builder {
            self.logLevel = logLevel
            return self
        }
        
        func service(_ svc: FormbricksServiceProtocol) -> FormbricksConfig.Builder {
            self.customService = svc
            return self
        }
        
        /// Builds the FormbricksConfig object from the Builder object.
        @objc public func build() -> FormbricksConfig {
            return FormbricksConfig(appUrl: appUrl, environmentId: environmentId, userId: userId, attributes: attributes, logLevel: logLevel, customService: customService)
        }
    }
}
