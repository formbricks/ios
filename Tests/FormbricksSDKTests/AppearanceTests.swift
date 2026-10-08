import XCTest
@testable import FormbricksSDK

final class AppearanceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Formbricks.cleanup()
        AppearanceState.set(.light)
    }

    override func tearDown() {
        AppearanceState.set(.light)
        Formbricks.cleanup()
        super.tearDown()
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: style)
    }

    func testDefaultsToLight() {
        XCTAssertEqual(AppearanceState.current, .light)
        XCTAssertEqual(AppearanceState.resolved(traits: traits(.dark)), "light")
    }

    func testSetAppearanceWorksBeforeSetup() {
        XCTAssertFalse(Formbricks.isInitialized)
        Formbricks.setAppearance("dark")
        XCTAssertEqual(AppearanceState.current, .dark)
        XCTAssertEqual(AppearanceState.resolved(traits: traits(.light)), "dark")
    }

    func testSystemFollowsTheAppTheme() {
        Formbricks.setAppearance(.system)
        XCTAssertEqual(AppearanceState.resolved(traits: traits(.dark)), "dark")
        XCTAssertEqual(AppearanceState.resolved(traits: traits(.light)), "light")
    }

    func testUnknownValueFallsBackToLight() {
        Formbricks.setAppearance("dark")
        Formbricks.setAppearance("sepia")
        XCTAssertEqual(AppearanceState.current, .light)
    }

    func testSetupConfigAppliesAppearanceAndLogoutKeepsIt() {
        let config = FormbricksConfig.Builder(appUrl: "https://app.formbricks.com", workspaceId: "ws")
            .set(appearance: .dark)
            .build()
        Formbricks.setup(with: config)
        XCTAssertEqual(AppearanceState.current, .dark)

        Formbricks.logout()
        XCTAssertEqual(AppearanceState.current, .dark)
    }

    func testChangeIsAnnouncedToOpenSurveys() {
        let announced = expectation(forNotification: AppearanceState.didChange, object: nil)
        Formbricks.setAppearance("dark")
        wait(for: [announced], timeout: 1)
    }

    func testSwitchScriptToleratesAnOlderRenderer() {
        XCTAssertEqual(
            AppearanceState.switchScript(for: "dark"),
            "window.formbricksSurveys?.setAppearance?.('dark');")
    }

    // MARK: - Changes made while the survey loads

    func testSurveyRenderedEventDecodes() throws {
        let message = try JSONDecoder().decode(JsMessageData.self, from: Data(#"{"event":"onSurveyRendered"}"#.utf8))
        XCTAssertEqual(message.event, .onSurveyRendered)
    }

    /// The handshake must fire after `renderSurvey`, or a held-back change is sent to no renderer.
    func testHtmlAnnouncesTheRenderAfterRenderSurvey() throws {
        let workspace = try workspace()
        let surveyId = try XCTUnwrap(workspace.data.data.surveys?.first?.id)
        let html = try XCTUnwrap(FormbricksViewModel(workspaceResponse: workspace, surveyId: surveyId).htmlString)
        let render = try XCTUnwrap(html.range(of: "window.formbricksSurveys.renderSurvey(surveyProps);"))
        let rendered = try XCTUnwrap(html.range(of: #"event: "onSurveyRendered""#))
        XCTAssertLessThan(render.upperBound, rendered.lowerBound)
    }

    private func workspace() throws -> WorkspaceResponse {
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "https://example.com", workspaceId: "workspaceId")
            .service(MockFormbricksService())
            .build())
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Environment", withExtension: "json"))
        return try JSONDecoder.iso8601Full.decode(WorkspaceResponse.self, from: Data(contentsOf: url))
    }

    // MARK: - customCss

    func testNoCustomCssSendsNoKey() {
        XCTAssertNil(CustomCss.props(workspace: nil, survey: nil))
        XCTAssertNil(CustomCss.props(workspace: CustomCss(light: "", dark: nil), survey: nil))
    }

    func testCustomCssIsForwardedUntouchedAndEmptyFieldsAreOmitted() {
        let props = CustomCss.props(
            workspace: CustomCss(light: ".a{color:red}", dark: nil),
            survey: CustomCss(light: nil, dark: ".b{margin:0}"))
        XCTAssertEqual(props?["workspace"], ["light": ".a{color:red}"])
        XCTAssertEqual(props?["survey"], ["dark": ".b{margin:0}"])
    }

    func testCustomCssDecodesWithAndWithoutTheKey() throws {
        let with = try JSONDecoder().decode(
            Settings.self,
            from: Data(#"{"customCss":{"light":".a{}"}}"#.utf8))
        XCTAssertEqual(with.customCss, CustomCss(light: ".a{}", dark: nil))

        let without = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertNil(without.customCss)
    }
}
