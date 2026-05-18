import Foundation

internal enum FormbricksWorkspace {

    /// Only `appUrl` is user-supplied. Returns nil if it's missing.
    internal static var baseApiUrl: String? {
        return Formbricks.appUrl
    }

    /// Returns the full survey‐script URL as a String
    static var surveyScriptUrlString: String? {
        guard let baseURLString = baseApiUrl,
            let baseURL = URL(string: baseURLString),
            baseURL.scheme == "https" || baseURL.scheme == "http"
        else {
            return nil
        }
        let surveyScriptURL = baseURL.appendingPathComponent("js").appendingPathComponent(
            "surveys.umd.cjs")
        return surveyScriptURL.absoluteString
    }

    /// Returns the workspace-state fetch URL path with a `{workspaceId}` placeholder.
    static var getWorkspaceStateRequestEndpoint: String {
        return ["api", "v2", "client", "{workspaceId}", "environment"].joined(separator: "/")
    }

    /// Returns the post-user URL path with a `{workspaceId}` placeholder.
    static var postUserRequestEndpoint: String {
        return ["api", "v2", "client", "{workspaceId}", "user"].joined(separator: "/")
    }
}
