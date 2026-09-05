import XCTest
@testable import FormbricksSDK

final class MobileCoreRuntimeTests: XCTestCase {

    /// A minimal stand-in for the server-delivered bundle, speaking bridge protocol v1.
    /// Echoes enough of the payload back to prove state crosses the bridge intact.
    private let stubBrain = """
    globalThis.formbricksMobileCore = {
      protocolVersion: 1,
      selectSurvey: function (payload) {
        var surveys = (payload.workspaceState.data && payload.workspaceState.data.data.surveys) || [];
        var alreadyDisplayed = (payload.userState.displays || []).length > 0;
        if (surveys.length === 0 || alreadyDisplayed) {
          return { v: 1, shouldDisplay: false, surveyId: null, delaySeconds: null, languageCode: null, reason: "stub: nothing to show" };
        }
        return {
          v: 1,
          shouldDisplay: true,
          surveyId: surveys[0].id,
          delaySeconds: 2,
          languageCode: payload.language,
          reason: "stub: action=" + payload.action + " userId=" + payload.userState.userId
        };
      }
    };
    """

    private let workspaceStateJSON = """
    { "data": { "data": { "surveys": [ { "id": "survey_123" } ] } } }
    """

    func testRuntimeInitializesWithValidBundle() {
        XCTAssertNotNil(MobileCoreRuntime(bundleSource: stubBrain))
    }

    func testRuntimeRejectsBundleWithoutGlobal() {
        XCTAssertNil(MobileCoreRuntime(bundleSource: "var x = 1;"))
    }

    func testRuntimeRejectsBundleWithWrongProtocolVersion() {
        let futureBrain = stubBrain.replacingOccurrences(of: "protocolVersion: 1", with: "protocolVersion: 2")
        XCTAssertNil(MobileCoreRuntime(bundleSource: futureBrain))
    }

    func testRuntimeRejectsBundleThatFailsToEvaluate() {
        XCTAssertNil(MobileCoreRuntime(bundleSource: "this is not javascript {{{"))
    }

    func testSelectSurveyReturnsDecisionAndPassesStateThrough() throws {
        let runtime = try XCTUnwrap(MobileCoreRuntime(bundleSource: stubBrain))
        let userState = MobileCoreUserState(userId: "user_1", segments: [], displays: [], responses: [], lastDisplayedAtMs: nil)

        let decision = try XCTUnwrap(runtime.selectSurvey(
            action: "button_clicked",
            workspaceStateJSON: workspaceStateJSON,
            userState: userState,
            language: "de"
        ))

        XCTAssertTrue(decision.shouldDisplay)
        XCTAssertEqual(decision.surveyId, "survey_123")
        XCTAssertEqual(decision.delaySeconds, 2)
        XCTAssertEqual(decision.languageCode, "de")
        XCTAssertEqual(decision.reason, "stub: action=button_clicked userId=user_1")
    }

    func testSelectSurveyRespectsUserStateAcrossBridge() throws {
        let runtime = try XCTUnwrap(MobileCoreRuntime(bundleSource: stubBrain))
        let userState = MobileCoreUserState(
            userId: "user_1",
            segments: [],
            displays: [Display(surveyId: "survey_123", createdAt: "2026-07-02T00:00:00Z")],
            responses: [],
            lastDisplayedAtMs: nil
        )

        let decision = try XCTUnwrap(runtime.selectSurvey(
            action: "button_clicked",
            workspaceStateJSON: workspaceStateJSON,
            userState: userState,
            language: "default"
        ))

        XCTAssertFalse(decision.shouldDisplay)
        XCTAssertNil(decision.surveyId)
    }

    func testSelectSurveyReturnsNilWhenBrainThrows() throws {
        let throwingBrain = """
        globalThis.formbricksMobileCore = {
          protocolVersion: 1,
          selectSurvey: function () { throw new Error("boom"); }
        };
        """
        let runtime = try XCTUnwrap(MobileCoreRuntime(bundleSource: throwingBrain))
        let userState = MobileCoreUserState(userId: nil, segments: nil, displays: nil, responses: nil, lastDisplayedAtMs: nil)

        XCTAssertNil(runtime.selectSurvey(
            action: "button_clicked",
            workspaceStateJSON: workspaceStateJSON,
            userState: userState,
            language: "default"
        ))
    }
}
