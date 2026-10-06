import UIKit
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

    override func setUp() {
        super.setUp()
        Formbricks.cleanup()
    }

    override func tearDown() {
        Formbricks.cleanup()
        super.tearDown()
    }

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
        XCTAssertEqual(SurveyTextScale.textSizeAdjust(for: .extraExtraExtraLarge), "135%")
    }

    func testTheAccessibilitySizesStopAtTheCap() {
        XCTAssertTrue(categories.allSatisfy { SurveyTextScale.factor(for: $0) <= SurveyTextScale.maximumFactor })
        XCTAssertEqual(SurveyTextScale.textSizeAdjust(for: .accessibilityExtraExtraExtraLarge), "200%")
    }

    /// The setting has to reach the page's root element, or WebKit never applies it.
    func testTheSurveyPageCarriesTheSetting() throws {
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "https://example.com", workspaceId: "workspaceId")
            .service(MockFormbricksService())
            .build())
        let fixtureUrl = try XCTUnwrap(Bundle.module.url(forResource: "Environment", withExtension: "json"))
        let workspace = try JSONDecoder.iso8601Full.decode(WorkspaceResponse.self, from: Data(contentsOf: fixtureUrl))

        func html(_ category: UIContentSizeCategory) throws -> String {
            try XCTUnwrap(FormbricksViewModel(
                workspaceResponse: workspace, surveyId: "cm6ovw6j7000gsf0kduf4oo4i",
                contentSizeCategory: category
            ).htmlString)
        }

        XCTAssertTrue(try html(.large).contains("html { -webkit-text-size-adjust: auto; }"))
        XCTAssertTrue(try html(.accessibilityExtraExtraExtraLarge).contains("html { -webkit-text-size-adjust: 200%; }"))
    }
}
