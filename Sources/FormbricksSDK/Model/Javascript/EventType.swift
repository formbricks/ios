enum EventType: String, Codable {
    case onClose = "onClose"
    case onDisplayCreated = "onDisplayCreated"
    case onResponseCreated = "onResponseCreated"
    case onFinished = "onFinished"
    case onOpenExternalURL = "onOpenExternalURL"
    case onSurveyLibraryLoadError = "onSurveyLibraryLoadError"
}
