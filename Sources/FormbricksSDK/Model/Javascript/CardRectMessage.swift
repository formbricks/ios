import CoreGraphics
import Foundation

/// Where the survey card is, as the shared renderer measures it.
///
/// A `WKWebView` hit-tests its whole rectangle and ignores the `pointer-events: none` the renderer
/// puts outside the card, so a full-screen WebView swallows every touch even when nothing is
/// painted. To let touches through, the native side has to mask them itself — and only the web
/// layer knows where the card is, because CSS decides that.
///
/// Values are CSS pixels relative to the viewport. The WebView's viewport is pinned at
/// `initial-scale=1.0, maximum-scale=1.0` (see `FormbricksViewModel.htmlTemplate`), so one CSS
/// pixel is one point and the rect needs no conversion.
struct CardRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// `onCardRectChange` payload. `rect` is absent or null when no card is on screen — while it
/// animates out, or before the first paint.
struct CardRectMessage: Codable {
    let rect: CardRect?
}
