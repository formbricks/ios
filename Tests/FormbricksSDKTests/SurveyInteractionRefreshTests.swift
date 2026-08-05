import XCTest
import WebKit
@testable import FormbricksSDK

/// `WKScriptMessage` cannot be constructed with a payload, but `body` is overridable, so the
/// real `JsMessageHandler` can be driven end to end without a live WebView.
private final class FakeScriptMessage: WKScriptMessage {
    private let payload: Any

    init(payload: Any) {
        self.payload = payload
        super.init()
    }

    override var body: Any { payload }
}

/// Counts `postUser` calls so the interaction gate can be asserted end to end.
private final class CountingMockService: MockFormbricksService {
    var postUserCallCount = 0

    override func postUser(id: String, attributes: [String: AttributeValue]?, completion: @escaping (ResultType<PostUserRequest.Response>) -> Void) {
        postUserCallCount += 1
        super.postUser(id: id, attributes: attributes, completion: completion)
    }
}

final class SurveyInteractionRefreshTests: XCTestCase {

    private let userDefaultsKeys = [
        "userIdKey", "contactIdKey", "segmentsKey",
        "displaysKey", "responsesKey", "lastDisplayedAtKey", "expiresAtKey"
    ]

    override func setUp() {
        super.setUp()
        Formbricks.cleanup()
        clearUserState()
    }

    override func tearDown() {
        Formbricks.cleanup()
        clearUserState()
        super.tearDown()
    }

    private func clearUserState() {
        userDefaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        // The cached workspace blob outlives `Formbricks.cleanup()` on purpose (real apps rely
        // on it across launches), and its fixture `expiresAt` is years out — so without this a
        // blob written by an earlier run is reused and never refetched.
        UserDefaults.standard.removeObject(forKey: SurveyManager.workspaceResponseObjectKey)
        UserDefaults.standard.removeObject(forKey: SurveyManager.legacyEnvironmentResponseObjectKey)
    }

    private func decodeSurvey(_ json: String) throws -> Survey {
        try JSONDecoder().decode(Survey.self, from: Data(json.utf8))
    }

    private func survey(id: String = "survey-a", refresh: InteractionRefresh?) -> Survey {
        Survey(
            id: id,
            triggers: nil,
            recontactDays: nil,
            displayLimit: nil,
            delay: nil,
            displayPercentage: nil,
            displayOption: .respondMultiple,
            segment: nil,
            styling: nil,
            languages: nil,
            projectOverwrites: nil,
            interactionRefresh: refresh
        )
    }

    // MARK: - Decoding

    /// Workspaces without interaction targeting get no `interactionRefresh` at all.
    func testSurveyDecodesWithoutInteractionRefresh() throws {
        let decoded = try decodeSurvey(#"{"id":"survey-a"}"#)
        XCTAssertNil(decoded.interactionRefresh)
    }

    func testSurveyDecodesFullInteractionRefresh() throws {
        let decoded = try decodeSurvey(#"""
        {"id":"survey-a","interactionRefresh":{"onDisplay":true,"onResponse":false,"onFinished":true}}
        """#)
        XCTAssertEqual(decoded.interactionRefresh, InteractionRefresh(onDisplay: true, onResponse: false, onFinished: true))
    }

    /// A partial object must not fail the decode — otherwise one malformed survey blanks out
    /// the whole workspace payload and the user sees no surveys at all.
    func testPartialInteractionRefreshDefaultsMissingKeysToFalse() throws {
        let decoded = try decodeSurvey(#"{"id":"survey-a","interactionRefresh":{"onDisplay":true}}"#)
        XCTAssertEqual(decoded.interactionRefresh, InteractionRefresh(onDisplay: true))
    }

    func testUnknownKeyInsideInteractionRefreshIsIgnored() throws {
        let decoded = try decodeSurvey(#"""
        {"id":"survey-a","interactionRefresh":{"onDisplay":true,"onSomethingNew":true}}
        """#)
        XCTAssertEqual(decoded.interactionRefresh?.onDisplay, true)
    }

    /// The server attaches an all-false object to every survey in an interaction-targeting
    /// workspace, so this is a real payload and must be distinguishable from absent.
    func testAllFalseInteractionRefreshIsPresentButNeverRefreshes() throws {
        let decoded = try decodeSurvey(#"""
        {"id":"survey-a","interactionRefresh":{"onDisplay":false,"onResponse":false,"onFinished":false}}
        """#)
        XCTAssertNotNil(decoded.interactionRefresh)
        for source in [InteractionSource.onDisplay, .onResponse, .onFinished] {
            XCTAssertFalse(decoded.interactionRefresh?.shouldRefresh(on: source) ?? true)
        }
    }

    /// The cached workspace blob is re-encoded from the typed model, so the field has to
    /// survive a round trip or it is silently lost until the cache expires.
    func testInteractionRefreshSurvivesEncodeDecodeRoundTrip() throws {
        let original = survey(refresh: InteractionRefresh(onDisplay: true, onResponse: true, onFinished: true))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Survey.self, from: data)
        XCTAssertEqual(decoded.interactionRefresh, original.interactionRefresh)
    }

    func testShouldRefreshMapsEachSourceToItsOwnFlag() {
        let refresh = InteractionRefresh(onDisplay: true, onResponse: false, onFinished: true)
        XCTAssertTrue(refresh.shouldRefresh(on: .onDisplay))
        XCTAssertFalse(refresh.shouldRefresh(on: .onResponse))
        XCTAssertTrue(refresh.shouldRefresh(on: .onFinished))
    }

    // MARK: - JS bridge

    func testEventTypeDecodesOnFinished() throws {
        let data = Data(#"{"event":"onFinished"}"#.utf8)
        let message = try JSONDecoder().decode(JsMessageData.self, from: data)
        XCTAssertEqual(message.event, .onFinished)
    }

    /// The event vocabulary stays closed: an unrecognised event must still fail to decode so
    /// it is logged rather than silently mapped onto a known case.
    func testUnknownEventStillFailsToDecode() {
        let data = Data(#"{"event":"onSomethingElse"}"#.utf8)
        XCTAssertNil(try? JSONDecoder().decode(JsMessageData.self, from: data))
    }

    func testHtmlTemplatePassesOnFinishedToRenderSurvey() throws {
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "https://example.com", workspaceId: "workspaceId")
            .service(MockFormbricksService())
            .build())

        guard let url = Bundle.module.url(forResource: "Environment", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return XCTFail("Missing Environment.json fixture")
        }
        let workspaceResponse = try JSONDecoder.iso8601Full.decode(GetWorkspaceRequest.Response.self, from: data)
        guard let surveyId = workspaceResponse.data.data.surveys?.first?.id else {
            return XCTFail("Fixture has no surveys")
        }

        let html = FormbricksViewModel(workspaceResponse: workspaceResponse, surveyId: surveyId).htmlString
        XCTAssertEqual(html?.contains(#"event: "onFinished""#), true)
        XCTAssertEqual(html?.contains("function onFinished()"), true)
        // Must be listed in the props object, not merely defined.
        XCTAssertEqual(html?.contains("onFinished,"), true)
    }

    // MARK: - The gate

    func testAnonymousUserNeverRefreshes() {
        let service = CountingMockService()
        let userManager = UserManager(service: service)

        userManager.refreshSegmentsAfterInteraction(
            survey: survey(refresh: InteractionRefresh(onDisplay: true)),
            source: .onDisplay
        )

        let exp = expectation(description: "no sync for anonymous user")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(service.postUserCallCount, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testGateBlocksWhenFieldAbsentOrFlagFalse() {
        let service = CountingMockService()
        let userManager = UserManager(service: service)
        UserDefaults.standard.set("user-1", forKey: "userIdKey")

        // Absent — workspace does not use interaction targeting.
        userManager.refreshSegmentsAfterInteraction(survey: survey(refresh: nil), source: .onDisplay)
        // Present but all false — no interaction filter references this survey.
        userManager.refreshSegmentsAfterInteraction(survey: survey(refresh: InteractionRefresh()), source: .onDisplay)
        // Present, but a different source than the one that fired.
        userManager.refreshSegmentsAfterInteraction(
            survey: survey(refresh: InteractionRefresh(onDisplay: true)),
            source: .onResponse
        )

        let exp = expectation(description: "gate blocks all three")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(service.postUserCallCount, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testMatchingFlagTriggersExactlyOneSync() {
        let service = CountingMockService()
        let userManager = UserManager(service: service)
        UserDefaults.standard.set("user-1", forKey: "userIdKey")

        userManager.refreshSegmentsAfterInteraction(
            survey: survey(refresh: InteractionRefresh(onDisplay: true)),
            source: .onDisplay
        )

        let exp = expectation(description: "one sync")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(service.postUserCallCount, 1)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    /// A display -> response -> finish burst must cost one request, not three.
    func testInteractionBurstCoalescesIntoOneSync() {
        let service = CountingMockService()
        let userManager = UserManager(service: service)
        UserDefaults.standard.set("user-1", forKey: "userIdKey")

        let allOn = survey(refresh: InteractionRefresh(onDisplay: true, onResponse: true, onFinished: true))
        userManager.refreshSegmentsAfterInteraction(survey: allOn, source: .onDisplay)
        userManager.refreshSegmentsAfterInteraction(survey: allOn, source: .onResponse)
        userManager.refreshSegmentsAfterInteraction(survey: allOn, source: .onFinished)

        let exp = expectation(description: "burst coalesces")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            XCTAssertEqual(service.postUserCallCount, 1)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - UpdateQueue in-flight join

    func testRefreshIsDroppedWhileSyncIsInFlightAndResumesAfter() {
        let mockUserManager = MockUserManager()
        let queue = UpdateQueue(userManager: mockUserManager)
        defer { queue.cleanup() }

        queue.requestUserStateRefresh(userId: "user-1")

        let firstCommit = expectation(description: "first commit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // MockUserManager never reports completion, so the queue is still "in flight".
            XCTAssertEqual(mockUserManager.syncCallCount, 1)

            queue.requestUserStateRefresh(userId: "user-1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                XCTAssertEqual(mockUserManager.syncCallCount, 1, "Nudge during an in-flight sync must be dropped")

                queue.syncDidFinish()
                queue.requestUserStateRefresh(userId: "user-1")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    XCTAssertEqual(mockUserManager.syncCallCount, 2, "Nudge after completion must sync again")
                    firstCommit.fulfill()
                }
            }
        }
        wait(for: [firstCommit], timeout: 5.0)
    }

    /// A commit with no user id must not leave the in-flight flag stuck, or every later
    /// refresh nudge would be swallowed for the lifetime of the queue.
    func testAnonymousCommitDoesNotWedgeTheQueue() {
        let mockUserManager = MockUserManager()
        let queue = UpdateQueue(userManager: mockUserManager)
        defer { queue.cleanup() }

        // No user id anywhere: commit bails out early.
        queue.set(attributes: ["foo": "bar"])

        let exp = expectation(description: "queue still usable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(mockUserManager.syncCallCount, 0)
            queue.requestUserStateRefresh(userId: "user-1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                XCTAssertEqual(mockUserManager.syncCallCount, 1)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3.0)
    }

    // MARK: - End-to-end wiring: JS event -> SurveyManager -> UserManager -> queue

    /// Drives the real `JsMessageHandler` with a real `WKScriptMessage`, so the whole delivery
    /// path is covered — not just the pieces. Without this, the `.onFinished` switch case can be
    /// replaced with `break` and every other test still passes.
    private func setUpSdkWithFixture(_ service: FormbricksServiceProtocol, userId: String? = "user-1") -> String {
        if let userId = userId {
            UserDefaults.standard.set(userId, forKey: "userIdKey")
        }
        Formbricks.setup(with: FormbricksConfig.Builder(appUrl: "https://example.com", workspaceId: "workspaceId")
            .service(service)
            .build())
        return "cm6ovw6j7000gsf0kduf4oo4i" // the fixture survey, which carries interactionRefresh
    }

    private func send(_ event: String, to handler: JsMessageHandler) {
        handler.userContentController(
            WKUserContentController(),
            didReceive: FakeScriptMessage(payload: #"{"event":"\#(event)"}"#)
        )
    }

    func testOnFinishedEventReachesTheUserStateRefresh() {
        let service = CountingMockService()
        let surveyId = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount

        send("onFinished", to: JsMessageHandler(surveyId: surveyId))

        let exp = expectation(description: "onFinished triggers a refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            XCTAssertEqual(service.postUserCallCount - baseline, 1)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }

    func testDisplayEventReachesTheUserStateRefresh() {
        let service = CountingMockService()
        let surveyId = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount

        send("onDisplayCreated", to: JsMessageHandler(surveyId: surveyId))

        let exp = expectation(description: "onDisplayCreated triggers a refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            XCTAssertEqual(service.postUserCallCount - baseline, 1)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }

    /// The one-shot guard: the surveys library does not guard `onFinished`, and a self-hosted
    /// server may serve an older bundle, so a repeated event must not cost a second request
    /// once the first sync has already completed.
    func testRepeatedOnFinishedRefreshesOnlyOnceForTheSameShowing() {
        let service = CountingMockService()
        let surveyId = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount
        let handler = JsMessageHandler(surveyId: surveyId)

        send("onFinished", to: handler)

        let exp = expectation(description: "second onFinished is ignored")
        // Wait past the debounce and the sync so the in-flight lock is released; only the
        // handler's own guard can suppress the second event by then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            self.send("onFinished", to: handler)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                XCTAssertEqual(service.postUserCallCount - baseline, 1)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5.0)
    }

    /// A fresh handler means a fresh showing, so it is allowed to refresh again.
    func testNewShowingCanRefreshAgain() {
        let service = CountingMockService()
        let surveyId = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount

        send("onFinished", to: JsMessageHandler(surveyId: surveyId))

        let exp = expectation(description: "second showing refreshes again")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            self.send("onFinished", to: JsMessageHandler(surveyId: surveyId))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                XCTAssertEqual(service.postUserCallCount - baseline, 2)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5.0)
    }

    /// The survey id must actually be matched. If the lookup degraded to "just take the first
    /// survey", an unknown id would wrongly consult another survey's flags.
    func testUnknownSurveyIdDoesNotRefresh() {
        let service = CountingMockService()
        _ = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount

        Formbricks.surveyManager?.onSurveyInteraction(surveyId: "no-such-survey", source: .onFinished)

        let exp = expectation(description: "unknown survey id is a no-op")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            XCTAssertEqual(service.postUserCallCount - baseline, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }

    /// Proves the fixture — i.e. a real server-shaped payload — decodes the gate correctly.
    func testFixtureSurveyCarriesInteractionRefresh() {
        let service = CountingMockService()
        let surveyId = setUpSdkWithFixture(service)

        let survey = Formbricks.surveyManager?.workspaceResponse?.data.data.surveys?
            .first(where: { $0.id == surveyId })
        XCTAssertEqual(survey?.interactionRefresh?.onDisplay, true)
        XCTAssertEqual(survey?.interactionRefresh?.onResponse, true)
        XCTAssertEqual(survey?.interactionRefresh?.onFinished, true)
    }

    // MARK: - Sync timer

    /// The bug this covers: `startSyncTimer` ran inside `syncUser`'s completion, which
    /// `APIClient` delivers on URLSession's background delegate queue. `Timer.scheduledTimer`
    /// installs on `RunLoop.current`, and that pooled thread has no run loop, so the timer was
    /// created and never fired. This mock reproduces the same threading, so the second
    /// `postUser` only happens if the timer is genuinely live.
    func testSyncTimerFiresWhenScheduledFromABackgroundCompletion() {
        let originalFloor = Config.User.minimumSyncIntervalInSeconds
        Config.User.minimumSyncIntervalInSeconds = 0.2
        defer { Config.User.minimumSyncIntervalInSeconds = originalFloor }

        let service = BackgroundCompletionMockService()
        service.expiresIn = 0.3
        let userManager = UserManager(service: service)

        let exp = expectation(description: "timer fires and re-syncs")
        service.onPostUser = { count in
            if count == 2 { exp.fulfill() }
        }

        userManager.syncUser(withId: "user-1")

        wait(for: [exp], timeout: 5.0)
        XCTAssertGreaterThanOrEqual(service.postUserCallCount, 2)
    }

    /// A device clock ahead of the server makes every `expiresAt` land in the past. Without
    /// the floor the timer would fire immediately, re-sync, and loop.
    func testSkewedClockDoesNotCauseASyncLoop() {
        let originalFloor = Config.User.minimumSyncIntervalInSeconds
        Config.User.minimumSyncIntervalInSeconds = 10
        defer { Config.User.minimumSyncIntervalInSeconds = originalFloor }

        let service = BackgroundCompletionMockService()
        service.expiresIn = -3600 // server expiry already an hour in the device's past
        let userManager = UserManager(service: service)

        userManager.syncUser(withId: "user-1")

        let exp = expectation(description: "no loop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(service.postUserCallCount, 1, "Clamp should hold the next sync off")
            XCTAssertEqual(userManager.syncTimer?.isValid, true)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }
}

/// Delivers completions on a background queue, the way `APIClient` does via URLSession's
/// delegate queue, and returns a user state whose expiry is controllable. Used to prove the
/// sync timer is not scheduled onto a dead run loop.
private final class BackgroundCompletionMockService: MockFormbricksService {
    var postUserCallCount = 0
    /// Seconds from now for the returned `expiresAt`. Negative simulates clock skew.
    var expiresIn: TimeInterval = 0.3
    var onPostUser: ((Int) -> Void)?

    override func postUser(id: String, attributes: [String: AttributeValue]?, completion: @escaping (ResultType<PostUserRequest.Response>) -> Void) {
        postUserCallCount += 1
        onPostUser?(postUserCallCount)

        let expiresAt = DateFormatter.isoFormatter.string(from: Date().addingTimeInterval(expiresIn))
        let json = """
        {"data":{"state":{"data":{"contactId":"contact-1","displays":[],"lastDisplayAt":null,"responses":[],"segments":["segment-1"],"userId":"\(id)"},"expiresAt":"\(expiresAt)"}}}
        """

        DispatchQueue.global().async {
            do {
                let response = try JSONDecoder.iso8601Full.decode(PostUserRequest.Response.self, from: Data(json.utf8))
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
