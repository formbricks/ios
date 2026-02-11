struct Project: Codable {
    let id: String?
    let recontactDays: Int?
    let clickOutsideClose: Bool?
    let overlay: SurveyOverlay?
    let placement: String?
    let inAppSurveyBranding: Bool?
    let styling: Styling?
}
