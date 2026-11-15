import Foundation

/// Prefilled values for the playground's fields. The E2E journey passes them as launch environment
/// variables; run by hand, the fields start empty (app URL and workspace) or with the QA defaults.
struct LaunchConfiguration {
    var appUrl: String
    var workspaceId: String
    var userId: String
    var attributeKey: String
    var attributeValue: String
    var action: String

    /// Set up the SDK on launch, so the journey does not have to type the server's URL.
    var setsUpOnLaunch: Bool { !appUrl.isEmpty && !workspaceId.isEmpty }

    init(environment: [String: String]) {
        appUrl = environment["FORMBRICKS_APP_URL"] ?? ""
        workspaceId = environment["FORMBRICKS_WORKSPACE_ID"] ?? ""
        userId = environment["FORMBRICKS_USER_ID"] ?? ""
        attributeKey = environment["FORMBRICKS_ATTRIBUTE_KEY"] ?? "plan"
        attributeValue = environment["FORMBRICKS_ATTRIBUTE_VALUE"] ?? "pro"
        action = environment["FORMBRICKS_ACTION"] ?? "qa-action"
    }
}
