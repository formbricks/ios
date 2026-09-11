import UIKit

/// Which touches over the survey's full-screen WebView belong to the survey, and which should fall
/// through to the host app underneath.
///
/// A `WKWebView` hit-tests its entire rectangle. The shared renderer already sets
/// `pointer-events: none` outside the card, but that is a *web* hit test — UIKit never sees it, so a
/// transparent full-screen WebView still swallows every touch and the host app appears frozen.
enum SurveyTouchRegion: Equatable {
    /// Every touch belongs to the survey.
    ///
    /// Correct for a `light` or `dark` overlay, where a visible backdrop is *supposed* to block the
    /// host app. Also the starting state for a no-overlay survey, and it stays that way if the
    /// renderer never reports a rect — an older self-hosted server serves a bundle without
    /// `onCardRectChange`, and behaving exactly as the SDK always did is the safe answer there.
    case everything

    /// Only touches inside this rect belong to the survey; everything else reaches the host app.
    /// The rect is in window points, which the reported CSS-pixel rect maps onto 1:1 (see `CardRect`).
    case card(CGRect)

    /// Nothing belongs to the survey, because no card is on screen.
    ///
    /// The renderer reports this while the card animates out, and the card is hidden for a full
    /// second before `onClose` arrives. Without this state the SDK leaves a dead patch over a host
    /// app that looks perfectly usable.
    case nothing

    /// Whether a touch at `point` (in window coordinates) belongs to the survey.
    func accepts(_ point: CGPoint) -> Bool {
        switch self {
        case .everything:
            return true
        case .card(let rect):
            return rect.contains(point)
        case .nothing:
            return false
        }
    }

    /// Maps a rect reported by the renderer onto a region. A missing rect means the card is not on
    /// screen — deliberately *not* "block everything", which is the trap the Flutter SDK fell into
    /// when its DOM probe stopped matching: a null rect there meant the survey itself became
    /// untappable. Absence of a card and absence of the feature are different things, and only the
    /// latter keeps `everything`.
    static func forReported(rect: CardRect?) -> SurveyTouchRegion {
        guard let rect = rect else { return .nothing }
        return .card(rect.cgRect)
    }
}

/// Hosts a no-overlay survey in its own window so touches outside the card reach the host app.
///
/// Returning `nil` from `hitTest` makes UIKit continue to the next window down, which is the host
/// app's. A presented view controller cannot do this reliably: UIKit's own transition container
/// answers the hit test for the whole screen even when the content declines it.
final class PassthroughWindow: UIWindow {
    /// Starts at `.everything`, so the SDK blocks touches exactly as it used to until the renderer
    /// tells us where the card is.
    var touchRegion: SurveyTouchRegion = .everything

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard touchRegion.accepts(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Carries card rects from the JS bridge to whoever is doing the hit testing.
///
/// A plain box rather than an `ObservableObject`: nothing here drives SwiftUI, and re-rendering the
/// WebView on every frame of the card's open animation is the opposite of what we want.
final class SurveyLayoutRelay {
    /// Called on the main thread each time the renderer reports the card's rect, `nil` when no card
    /// is on screen.
    var onCardRectChange: ((CardRect?) -> Void)?
}
