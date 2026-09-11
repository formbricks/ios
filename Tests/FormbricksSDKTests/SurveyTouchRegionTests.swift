import XCTest
@testable import FormbricksSDK

/// A transparent full-screen WebView still swallows every touch — `pointer-events: none` is a web
/// hit test that UIKit never sees. These pin which touches the survey claims in each overlay mode,
/// because getting it wrong is invisible in code review and obvious to a user: either the host app
/// freezes, or the survey itself stops responding.
final class SurveyTouchRegionTests: XCTestCase {

    private let card = CGRect(x: 0, y: 600, width: 390, height: 240)
    private var insideCard: CGPoint { CGPoint(x: 195, y: 700) }
    private var outsideCard: CGPoint { CGPoint(x: 195, y: 200) }

    // MARK: - overlay: light / dark

    /// A visible backdrop is meant to block the host app, so the survey claims the whole screen.
    func testAnOverlaidSurveyClaimsEveryTouch() {
        let region = SurveyTouchRegion.everything

        XCTAssertTrue(region.accepts(insideCard))
        XCTAssertTrue(region.accepts(outsideCard))
        XCTAssertTrue(region.accepts(.zero))
    }

    // MARK: - overlay: none

    /// The card takes its own touches; everything else falls through to the host app.
    func testANoOverlaySurveyClaimsOnlyTheCard() {
        let region = SurveyTouchRegion.forReported(
            rect: CardRect(x: 0, y: 600, width: 390, height: 240))

        XCTAssertEqual(region, .card(card))
        XCTAssertTrue(region.accepts(insideCard), "The survey must stay usable")
        XCTAssertFalse(region.accepts(outsideCard), "The host app must stay usable")
    }

    /// The renderer reports the card's absence, and the SDK must stop claiming touches at that
    /// point. The card is hidden for a full second before `onClose` arrives, so without this the
    /// SDK leaves a dead patch over a host app that looks perfectly usable.
    func testNoCardOnScreenClaimsNothing() {
        let region = SurveyTouchRegion.forReported(rect: nil)

        XCTAssertEqual(region, .nothing)
        XCTAssertFalse(region.accepts(insideCard))
        XCTAssertFalse(region.accepts(outsideCard))
    }

    /// An older self-hosted server serves a renderer that never calls `onCardRectChange`, so no
    /// rect ever arrives. The SDK has to keep behaving exactly as it used to rather than guess.
    ///
    /// This is the distinction the Flutter SDK got wrong: there, a missing rect meant "claim
    /// nothing", so when its DOM probe stopped matching, the survey became untappable. Absence of a
    /// card and absence of the feature are different things.
    func testTheDefaultBeforeAnyRectArrivesBlocksLikeBefore() {
        let window = PassthroughWindow(frame: .zero)

        XCTAssertEqual(window.touchRegion, .everything)
        XCTAssertTrue(window.touchRegion.accepts(outsideCard))
    }

    // MARK: - Boundaries

    /// `CGRect.contains` excludes the far edges, so a tap on the card's bottom-right corner pixel
    /// belongs to the host app. Pinned because a future switch to `insetBy` or a rounding change
    /// would move this silently.
    func testCardEdgesFollowCGRectContains() {
        let region = SurveyTouchRegion.card(card)

        XCTAssertTrue(region.accepts(CGPoint(x: card.minX, y: card.minY)), "Top-left is inside")
        XCTAssertFalse(region.accepts(CGPoint(x: card.maxX, y: card.maxY)), "Bottom-right is not")
        XCTAssertFalse(region.accepts(CGPoint(x: card.minX - 1, y: card.minY)))
    }

    /// A zero-area rect would claim nothing anyway, but the renderer already reports absence rather
    /// than a degenerate rect — assert the mapping keeps its shape if that ever changes.
    func testAZeroAreaCardClaimsNothing() {
        let region = SurveyTouchRegion.forReported(rect: CardRect(x: 10, y: 10, width: 0, height: 0))

        XCTAssertFalse(region.accepts(CGPoint(x: 10, y: 10)))
    }

    // MARK: - Decoding the bridge payload

    /// The rect arrives as JSON over the JS bridge, so the decode is part of the contract.
    func testDecodesAReportedRect() throws {
        let json = #"{"event":"onCardRectChange","rect":{"x":12.5,"y":600,"width":390,"height":240.25}}"#
        let message = try JSONDecoder().decode(CardRectMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message.rect?.cgRect, CGRect(x: 12.5, y: 600, width: 390, height: 240.25))
    }

    /// `rect: null` is how the renderer says the card has gone. It must decode, not throw — a throw
    /// would leave the SDK masking touches to a card that is no longer there.
    func testDecodesAnAbsentRect() throws {
        let json = #"{"event":"onCardRectChange","rect":null}"#
        let message = try JSONDecoder().decode(CardRectMessage.self, from: Data(json.utf8))

        XCTAssertNil(message.rect)
        XCTAssertEqual(SurveyTouchRegion.forReported(rect: message.rect), .nothing)
    }
}
