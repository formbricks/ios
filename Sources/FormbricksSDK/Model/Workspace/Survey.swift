enum DisplayOptionType: String, Codable {
    case respondMultiple = "respondMultiple"
    case displayOnce = "displayOnce"
    case displayMultiple = "displayMultiple"
    case displaySome = "displaySome"
}

struct SurveyLanguage: Codable {
    let enabled: Bool
    let isDefault: Bool       // must differ from "default" in JSON
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
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    case center = "center"
}

/// Defines the overlay style displayed behind a survey modal.
enum SurveyOverlay: String, Codable {
    case none = "none"
    case light = "light"
    case dark = "dark"
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
    let name: String
    let triggers: [Trigger]?
    let recontactDays: Int?
    let displayLimit: Int?
    let delay: Int?
    let displayPercentage: Double?
    let displayOption: DisplayOptionType?
    let segment: Segment?
    let styling: Styling?
    let languages: [SurveyLanguage]?
    let projectOverwrites: ProjectOverwrites?
}
