enum EventType: String, Codable {
    case onClose = "onClose"
    case onDisplayCreated = "onDisplayCreated"
    case onResponseCreated = "onResponseCreated"
    case onFinished = "onFinished"
    case onOpenExternalURL = "onOpenExternalURL"
    case onSurveyLibraryLoadError = "onSurveyLibraryLoadError"
    /// The survey card moved or resized. Carries the card's rect so the native side can let
    /// touches outside it reach the host app — see `CardRect`.
    case onCardRectChange = "onCardRectChange"
}
