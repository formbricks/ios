import Foundation

/// The three survey-lifecycle moments that can flip interaction-based segment membership.
/// Raw values match the source names used by the JS SDK so the gate below can be keyed
/// off the same vocabulary on both platforms.
enum InteractionSource: String {
    case onDisplay
    case onResponse
    case onFinished
}

/// Per-survey gate for the post-interaction segment refresh.
///
/// Each flag says whether interacting with *this* survey via that event can change some
/// live survey's segment membership — e.g. a survey referenced only by a "have seen"
/// filter refreshes on display but not on response or finish, and a survey no interaction
/// filter references never refreshes at all.
///
/// The client API attaches this only for workspaces that use survey-interaction targeting,
/// so it is absent for everyone else, and present-but-all-false for surveys in such a
/// workspace that no interaction filter points at.
struct InteractionRefresh: Codable, Equatable {
    let onDisplay: Bool
    let onResponse: Bool
    let onFinished: Bool

    private enum CodingKeys: String, CodingKey {
        case onDisplay, onResponse, onFinished
    }

    init(onDisplay: Bool = false, onResponse: Bool = false, onFinished: Bool = false) {
        self.onDisplay = onDisplay
        self.onResponse = onResponse
        self.onFinished = onFinished
    }

    /// Missing sub-keys decode as `false`, mirroring the tolerant `Segment` decoder. A strict
    /// model would turn a partial object into a `keyNotFound` on the whole workspace-state
    /// decode, which blanks out every survey — so never require these keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onDisplay = try container.decodeIfPresent(Bool.self, forKey: .onDisplay) ?? false
        onResponse = try container.decodeIfPresent(Bool.self, forKey: .onResponse) ?? false
        onFinished = try container.decodeIfPresent(Bool.self, forKey: .onFinished) ?? false
    }

    /// Whether an interaction of this kind should trigger a user-state refresh.
    func shouldRefresh(on source: InteractionSource) -> Bool {
        switch source {
        case .onDisplay:  return onDisplay
        case .onResponse: return onResponse
        case .onFinished: return onFinished
        }
    }
}
