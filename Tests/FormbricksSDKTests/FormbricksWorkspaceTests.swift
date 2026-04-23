import XCTest
@testable import FormbricksSDK

final class FormbricksWorkspaceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Always clean up before each test
        Formbricks.cleanup()
    }

    override func tearDown() {
        Formbricks.cleanup()
        super.tearDown()
    }

    func testBaseApiUrl() {
        // Test that baseApiUrl returns nil when appUrl is nil
        XCTAssertNil(FormbricksWorkspace.baseApiUrl)

        // Setup SDK with valid appUrl
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "https://app.formbricks.com", workspaceId: "test-workspace-id")
            .setLogLevel(.debug)
            .build())

        // Test that baseApiUrl returns the correct URL
        XCTAssertEqual(FormbricksWorkspace.baseApiUrl, "https://app.formbricks.com")
    }

    func testSurveyScriptUrlString() {
        // Test that surveyScriptUrlString returns nil when appUrl is nil
        XCTAssertNil(FormbricksWorkspace.surveyScriptUrlString)

        // Setup SDK with valid appUrl
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "https://app.formbricks.com", workspaceId: "test-workspace-id")
            .setLogLevel(.debug)
            .build())

        // Test that surveyScriptUrlString returns the correct URL
        XCTAssertEqual(FormbricksWorkspace.surveyScriptUrlString, "https://app.formbricks.com/js/surveys.umd.cjs")

        // Test with invalid URL
        Formbricks.cleanup()
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "invalid url", workspaceId: "test-workspace-id")
            .setLogLevel(.debug)
            .build())

        // Test that surveyScriptUrlString returns nil for invalid URL
        XCTAssertNil(FormbricksWorkspace.surveyScriptUrlString)
    }
}
