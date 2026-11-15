import XCTest

/// The SDK golden journey against a real Formbricks server (see e2e/ios/run-journey.sh):
/// set up → setUserId → setAttribute plan=pro → track qa-action → the targeted survey appears →
/// NPS 9 → Next → type the feedback → Finish → "Thanks!" → close.
/// e2e/server/assert-response.sh then checks the stored response through the V1 API.
///
/// Inputs come from the test runner's environment (`TEST_RUNNER_<name>` on the xcodebuild command
/// line): E2E_APP_URL, E2E_USER_ID, E2E_FEEDBACK, and optionally E2E_WORKSPACE_ID.
final class GoldenJourneyUITests: XCTestCase {
    private static let qaWorkspaceId = "clsdkqaws00000000000000001"
    /// WebKit's first process launch on a cold CI simulator alone can take 20 s or more.
    private static let surveyTimeout: TimeInterval = 60
    private static let elementTimeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGoldenJourney() throws {
        let environment = ProcessInfo.processInfo.environment
        let appUrl = try required("E2E_APP_URL", in: environment)
        let userId = try required("E2E_USER_ID", in: environment)
        let feedback = try required("E2E_FEEDBACK", in: environment)

        let app = XCUIApplication()
        app.launchEnvironment = [
            "FORMBRICKS_APP_URL": appUrl,
            "FORMBRICKS_WORKSPACE_ID": environment["E2E_WORKSPACE_ID"] ?? Self.qaWorkspaceId,
            "FORMBRICKS_USER_ID": userId,
            "FORMBRICKS_ATTRIBUTE_KEY": "plan",
            "FORMBRICKS_ATTRIBUTE_VALUE": "pro",
            "FORMBRICKS_ACTION": "qa-action",
        ]
        app.launch()

        try tap(app.buttons["setUserIdButton"], in: app)
        try tap(app.buttons["setAttributeButton"], in: app)

        let survey = try trackUntilTheSurveyAppears(in: app)

        try tap(
            firstExisting(
                [
                    survey.radioButtons["Rate 9 out of 10"],
                    survey.buttons["Rate 9 out of 10"],
                    survey.staticTexts["9"],
                ], in: app), in: app)
        try tap(survey.buttons["Next"], in: app)

        let answer = try firstExisting(
            [
                survey.textFields["Type your answer"],
                survey.textFields.firstMatch,
            ], in: app)
        try tap(answer, in: app)
        answer.typeText(feedback)
        try tap(survey.buttons["Finish"], in: app)

        // The ending card renders only after the server accepted the response.
        try waitFor(survey.staticTexts["Thanks!"], in: app)
        try tap(survey.buttons["Close survey"], in: app)
        XCTAssertTrue(survey.waitForNonExistence(timeout: Self.elementTimeout), "the survey did not close")
    }

    /// Taps Track until the survey WebView shows. An early tap can land before the SDK fetched the
    /// workspace or synced the user's attributes, and then no survey matches yet.
    private func trackUntilTheSurveyAppears(in app: XCUIApplication) throws -> XCUIElement {
        let survey = app.webViews.firstMatch
        let deadline = Date().addingTimeInterval(180)
        repeat {
            try tap(app.buttons["trackButton"], in: app)
            if survey.waitForExistence(timeout: 15) {
                return survey
            }
        } while Date() < deadline
        attachTree(of: app)
        XCTFail("No survey appeared within 180s of tracking qa-action")
        throw JourneyError.notFound("survey web view")
    }

    private func required(_ name: String, in environment: [String: String]) throws -> String {
        guard let value = environment[name], !value.isEmpty else {
            XCTFail("Set \(name), for example TEST_RUNNER_\(name)=... on the xcodebuild command line")
            throw JourneyError.missingInput(name)
        }
        return value
    }

    private func waitFor(_ element: XCUIElement, in app: XCUIApplication) throws {
        guard element.waitForExistence(timeout: Self.elementTimeout) else {
            attachTree(of: app)
            XCTFail("Not found within \(Self.elementTimeout)s: \(element)")
            throw JourneyError.notFound(element.description)
        }
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        try waitFor(element, in: app)
        element.tap()
    }

    /// The first of `candidates` to appear. WKWebView maps some HTML roles differently across iOS
    /// versions (a radio input may surface as a radio button, a button or only its text).
    private func firstExisting(_ candidates: [XCUIElement], in app: XCUIApplication) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(Self.elementTimeout)
        repeat {
            if let found = candidates.first(where: \.exists) {
                return found
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        attachTree(of: app)
        XCTFail("None found within \(Self.elementTimeout)s: \(candidates.map(\.description))")
        throw JourneyError.notFound(candidates.map(\.description).joined(separator: ", "))
    }

    /// The accessibility tree, for working out a selector from the xcresult when one fails.
    private func attachTree(of app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "Accessibility tree"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum JourneyError: Error {
    case missingInput(String)
    case notFound(String)
}
