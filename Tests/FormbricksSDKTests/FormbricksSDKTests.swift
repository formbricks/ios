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
        
        // In headless test environment, presentation fails (no key window), so flag should reset to false
        XCTAssertFalse(Formbricks.surveyManager?.isShowingSurvey ?? true)
        
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
        
        // In headless test environment, presentation fails (no key window), so flag should reset to false
        XCTAssertFalse(Formbricks.surveyManager?.isShowingSurvey ?? true)
        
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

    // MARK: - UserManager syncUser errors/messages tests

    func testSyncUserLogsErrors() {
        let errorsMockService = MockFormbricksService()
        errorsMockService.userMockResponse = .userWithErrors

        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(errorsMockService)
            .build()
        Formbricks.setup(with: config)

        // Refresh environment first
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        let envExpectation = expectation(description: "Env loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { envExpectation.fulfill() }
        wait(for: [envExpectation])

        // Set userId to trigger syncUser which uses the mock with errors
        Formbricks.setUserId(userId)

        let syncExpectation = expectation(description: "User synced with errors")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            syncExpectation.fulfill()
        }
        wait(for: [syncExpectation], timeout: 3.0)

        // Verify the user was still synced successfully despite errors
        XCTAssertEqual(Formbricks.userManager?.userId, userId, "User ID should be set even when response has errors")
        XCTAssertNotNil(Formbricks.userManager?.syncTimer, "Sync timer should still be set")
    }

    func testSyncUserLogsMessages() {
        let messagesMockService = MockFormbricksService()
        messagesMockService.userMockResponse = .userWithMessages

        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(messagesMockService)
            .build()
        Formbricks.setup(with: config)

        // Refresh environment first
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        let envExpectation = expectation(description: "Env loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { envExpectation.fulfill() }
        wait(for: [envExpectation])

        // Set userId to trigger syncUser which uses the mock with messages
        Formbricks.setUserId(userId)

        let syncExpectation = expectation(description: "User synced with messages")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            syncExpectation.fulfill()
        }
        wait(for: [syncExpectation], timeout: 3.0)

        // Verify the user was synced successfully
        XCTAssertEqual(Formbricks.userManager?.userId, userId, "User ID should be set when response has messages")
        XCTAssertNotNil(Formbricks.userManager?.syncTimer, "Sync timer should still be set")
    }

    func testSyncUserLogsErrorsAndMessages() {
        let bothMockService = MockFormbricksService()
        bothMockService.userMockResponse = .userWithErrorsAndMessages

        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(bothMockService)
            .build()
        Formbricks.setup(with: config)

        // Refresh environment first
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        let envExpectation = expectation(description: "Env loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { envExpectation.fulfill() }
        wait(for: [envExpectation])

        // Set userId to trigger syncUser which uses the mock with both errors and messages
        Formbricks.setUserId(userId)

        let syncExpectation = expectation(description: "User synced with errors and messages")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            syncExpectation.fulfill()
        }
        wait(for: [syncExpectation], timeout: 3.0)

        // Verify the user was synced successfully despite having both errors and messages
        XCTAssertEqual(Formbricks.userManager?.userId, userId, "User ID should be set when response has both errors and messages")
        XCTAssertNotNil(Formbricks.userManager?.syncTimer, "Sync timer should still be set")
    }

    // MARK: - setUserId override behavior tests

    func testSetUserIdSameValueIsNoOp() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)

        // Refresh environment first
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        let envExpectation = expectation(description: "Env loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { envExpectation.fulfill() }
        wait(for: [envExpectation])

        // Set userId
        Formbricks.setUserId(userId)
        let setExpectation = expectation(description: "User set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { setExpectation.fulfill() }
        wait(for: [setExpectation], timeout: 3.0)

        XCTAssertEqual(Formbricks.userManager?.userId, userId)

        // Set the same userId again — should be a no-op, userId stays the same
        Formbricks.setUserId(userId)
        XCTAssertEqual(Formbricks.userManager?.userId, userId, "Same userId should remain set (no-op)")
    }

    func testSetUserIdDifferentValueOverridesPrevious() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)

        // Refresh environment first
        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        let envExpectation = expectation(description: "Env loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { envExpectation.fulfill() }
        wait(for: [envExpectation])

        // Set initial userId and wait for sync to complete
        Formbricks.setUserId(userId)
        let setExpectation = expectation(description: "First user set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { setExpectation.fulfill() }
        wait(for: [setExpectation], timeout: 3.0)

        XCTAssertEqual(Formbricks.userManager?.userId, userId)

        // Capture previous state to verify cleanup happens
        Formbricks.surveyManager?.onNewDisplay(surveyId: surveyID)
        XCTAssertEqual(Formbricks.userManager?.displays?.count, 1, "Should have 1 display before override")

        // Set a different userId — should clean up previous user state first
        let newUserId = "NEW-USER-ID-12345"
        Formbricks.setUserId(newUserId)

        // Immediately after setUserId, the previous user state should be cleaned up
        // (logout was called synchronously before queueing the new userId)
        XCTAssertNil(Formbricks.userManager?.userId, "Previous userId should be cleared by logout")
        XCTAssertNil(Formbricks.userManager?.displays, "Previous displays should be cleared by logout")
        XCTAssertNil(Formbricks.userManager?.responses, "Previous responses should be cleared by logout")
        XCTAssertNil(Formbricks.userManager?.segments, "Previous segments should be cleared by logout")
    }

    func testLogoutWithoutUserIdDoesNotError() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)

        // Logout without ever setting a userId — should not crash or error
        XCTAssertNil(Formbricks.userManager?.userId)
        Formbricks.logout()
        XCTAssertNil(Formbricks.userManager?.userId, "userId should remain nil after logout")
    }

    // MARK: - setAttribute overload tests

    func testSetAttributeDouble() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)

        // Should not crash; exercises the Double overload
        Formbricks.setAttribute(42.0, forKey: "age")
    }

    func testSetAttributeDate() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)

        // Should not crash; exercises the Date overload
        Formbricks.setAttribute(Date(), forKey: "signupDate")
    }

    // MARK: - ConfigBuilder coverage tests

    func testConfigBuilderStringAttributes() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .set(stringAttributes: ["key1": "val1", "key2": "val2"])
            .build()

        XCTAssertEqual(config.attributes?["key1"], "val1")
        XCTAssertEqual(config.attributes?["key2"], "val2")
    }

    func testConfigBuilderAddAttribute() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .add(attribute: "hello", forKey: "greeting")
            .build()

        XCTAssertEqual(config.attributes?["greeting"], "hello")
    }

    // MARK: - PresentSurveyManager tests

    func testPresentCompletesInHeadlessEnvironment() {
        // In a headless test environment there is no key window, so present() should
        // call the completion with false.
        let config = FormbricksConfig.Builder(appUrl: appUrl, environmentId: environmentId)
            .setLogLevel(.debug)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)

        Formbricks.surveyManager?.refreshEnvironmentIfNeeded(force: true)
        let loadExpectation = expectation(description: "Env loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { loadExpectation.fulfill() }
        wait(for: [loadExpectation])

        guard let env = Formbricks.surveyManager?.environmentResponse else {
            XCTFail("Missing environmentResponse")
            return
        }

        let manager = PresentSurveyManager()
        let presentExpectation = expectation(description: "Present completes")
        manager.present(environmentResponse: env, id: surveyID) { success in
            // No key window in headless tests → completion(false)
            XCTAssertFalse(success, "Presentation should fail in headless environment")
            presentExpectation.fulfill()
        }
        wait(for: [presentExpectation], timeout: 2.0)
    }

    // MARK: - WebView data tests

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

        // placement should come from survey.projectOverwrites (center), overlay should be "dark",
        // and clickOutside should be false (from survey.projectOverwrites.clickOutsideClose)
        XCTAssertEqual(object["placement"] as? String, "center")
        XCTAssertEqual(object["overlay"] as? String, "dark")
        XCTAssertEqual(object["clickOutside"] as? Bool, false)
    }
}
