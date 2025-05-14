import XCTest
@testable import FormbricksSDK

final class FormbricksSDKTests: XCTestCase {
    
    let environmentId = "environmentId"
    let appUrl = "appUrl"
    let userId = "6CCCE716-6783-4D0F-8344-9C7DFA43D8F7"
    let surveyID = "cm6ovw6j7000gsf0kduf4oo4i"
    let mockService = MockFormbricksService()
    let waitDescription = "wait for a second"
    
    override func setUp() {
        super.setUp()
        // Always clean up before each test
        Formbricks.cleanup()
    }
    
    override func tearDown() {
        Formbricks.cleanup()
        super.tearDown()
    }
    
    func testFormbricks() throws {
        // Everything should be in the default state before initialization.
        XCTAssertFalse(Formbricks.isInitialized)
        XCTAssertNil(Formbricks.surveyManager)
        XCTAssertNil(Formbricks.userManager)
        
        // The language should be "default" initially
        XCTAssertEqual(Formbricks.language, "default")
        
        // Set language before SDK setup
        Formbricks.setLanguage("de")
        XCTAssertEqual(Formbricks.language, "de") // This works without initialization
        
        // User manager default state: there is no user yet.
        XCTAssertNil(Formbricks.userManager?.displays)
        XCTAssertNil(Formbricks.userManager?.responses)
        XCTAssertNil(Formbricks.userManager?.segments)
         
        // Use methods before init should have no effect except language.
        Formbricks.setUserId("userId")
        Formbricks.setAttributes(["testA" : "testB"])
        Formbricks.setAttribute("test", forKey: "testKey")
        XCTAssertNil(Formbricks.userManager?.userId)
        
        // Setup the SDK using your new instance-based design.
        // This creates new instances for both the UserManager and SurveyManager.
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .set(attributes: ["a": "b"])
            .add(attribute: "test", forKey: "key")
            .setLogLevel(.debug)
            .build())
       
        // IMPORTANT: Set up the service dependency on both managers BEFORE any API calls happen
        Formbricks.userManager?.service = mockService
        Formbricks.surveyManager?.service = mockService
        
        XCTAssertTrue(Formbricks.isInitialized)
        XCTAssertEqual(Formbricks.appUrl, appUrl)
        XCTAssertEqual(Formbricks.environmentId, environmentId)
         
        // Check error state handling.
        mockService.isErrorResponseNeeded = true
        XCTAssertFalse(Formbricks.surveyManager?.hasApiError ?? false)
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        XCTAssertTrue(Formbricks.surveyManager?.hasApiError ?? false)

        mockService.isErrorResponseNeeded = false
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        
        // Wait for environment to refresh
        let refreshExpectation = expectation(description: "Environment refreshed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshExpectation.fulfill()
        }
        wait(for: [refreshExpectation], timeout: 1.0)
        
        // Authenticate the user.
        Formbricks.setUserId(userId)
        let userSetExpectation = expectation(description: "User set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            userSetExpectation.fulfill()
        }
        wait(for: [userSetExpectation], timeout: 1.0)

        XCTAssertEqual(Formbricks.userManager?.userId, userId)
        // User refresh timer should be set.
        XCTAssertNotNil(Formbricks.userManager?.syncTimer)
        
        // The environment should be fetched.
        XCTAssertNotNil(Formbricks.surveyManager?.environmentResponse)
        
        // Check if the filter method works properly.
        XCTAssertEqual(Formbricks.surveyManager?.filteredSurveys.count, 1)
        
        // Verify that we're not showing any survey initially.
        XCTAssertNotNil(Formbricks.surveyManager?.filteredSurveys)
        XCTAssertFalse(Formbricks.surveyManager?.isShowingSurvey ?? false)
        
        // Track an unknown event—survey should not be shown.
        Formbricks.track("unknown_event")
        XCTAssertFalse(Formbricks.surveyManager?.isShowingSurvey ?? false)
        
        // Track a known event—the survey should be shown.
        Formbricks.track("click_demo_button")
        let trackExpectation = expectation(description: "Track event")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            trackExpectation.fulfill()
        }
        wait(for: [trackExpectation], timeout: 1.0)
        
        XCTAssertTrue(Formbricks.surveyManager?.isShowingSurvey ?? false)
        
        // "Dismiss" the webview.
        Formbricks.surveyManager?.dismissSurveyWebView()
        XCTAssertFalse(Formbricks.surveyManager?.isShowingSurvey ?? false)
        
        // Validate display and response.
        Formbricks.surveyManager?.postResponse(surveyId: surveyID)
        Formbricks.surveyManager?.onNewDisplay(surveyId: surveyID)
        XCTAssertEqual(Formbricks.userManager?.responses?.count, 1)
        XCTAssertEqual(Formbricks.userManager?.displays?.count, 1)
        
        // Track a valid event, but survey should not be shown because a response was already submitted.
        Formbricks.track("click_demo_button")
        let secondTrackExpectation = expectation(description: "Second track event")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            secondTrackExpectation.fulfill()
        }
        wait(for: [secondTrackExpectation], timeout: 1.0)
        
        XCTAssertFalse(Formbricks.surveyManager?.isShowingSurvey ?? false)
        
        // Validate logout.
        XCTAssertNotNil(Formbricks.userManager?.userId)
        XCTAssertNotNil(Formbricks.userManager?.responses)
        XCTAssertNotNil(Formbricks.userManager?.displays)
        Formbricks.logout()
        
        let logoutExpectation = expectation(description: "Logout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            logoutExpectation.fulfill()
        }
        wait(for: [logoutExpectation], timeout: 1.0)
        
        XCTAssertNil(Formbricks.userManager?.userId)
        XCTAssertNil(Formbricks.userManager?.responses)
        XCTAssertNil(Formbricks.userManager?.displays)
        
        // Clear the responses and verify survey behavior.
        Formbricks.logout()
        Formbricks.surveyManager?.filterSurveys()
        
        Formbricks.track("click_demo_button")
        let thirdTrackExpectation = expectation(description: "Third track event")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            thirdTrackExpectation.fulfill()
        }
        wait(for: [thirdTrackExpectation], timeout: 1.0)
        
        XCTAssertTrue(Formbricks.surveyManager?.isShowingSurvey ?? false)
        
        // Test the cleanup
        Formbricks.cleanup()
        XCTAssertNil(Formbricks.userManager)
        XCTAssertNil(Formbricks.surveyManager)
        XCTAssertNil(Formbricks.apiQueue)
        XCTAssertNil(Formbricks.presentSurveyManager)
        XCTAssertFalse(Formbricks.isInitialized)
        XCTAssertNil(Formbricks.appUrl)
        XCTAssertNil(Formbricks.environmentId)
        XCTAssertNil(Formbricks.logger)
    }
    
//    func testCleanupWithCompletion() {
//        // Setup the SDK
//        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
//            .setLogLevel(.debug)
//            .build()
//        Formbricks.setup(with: config)
//        
//        // IMPORTANT: Set up mocks immediately
//        Formbricks.userManager?.service = mockService
//        Formbricks.surveyManager?.service = mockService
//        
//        XCTAssertTrue(Formbricks.isInitialized)
//        
//        // Ensure operations complete before cleanup
//        let setupCompleteExpectation = expectation(description: "Setup complete")
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//            setupCompleteExpectation.fulfill()
//        }
//        wait(for: [setupCompleteExpectation], timeout: 1.0)
//        
//        // Use a DispatchSemaphore so we can synchronously wait for the cleanup to complete
//        // without relying on XCTest expectations which can time out
//        let semaphore = DispatchSemaphore(value: 0)
//        
//        Formbricks.cleanup(waitForOperations: true) {
//            semaphore.signal()
//        }
//        
//        // Wait for cleanup to finish with a longer timeout
//        _ = semaphore.wait(timeout: .now() + 10.0)
//        
//        // Add a short delay to allow any final cleanup to finish
//        let postCleanupExpectation = expectation(description: "Post cleanup")
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//            postCleanupExpectation.fulfill()
//        }
//        wait(for: [postCleanupExpectation], timeout: 1.0)
//        
//        // Validate cleanup: all main properties should be nil or false
//        XCTAssertNil(Formbricks.userManager)
//        XCTAssertNil(Formbricks.surveyManager)
//        XCTAssertNil(Formbricks.presentSurveyManager)
//        XCTAssertNil(Formbricks.apiQueue)
//        XCTAssertFalse(Formbricks.isInitialized)
//        XCTAssertNil(Formbricks.appUrl)
//        XCTAssertNil(Formbricks.environmentId)
//        XCTAssertNil(Formbricks.logger)
//    }
}
