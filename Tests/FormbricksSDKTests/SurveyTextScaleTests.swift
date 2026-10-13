import UIKit
import WebKit
import XCTest
@testable import FormbricksSDK

/// WKWebView ignores Dynamic Type, so the SDK hands the user's setting to the survey page itself
/// (ENG-3427). These pin what a respondent can see: the default size renders exactly as before, the
/// text follows the setting in both directions, and the accessibility sizes stop at the cap the
/// survey layout is known to fit.
final class SurveyTextScaleTests: XCTestCase {

    /// Every Dynamic Type setting, smallest to largest.
    private let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    func testTheDefaultSizeLeavesThePageUntouched() {
        XCTAssertEqual(SurveyTextScale.factor(for: .large), 1)
        XCTAssertEqual(SurveyTextScale.textSizeAdjust(for: .large), "auto")
        XCTAssertEqual(SurveyTextScale.textSizeAdjust(for: .unspecified), "auto",
                       "A trait collection with no setting must read as the default size")
    }

    func testTheTextFollowsTheSettingInBothDirections() {
        let factors = categories.map(SurveyTextScale.factor(for:))
        XCTAssertEqual(factors, factors.sorted(), "A larger setting must never make the text smaller")
        XCTAssertLessThan(SurveyTextScale.factor(for: .extraSmall), 1)
        let largestStandardSize = SurveyTextScale.factor(for: .extraExtraExtraLarge)
        XCTAssertTrue(largestStandardSize > 1 && largestStandardSize < SurveyTextScale.maximumFactor,
                      "The largest non-accessibility size must grow the text without reaching the cap")
    }

    func testTheAccessibilitySizesStopAtTheCap() {
        XCTAssertTrue(categories.allSatisfy { SurveyTextScale.factor(for: $0) <= SurveyTextScale.maximumFactor })
        XCTAssertEqual(SurveyTextScale.textSizeAdjust(for: .accessibilityExtraExtraExtraLarge), "200%")
    }

    /// The setting has to reach the page's root element, or WebKit never applies it. It comes from the
    /// presenting window's traits, so a host app that overrides Dynamic Type there sizes the survey too.
    func testTheSurveyPageCarriesThePresentersSetting() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("traitOverrides needs iOS 17") }
        let workspace = try setUpWorkspace()

        func html(presentedFrom traitSource: UITraitEnvironment?) throws -> String {
            try XCTUnwrap(FormbricksViewModel(
                workspaceResponse: workspace, surveyId: surveyId, traitSource: traitSource
            ).htmlString)
        }
        // Both directions, so the assertions hold whatever the simulator's own setting is.
        let largest = UIWindow(frame: .zero)
        largest.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        let smallest = UIWindow(frame: .zero)
        smallest.traitOverrides.preferredContentSizeCategory = .extraSmall

        XCTAssertTrue(try html(presentedFrom: largest).contains("-webkit-text-size-adjust: 200%"))
        XCTAssertTrue(try html(presentedFrom: smallest).contains(
            "-webkit-text-size-adjust: \(SurveyTextScale.textSizeAdjust(for: .extraSmall))"))
        XCTAssertTrue(try html(presentedFrom: nil).contains("-webkit-text-size-adjust: auto"),
                      "Without a presenter the page must not depend on the device's setting")
    }

    /// WebKit ignores the percentage in desktop-class content mode, which full-size iPads would
    /// otherwise load the survey in.
    func testTheSurveyWebViewAsksForMobileContent() throws {
        let workspace = try setUpWorkspace()
        let window = PassthroughWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let manager = PresentSurveyManager()
        manager.installPassthroughWindow(window, workspaceResponse: workspace, id: surveyId)
        addTeardownBlock { manager.dismissView() }
        window.layoutIfNeeded()

        let webView = try XCTUnwrap(firstWebView(in: window))
        XCTAssertEqual(webView.configuration.defaultWebpagePreferences.preferredContentMode, .mobile)
    }

    private let surveyId = "cm6ovw6j7000gsf0kduf4oo4i"

    /// Sets the SDK up for building a survey page, and tears it down after the test.
    private func setUpWorkspace() throws -> WorkspaceResponse {
        Formbricks.cleanup()
        addTeardownBlock { Formbricks.cleanup() }
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "https://example.com", workspaceId: "workspaceId")
            .service(MockFormbricksService())
            .build())
        let fixtureUrl = try XCTUnwrap(Bundle.module.url(forResource: "Environment", withExtension: "json"))
        return try JSONDecoder.iso8601Full.decode(WorkspaceResponse.self, from: Data(contentsOf: fixtureUrl))
    }

    private func firstWebView(in view: UIView) -> WKWebView? {
        (view as? WKWebView) ?? view.subviews.lazy.compactMap(firstWebView(in:)).first
    }
}
