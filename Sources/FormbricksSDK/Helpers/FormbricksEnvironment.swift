import Foundation

internal enum FormbricksEnvironment {

  /// Only `appUrl` is user-supplied. Returns nil if it's missing.
  internal static var baseApiUrl: String? {
    return Formbricks.appUrl
  }

  /// Returns the full survey‐script URL as a String
  static var surveyScriptUrlString: String? {
    guard let baseURLString = baseApiUrl,
          let baseURL = URL(string: baseURLString),
          baseURL.scheme == "https" || baseURL.scheme == "http" else {
      return nil
    }
    let surveyScriptURL = baseURL.appendingPathComponent("js").appendingPathComponent("surveys.umd.cjs")
    return surveyScriptURL.absoluteString
  }

  /// Returns the full environment‐fetch URL as a String for the given ID
  static var getEnvironmentRequestEndpoint: String {
    return ["api", "v2", "client", "{environmentId}", "environment"].joined(separator: "/")
  }

  /// Returns the full post-user URL as a String for the given ID
  static var postUserRequestEndpoint: String {
    return ["api", "v2", "client", "{environmentId}", "user"].joined(separator: "/")
  }
}
