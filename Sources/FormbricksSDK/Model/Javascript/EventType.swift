enum EventType: String, Codable {
    case onClose
    case onDisplayCreated
    case onResponseCreated
    case onFinished
    case onOpenExternalURL
    case onSurveyLibraryLoadError
    /// The survey card moved or resized. Carries the card's rect so the native side can let
    /// touches outside it reach the host app — see `CardRect`.
    case onCardRectChange
    /// renderSurvey returned, so `formbricksSurveys.setAppearance` can be called.
    case onSurveyRendered
}
