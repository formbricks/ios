enum DisplayOptionType: String, Codable {
    case respondMultiple
    case displayOnce
    case displayMultiple
    case displaySome
}

struct SurveyLanguage: Codable {
    let enabled: Bool
    let isDefault: Bool  // must differ from "default" in JSON
    let language: LanguageDetail

    private enum CodingKeys: String, CodingKey {
        case enabled
        case isDefault = "default"
        case language
    }
}

struct LanguageDetail: Codable {
    let id: String
    let code: String
    let alias: String?
    let projectId: String
}

// MARK: - New types for projectOverwrites

enum Placement: String, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
}

/// Defines the overlay style displayed behind a survey modal.
enum SurveyOverlay: String, Codable {
    case none
    case light
    case dark
}

struct ProjectOverwrites: Codable {
    let brandColor: String?
    let highlightBorderColor: String?
    let placement: Placement?
    let clickOutsideClose: Bool?
    let overlay: SurveyOverlay?
}

struct Survey: Codable {
    let id: String
    // `name` intentionally omitted — internal label, not returned by the
    // public client API. Cached payloads from older SDK versions may still
    // include it in JSON; Codable will quietly ignore unknown keys.
    let triggers: [Trigger]?
    let recontactDays: Int?
    let displayLimit: Int?
    let delay: Int?
    let displayPercentage: Double?
    let displayOption: DisplayOptionType?
    let segment: Segment?
    let styling: Styling?
    var customCss: CustomCss?
    let languages: [SurveyLanguage]?
    let projectOverwrites: ProjectOverwrites?
    /// Whether interacting with this survey can change some live survey's segment
    /// membership. Absent unless the workspace uses survey-interaction targeting.
    let interactionRefresh: InteractionRefresh?
}
