/// Compiled custom CSS for one scope; either mode may be absent. Forwarded to the renderer untouched.
struct CustomCss: Codable, Equatable {
    let light: String?
    let dark: String?

    /// The scope's non-empty strings, or nil when there is nothing to send. The renderer rejects
    /// the whole prop on a `null` inside a scope, so empty fields are omitted rather than nulled.
    var payload: [String: String]? {
        var result: [String: String] = [:]
        if let light, !light.isEmpty { result["light"] = light }
        if let dark, !dark.isEmpty { result["dark"] = dark }
        return result.isEmpty ? nil : result
    }

    /// The renderer's `customCss` prop, or nil (no key at all) when neither scope has CSS.
    static func props(workspace: CustomCss?, survey: CustomCss?) -> [String: [String: String]]? {
        var result: [String: [String: String]] = [:]
        if let workspace = workspace?.payload { result["workspace"] = workspace }
        if let survey = survey?.payload { result["survey"] = survey }
        return result.isEmpty ? nil : result
    }
}
