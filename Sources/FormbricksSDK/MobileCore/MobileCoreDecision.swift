import Foundation

/// The decision returned by the remote mobile core (the server-delivered JS "brain")
/// when asked whether a tracked action should display a survey.
struct MobileCoreDecision: Codable {
    /// Protocol version of the decision payload. Lets old shells reject decisions
    /// produced by a newer, incompatible brain instead of misinterpreting them.
    let v: Int
    let shouldDisplay: Bool
    let surveyId: String?
    let delaySeconds: Double?
    /// The resolved survey language code (e.g. "default" or "de"), already validated
    /// against the survey's enabled languages by the brain.
    let languageCode: String?
    /// Human-readable explanation of the decision, used for logging only.
    let reason: String?
}

/// The user-state snapshot the shell hands to the brain alongside the workspace state.
/// Mirrors what `UserManager` persists; the brain owns all interpretation of it.
struct MobileCoreUserState: Codable {
    let userId: String?
    let segments: [String]?
    let displays: [Display]?
    let responses: [String]?
    /// Milliseconds since epoch; JS-friendly representation of `lastDisplayedAt`.
    let lastDisplayedAtMs: Double?
}
