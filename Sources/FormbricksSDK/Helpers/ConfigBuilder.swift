import Foundation

/// The configuration object for the Formbricks SDK.
@objc(FormbricksConfig) public class FormbricksConfig: NSObject {
    let appUrl: String
    @objc public let workspaceId: String
    let userId: String?
    let attributes: [String: AttributeValue]?
    let logLevel: LogLevel
    /// Optional custom service, injected via Builder
    let customService: FormbricksServiceProtocol?
    /// True if this config was built using the deprecated `environmentId` parameter.
    let usedDeprecatedEnvironmentId: Bool
    /// How surveys render; nil leaves whatever `Formbricks.setAppearance` already set.
    let appearance: FormbricksAppearance?

    /// Backward-compatible alias for `workspaceId`.
    @available(*, deprecated, renamed: "workspaceId", message: "Use workspaceId instead. environmentId will be removed in a future version.")
    @objc public var environmentId: String { workspaceId }

    init(appUrl: String, workspaceId: String, userId: String?, attributes: [String: AttributeValue]?, logLevel: LogLevel, customService: FormbricksServiceProtocol?, usedDeprecatedEnvironmentId: Bool = false, appearance: FormbricksAppearance? = nil) {
            self.appUrl = appUrl
            self.workspaceId = workspaceId
            self.userId = userId
            self.attributes = attributes
            self.logLevel = logLevel
            self.customService = customService
            self.usedDeprecatedEnvironmentId = usedDeprecatedEnvironmentId
            self.appearance = appearance
    }

    /// The builder class for the FormbricksConfig object.
    @objc(FormbricksConfigBuilder) public class Builder: NSObject {
        var appUrl: String
        var workspaceId: String
        var userId: String?
        var attributes: [String: AttributeValue] = [:]
        var logLevel: LogLevel = .error
        /// Optional custom service, injected via Builder
        var customService: FormbricksServiceProtocol?
        var usedDeprecatedEnvironmentId: Bool = false
        var appearance: FormbricksAppearance?

        /// Initializes the builder with the workspace ID.
        @objc public init(appUrl: String, workspaceId: String) {
            self.appUrl = appUrl
            self.workspaceId = workspaceId
        }

        /// Initializes the builder with the environment ID.
        /// - Warning: `environmentId` is deprecated — use `init(appUrl:workspaceId:)` instead.
        @available(*, deprecated, renamed: "init(appUrl:workspaceId:)", message: "Use init(appUrl:workspaceId:) instead. environmentId will be removed in a future version.")
        @objc public init(appUrl: String, environmentId: String) {
            self.appUrl = appUrl
            self.workspaceId = environmentId
            self.usedDeprecatedEnvironmentId = true
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

        /// Sets how surveys render: `light`, `dark` or `system`.
        public func set(appearance: FormbricksAppearance) -> Builder {
            self.appearance = appearance
            return self
        }

        /// Sets how surveys render from a string: "light", "dark" or "system" (Obj-C compatible).
        /// An unknown value is ignored.
        @objc public func set(appearanceString: String) -> Builder {
            self.appearance = FormbricksAppearance(rawValue: appearanceString)
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
            return FormbricksConfig(appUrl: appUrl, workspaceId: workspaceId, userId: userId, attributes: attributes, logLevel: logLevel, customService: customService, usedDeprecatedEnvironmentId: usedDeprecatedEnvironmentId, appearance: appearance)
        }
    }
}
