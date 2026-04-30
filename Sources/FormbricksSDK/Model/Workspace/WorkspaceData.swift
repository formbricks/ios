struct WorkspaceData: Codable {
    let surveys: [Survey]?
    let actionClasses: [ActionClass]?
    let settings: Settings
    let recaptchaSiteKey: String?

    enum CodingKeys: String, CodingKey {
        case surveys
        case actionClasses
        case settings
        case workspace
        case project
        case recaptchaSiteKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        surveys = try container.decodeIfPresent([Survey].self, forKey: .surveys)
        actionClasses = try container.decodeIfPresent([ActionClass].self, forKey: .actionClasses)
        recaptchaSiteKey = try container.decodeIfPresent(String.self, forKey: .recaptchaSiteKey)

        // Server may respond with `settings`, `workspace`, or legacy `project` — all carry the same shape.
        if let settings = try container.decodeIfPresent(Settings.self, forKey: .settings) {
            self.settings = settings
        } else if let workspace = try container.decodeIfPresent(Settings.self, forKey: .workspace) {
            self.settings = workspace
        } else if let project = try container.decodeIfPresent(Settings.self, forKey: .project) {
            self.settings = project
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.settings,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected one of 'settings', 'workspace', or 'project' key in workspace data"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(surveys, forKey: .surveys)
        try container.encodeIfPresent(actionClasses, forKey: .actionClasses)
        try container.encodeIfPresent(recaptchaSiteKey, forKey: .recaptchaSiteKey)
        try container.encode(settings, forKey: .settings)
    }
}
