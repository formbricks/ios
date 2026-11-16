import WebKit
import XCTest

@testable import FormbricksSDK

/// `WKScriptMessage` cannot be constructed with a payload, but `body` is overridable, so the
/// real `JsMessageHandler` can be driven end to end without a live WebView.
final class FakeScriptMessage: WKScriptMessage {
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

    override func postUser(
        id: String, attributes: [String: AttributeValue]?,
        completion: @escaping (ResultType<PostUserRequest.Response>) -> Void
    ) {
        postUserCallCount += 1
        super.postUser(id: id, attributes: attributes, completion: completion)
    }
}

final class SurveyInteractionRefreshTests: XCTestCase {

    private let userDefaultsKeys = [
        "userIdKey", "contactIdKey", "segmentsKey",
        "displaysKey", "responsesKey", "lastDisplayedAtKey", "expiresAtKey",
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
        for key in userDefaultsKeys { UserDefaults.standard.removeObject(forKey: key) }
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
        let decoded = try decodeSurvey(
            #"""
            {"id":"survey-a","interactionRefresh":{"onDisplay":true,"onResponse":false,"onFinished":true}}
            """#)
        XCTAssertEqual(
            decoded.interactionRefresh, InteractionRefresh(onDisplay: true, onResponse: false, onFinished: true))
    }

    /// A partial object must not fail the decode — otherwise one malformed survey blanks out
    /// the whole workspace payload and the user sees no surveys at all.
    func testPartialInteractionRefreshDefaultsMissingKeysToFalse() throws {
        let decoded = try decodeSurvey(#"{"id":"survey-a","interactionRefresh":{"onDisplay":true}}"#)
        XCTAssertEqual(decoded.interactionRefresh, InteractionRefresh(onDisplay: true))
    }

    func testUnknownKeyInsideInteractionRefreshIsIgnored() throws {
        let decoded = try decodeSurvey(
            #"""
            {"id":"survey-a","interactionRefresh":{"onDisplay":true,"onSomethingNew":true}}
            """#)
        XCTAssertEqual(decoded.interactionRefresh?.onDisplay, true)
    }

    /// The server attaches an all-false object to every survey in an interaction-targeting
    /// workspace, so this is a real payload and must be distinguishable from absent.
    func testAllFalseInteractionRefreshIsPresentButNeverRefreshes() throws {
        let decoded = try decodeSurvey(
            #"""
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
        Formbricks.setup(
            with: FormbricksConfig.Builder(appUrl: "https://example.com", workspaceId: "workspaceId")
                .service(MockFormbricksService())
                .build())

        guard let url = Bundle.module.url(forResource: "Environment", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
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

        flushQueuedUpdates(of: userManager)
        XCTAssertEqual(service.postUserCallCount, 0)
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

        // Anything the gate let through would be sent by this flush.
        flushQueuedUpdates(of: userManager)
        XCTAssertEqual(service.postUserCallCount, 0)
    }

    func testMatchingFlagTriggersExactlyOneSync() {
        let service = CountingMockService()
        let userManager = UserManager(service: service)
        UserDefaults.standard.set("user-1", forKey: "userIdKey")

        userManager.refreshSegmentsAfterInteraction(
            survey: survey(refresh: InteractionRefresh(onDisplay: true)),
            source: .onDisplay
        )

        flushQueuedUpdates(of: userManager)
        XCTAssertEqual(service.postUserCallCount, 1)
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

        flushQueuedUpdates(of: userManager)
        XCTAssertEqual(service.postUserCallCount, 1)
    }

    // MARK: - UpdateQueue in-flight handling

    /// A nudge that lands mid-sync must be deferred and then replayed — not dropped. The
    /// in-flight request was built before that interaction, so its response cannot reflect it.
    func testRefreshDuringAnInFlightSyncIsDeferredThenReplayed() {
        let mockUserManager = MockUserManager()
        let queue = UpdateQueue(userManager: mockUserManager)
        defer { queue.cleanup() }

        queue.requestUserStateRefresh(userId: "user-1")
        queue.fireScheduledCommit()
        // MockUserManager never reports completion, so the queue is still "in flight".
        XCTAssertEqual(mockUserManager.syncCallCount, 1)

        queue.requestUserStateRefresh(userId: "user-1")
        XCTAssertFalse(
            queue.hasScheduledCommit,
            "A nudge during an in-flight sync must not start a second request"
        )

        // Completing the sync must replay the deferred nudge on its own — without any
        // further interaction.
        queue.syncDidFinish()
        XCTAssertTrue(queue.hasScheduledCommit, "The deferred refresh must be replayed once the sync finishes")
        queue.fireScheduledCommit()
        XCTAssertEqual(mockUserManager.syncCallCount, 2)
    }

    /// Only one deferred refresh is kept, so a long sync with many interactions behind it
    /// still costs a single follow-up request.
    func testMultipleDeferredRefreshesCollapseIntoOneReplay() {
        let mockUserManager = MockUserManager()
        let queue = UpdateQueue(userManager: mockUserManager)
        defer { queue.cleanup() }

        queue.requestUserStateRefresh(userId: "user-1")
        queue.fireScheduledCommit()
        XCTAssertEqual(mockUserManager.syncCallCount, 1)

        queue.requestUserStateRefresh(userId: "user-1")
        queue.requestUserStateRefresh(userId: "user-1")
        queue.requestUserStateRefresh(userId: "user-1")

        queue.syncDidFinish()
        queue.fireScheduledCommit()
        XCTAssertEqual(mockUserManager.syncCallCount, 2)
        XCTAssertFalse(queue.hasScheduledCommit, "Only one replay may be queued")
    }

    /// A commit with no user id must not leave the in-flight flag stuck, or every later
    /// refresh nudge would be swallowed for the lifetime of the queue.
    func testAnonymousCommitDoesNotWedgeTheQueue() {
        let mockUserManager = MockUserManager()
        let queue = UpdateQueue(userManager: mockUserManager)
        defer { queue.cleanup() }

        // No user id anywhere: commit bails out early.
        queue.set(attributes: ["foo": "bar"])
        queue.fireScheduledCommit()
        XCTAssertEqual(mockUserManager.syncCallCount, 0)

        // A stuck in-flight flag would defer this nudge instead of scheduling it.
        queue.requestUserStateRefresh(userId: "user-1")
        XCTAssertTrue(queue.hasScheduledCommit, "The anonymous commit wedged the queue")
        queue.fireScheduledCommit()
        XCTAssertEqual(mockUserManager.syncCallCount, 1)
    }

    // MARK: - End-to-end wiring: JS event -> SurveyManager -> UserManager -> queue

    /// Drives the real `JsMessageHandler` with a real `WKScriptMessage`, so the whole delivery
    /// path is covered — not just the pieces. Without this, the `.onFinished` switch case can be
    /// replaced with `break` and every other test still passes.
    private func setUpSdkWithFixture(_ service: FormbricksServiceProtocol, userId: String? = "user-1") -> String {
        if let userId = userId {
            UserDefaults.standard.set(userId, forKey: "userIdKey")
        }
        Formbricks.setup(
            with: FormbricksConfig.Builder(appUrl: "https://example.com", workspaceId: "workspaceId")
                .service(service)
                .build())
        return "cm6ovw6j7000gsf0kduf4oo4i"  // the fixture survey, which carries interactionRefresh
    }

    /// Sends whatever the update queue holds now, instead of sleeping past the debounce: a stalled
    /// simulator lets a sleep finish before the debounce fires. The mock service answers
    /// synchronously, so the request has been made by the time this returns.
    private func flushQueuedUpdates(of userManager: UserManager?, file: StaticString = #filePath, line: UInt = #line) {
        guard let userManager = userManager else {
            XCTFail("The SDK has no user manager", file: file, line: line)
            return
        }
        userManager.waitForPendingUpdates { _ in }
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

        flushQueuedUpdates(of: Formbricks.userManager)
        XCTAssertEqual(service.postUserCallCount - baseline, 1)
    }

    func testDisplayEventReachesTheUserStateRefresh() {
        let service = CountingMockService()
        let surveyId = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount

        send("onDisplayCreated", to: JsMessageHandler(surveyId: surveyId))

        flushQueuedUpdates(of: Formbricks.userManager)
        XCTAssertEqual(service.postUserCallCount - baseline, 1)
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
        // The sync completes inside the flush, so the in-flight lock is released; only the
        // handler's own guard can suppress the second event now.
        flushQueuedUpdates(of: Formbricks.userManager)
        XCTAssertEqual(service.postUserCallCount - baseline, 1)

        send("onFinished", to: handler)
        flushQueuedUpdates(of: Formbricks.userManager)
        XCTAssertEqual(service.postUserCallCount - baseline, 1)
    }

    /// A fresh handler means a fresh showing, so it is allowed to refresh again.
    func testNewShowingCanRefreshAgain() {
        let service = CountingMockService()
        let surveyId = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount

        send("onFinished", to: JsMessageHandler(surveyId: surveyId))
        flushQueuedUpdates(of: Formbricks.userManager)

        send("onFinished", to: JsMessageHandler(surveyId: surveyId))
        flushQueuedUpdates(of: Formbricks.userManager)

        XCTAssertEqual(service.postUserCallCount - baseline, 2)
    }

    /// The survey id must actually be matched. If the lookup degraded to "just take the first
    /// survey", an unknown id would wrongly consult another survey's flags.
    func testUnknownSurveyIdDoesNotRefresh() {
        let service = CountingMockService()
        _ = setUpSdkWithFixture(service)
        let baseline = service.postUserCallCount

        Formbricks.surveyManager?.onSurveyInteraction(surveyId: "no-such-survey", source: .onFinished)

        flushQueuedUpdates(of: Formbricks.userManager)
        XCTAssertEqual(service.postUserCallCount - baseline, 0)
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
    ///
    /// It checks where the timer lives instead of waiting for it to fire: a timer on that pooled
    /// thread's run loop is the bug, and a wait for it to fire only tells the bug apart from a
    /// stalled simulator by how long it takes.
    func testSyncTimerFiresWhenScheduledFromABackgroundCompletion() throws {
        let service = BackgroundCompletionMockService()
        let userManager = UserManager(service: service)

        syncAndWaitForTheNextSyncToBeScheduled(userManager, service: service)

        let timer = try XCTUnwrap(userManager.syncTimer)
        XCTAssertTrue(timer.isValid)
        XCTAssertTrue(
            CFRunLoopContainsTimer(CFRunLoopGetMain(), unsafeBitCast(timer, to: CFRunLoopTimer.self), .commonModes),
            "The sync timer must be on the main run loop; any other thread's run loop never runs"
        )

        // And when it fires, it re-syncs.
        let resynced = expectation(description: "the timer re-synced")
        service.onCompletionDelivered = { count in
            if count == 2 { DispatchQueue.main.async { resynced.fulfill() } }
        }
        timer.fire()
        wait(for: [resynced], timeout: eventTimeout)
        XCTAssertEqual(service.postUserCallCount, 2)
    }

    /// A failed sync must still leave a timer armed. Otherwise one transient network error ends
    /// the refresh cycle for the rest of the process — the timer that fired is spent, and
    /// `startSyncTimer()` is only reached from a successful sync.
    func testFailedSyncReArmsTheTimer() {
        let service = MockFormbricksService()
        service.isErrorResponseNeeded = true
        let userManager = UserManager(service: service)
        UserDefaults.standard.set("user-1", forKey: "userIdKey")

        userManager.syncUser(withId: "user-1")

        // The retry is armed on the main queue; a hop queued after it runs strictly later.
        let exp = expectation(description: "a retry is armed after the failure")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: eventTimeout)

        XCTAssertNotNil(userManager.syncTimer, "A failed sync must leave a retry scheduled")
        XCTAssertEqual(userManager.syncTimer?.isValid, true)
    }

    /// The retry backs off rather than hammering at the minimum sync interval, so a sustained
    /// outage doesn't turn into a fixed-rate request stream.
    func testFailureRetryBacksOffFurtherThanTheMinimumInterval() {
        XCTAssertGreaterThan(
            Double(Config.User.retryAfterFailureInMinutes) * 60.0,
            Config.User.minimumSyncIntervalInSeconds
        )
    }

    /// A device clock ahead of the server makes every `expiresAt` land in the past. Without
    /// the floor the timer would fire immediately, re-sync, and loop.
    func testSkewedClockDoesNotCauseASyncLoop() throws {

        let service = BackgroundCompletionMockService()
        service.expiresIn = -3600  // server expiry already an hour in the device's past
        let userManager = UserManager(service: service)

        syncAndWaitForTheNextSyncToBeScheduled(userManager, service: service)

        XCTAssertEqual(service.postUserCallCount, 1)
        let timer = try XCTUnwrap(userManager.syncTimer)
        XCTAssertTrue(timer.isValid)
        // Read off the timer rather than by waiting to see no second sync, so a stall cannot pass
        // or fail it. Unclamped, the fire date is the skewed expiry, an hour in the past.
        XCTAssertGreaterThan(
            timer.fireDate.timeIntervalSinceNow, Config.User.minimumSyncIntervalInSeconds / 2,
            "Clamp should hold the next sync off")
    }

    /// Syncs once and returns after the completion has armed the next sync. The completion
    /// arrives on a background queue and arms the timer with a main-queue hop; the hop queued
    /// after it runs strictly later, so the timer is in place once it does.
    private func syncAndWaitForTheNextSyncToBeScheduled(
        _ userManager: UserManager, service: BackgroundCompletionMockService
    ) {
        let scheduled = expectation(description: "the sync landed and armed the next one")
        service.onCompletionDelivered = { _ in DispatchQueue.main.async { scheduled.fulfill() } }
        userManager.syncUser(withId: "user-1")
        wait(for: [scheduled], timeout: eventTimeout)
    }
}

/// Delivers completions on a background queue, the way `APIClient` does via URLSession's
/// delegate queue, and returns a user state whose expiry is controllable. Used to prove the
/// sync timer is not scheduled onto a dead run loop.
private final class BackgroundCompletionMockService: MockFormbricksService {
    var postUserCallCount = 0
    /// Seconds from now for the returned `expiresAt`. Negative simulates clock skew.
    var expiresIn: TimeInterval = 3600
    /// Called on the background queue once `completion` has returned, with the request's number.
    var onCompletionDelivered: ((Int) -> Void)?

    override func postUser(
        id: String, attributes: [String: AttributeValue]?,
        completion: @escaping (ResultType<PostUserRequest.Response>) -> Void
    ) {
        postUserCallCount += 1

        let expiresAt = DateFormatter.isoFormatter.string(from: Date().addingTimeInterval(expiresIn))
        let json = """
            {"data":{"state":{"data":{"contactId":"contact-1","displays":[],"lastDisplayAt":null,"responses":[],"segments":["segment-1"],"userId":"\(id)"},"expiresAt":"\(expiresAt)"}}}
            """

        let count = postUserCallCount
        let t0 = Date()
        func dbg(_ m: String) { print("[DEBUG-q7f3] #\(count) +\(String(format: "%.2f", Date().timeIntervalSince(t0)))s \(m)") }
        dbg("enqueue on global(default)")
        Thread { dbg("probe: dedicated Thread ran") }.start()
        Thread {
            _ = DateFormatter.isoFormatter.date(from: expiresAt)
            dbg("probe: ICU parse on dedicated Thread done")
        }.start()
        Thread {
            _ = try? JSONDecoder.iso8601Full.decode(PostUserRequest.Response.self, from: Data(json.utf8))
            dbg("probe: shared iso8601Full decode on dedicated Thread done")
        }.start()
        DispatchQueue.global(qos: .userInitiated).async { dbg("probe: global(userInitiated) ran") }
        DispatchQueue.global(qos: .utility).async { dbg("probe: global(utility) ran") }
        DispatchQueue.global().async { dbg("probe: global(default) ran") }
        DispatchQueue(label: "debug.serial").async { dbg("probe: private serial queue ran") }
        DispatchQueue.global().async { [onCompletionDelivered] in
            dbg("block started")
            do {
                let response = try JSONDecoder.iso8601Full.decode(PostUserRequest.Response.self, from: Data(json.utf8))
                dbg("decoded")
                completion(.success(response))
                dbg("completion returned")
            } catch {
                completion(.failure(error))
            }
            onCompletionDelivered?(count)
        }
    }
}
