import XCTest
@testable import FormbricksSDK

final class FormbricksSDKTests: XCTestCase {
    let environmentId = "environmentId"
    let appUrl = "https://example.com"
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
            .service(mockService)
            .build()
        )
        
        XCTAssertTrue(Formbricks.isInitialized)
        XCTAssertEqual(Formbricks.appUrl, appUrl)
        XCTAssertEqual(Formbricks.environmentId, environmentId)
         
        // Check error state handling.
        XCTAssertFalse(Formbricks.surveyManager?.hasApiError ?? false)
        
        mockService.isErrorResponseNeeded = true
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        XCTAssertTrue(Formbricks.surveyManager?.hasApiError ?? false)

        mockService.isErrorResponseNeeded = false
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        
        // Wait for environment to refresh
        let refreshExpectation = expectation(description: "Environment refreshed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshExpectation.fulfill()
        }
        wait(for: [refreshExpectation])
        
        // Authenticate the user.
        Formbricks.setUserId(userId)
        
        // Wait for user ID to be set with a longer timeout
        let userSetExpectation = expectation(description: "User set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            userSetExpectation.fulfill()
        }
        wait(for: [userSetExpectation], timeout: 3.0)

        // Verify user ID is set
        XCTAssertEqual(Formbricks.userManager?.userId, userId, "User ID should be set")
        // User refresh timer should be set.
        XCTAssertNotNil(Formbricks.userManager?.syncTimer, "Sync timer should be set")
        
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
        let trackExpectation = expectation(description: "Track event")
        Formbricks.track("click_demo_button", completion: {
            trackExpectation.fulfill()
        })
        
        wait(for: [trackExpectation])
        
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            secondTrackExpectation.fulfill()
        }
        wait(for: [secondTrackExpectation], timeout: 5.0)
        
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
        
        let thirdTrackExpectation = expectation(description: "Third track event")
        Formbricks.track("click_demo_button", completion: {
            thirdTrackExpectation.fulfill()
        })
        
        wait(for: [thirdTrackExpectation])
        
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
    
    func testCleanupWithCompletion() {
        // Setup the SDK
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        
        Formbricks.setup(with: config)
        
        XCTAssertTrue(Formbricks.isInitialized)
        
        // Wait for cleanup to complete using XCTestExpectation
        let cleanupExpectation = expectation(description: "Cleanup complete")
        Formbricks.cleanup(waitForOperations: true) {
            cleanupExpectation.fulfill()
        }

        wait(for: [cleanupExpectation])
        
        // Validate cleanup: all main properties should be nil or false
        XCTAssertNil(Formbricks.userManager, "User manager should be nil")
        XCTAssertNil(Formbricks.surveyManager, "Survey manager should be nil")
        XCTAssertNil(Formbricks.presentSurveyManager, "Present survey manager should be nil")
        XCTAssertNil(Formbricks.apiQueue, "API queue should be nil")
        XCTAssertFalse(Formbricks.isInitialized, "SDK should not be initialized")
        XCTAssertNil(Formbricks.appUrl, "App URL should be nil")
        XCTAssertNil(Formbricks.environmentId, "Environment ID should be nil")
        XCTAssertNil(Formbricks.logger, "Logger should be nil")
    }
    
    func testSurveyManagerEdgeCases() {
        // Setup
        let userManager = UserManager()
        let presentSurveyManager = PresentSurveyManager()
        let service = MockFormbricksService()
        let manager = SurveyManager.create(userManager: userManager, presentSurveyManager: presentSurveyManager, service: service)

        // shouldDisplayBasedOnPercentage
        XCTAssertTrue(manager.shouldDisplayBasedOnPercentage(nil))
        XCTAssertTrue(manager.shouldDisplayBasedOnPercentage(100))
        XCTAssertFalse(manager.shouldDisplayBasedOnPercentage(0))

        // UserDefaults: corrupt data
        UserDefaults.standard.set(Data([0x00, 0x01]), forKey: "environmentResponseObjectKey")
        XCTAssertNil(manager.environmentResponse)

        // Timer-based refresh: wait deterministically for the environment refresh notification
        let notificationExpectation = expectation(forNotification: .environmentRefreshed, object: manager, handler: nil)
        manager.refreshEnvironmentAfter(timeout: 0.1)
        wait(for: [notificationExpectation], timeout: 2.0)

        // getLanguageCode coverage
        let survey = Survey(
            id: "1",
            name: "Test Survey",
            triggers: nil,
            recontactDays: nil,
            displayLimit: nil,
            delay: nil,
            displayPercentage: nil,
            displayOption: .respondMultiple,
            segment: nil,
            styling: nil,
            languages: [
                SurveyLanguage(enabled: true, isDefault: true, language: LanguageDetail(id: "1", code: "en", alias: "english", projectId: "p1")),
                SurveyLanguage(enabled: true, isDefault: false, language: LanguageDetail(id: "2", code: "de", alias: "german", projectId: "p1")),
                SurveyLanguage(enabled: false, isDefault: false, language: LanguageDetail(id: "3", code: "fr", alias: nil, projectId: "p1"))
            ],
            projectOverwrites: nil
        )
        // No language provided
        XCTAssertEqual(manager.getLanguageCode(survey: survey, language: nil), "default")
        // Explicit default
        XCTAssertEqual(manager.getLanguageCode(survey: survey, language: "default"), "default")
        // Code match, enabled
        XCTAssertEqual(manager.getLanguageCode(survey: survey, language: "de"), "de")
        // Alias match, enabled
        XCTAssertEqual(manager.getLanguageCode(survey: survey, language: "english"), "default") // isDefault
        // Code match, disabled
        XCTAssertNil(manager.getLanguageCode(survey: survey, language: "fr"))
        // Alias not found
        XCTAssertNil(manager.getLanguageCode(survey: survey, language: "spanish"))
    }

    func testWebViewDataUsesSurveyOverwrites() {
        // Setup SDK with mock service loading Environment.json (which now includes projectOverwrites)
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)

        // Force refresh and wait briefly for async fetch
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        let expectation = self.expectation(description: "Env loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }
        wait(for: [expectation])

        guard let env = Formbricks.surveyManager?.environmentResponse else {
            XCTFail("Missing environmentResponse")
            return
        }

        // Build the view model to produce WEBVIEW_DATA
        let vm = FormbricksViewModel(environmentResponse: env, surveyId: surveyID)
        guard let html = vm.htmlString else {
            XCTFail("Missing htmlString")
            return
        }

        // Extract the JSON payload between backticks in `const json = `...``
        guard let markerRange = html.range(of: "const json = `") else {
            XCTFail("Marker not found")
            return
        }
        let start = markerRange.upperBound
        guard let end = html[start...].firstIndex(of: "`") else {
            XCTFail("End backtick not found")
            return
        }
        let jsonSubstring = html[start..<end]
        let jsonString = String(jsonSubstring)
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Invalid JSON in WEBVIEW_DATA")
            return
        }

        // placement should come from survey.projectOverwrites (center), and darkOverlay true
        XCTAssertEqual(object["placement"] as? String, "center")
        XCTAssertEqual(object["darkOverlay"] as? Bool, true)
    }
}
