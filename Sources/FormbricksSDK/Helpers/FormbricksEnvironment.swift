import Foundation

internal enum FormbricksEnvironment {

  /// Only `appUrl` is user-supplied. Crash early if it's missing.
  fileprivate static var baseApiUrl: String {
    guard let url = Formbricks.appUrl else {
      fatalError("Formbricks.setup must be called before using the SDK.")
    }
    return url
  }

  /// Returns the full survey‐script URL as a String
  static var surveyScriptUrlString: String {
    guard let baseURL = URL(string: baseApiUrl) else {
      fatalError("Invalid base URL: \(baseApiUrl)")
    }
    
    // Append path components properly using URL
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
