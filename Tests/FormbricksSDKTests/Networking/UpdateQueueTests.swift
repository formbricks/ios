import XCTest

@testable import FormbricksSDK

class MockUserManager: UserManagerSyncable {
    var lastSyncedUserId: String?
    var lastSyncedAttributes: [String: AttributeValue]?
    var syncCallCount = 0
    /// Lets a test wait on the sync itself instead of guessing how long the debounce takes.
    var onSync: (() -> Void)?
    func syncUser(withId id: String, attributes: [String: AttributeValue]?) {
        lastSyncedUserId = id
        lastSyncedAttributes = attributes
        syncCallCount += 1
        onSync?()
    }
}

final class UpdateQueueTests: XCTestCase {
    var queue: UpdateQueue!
    var mockUserManager: MockUserManager!

    private var originalDebounce: TimeInterval = 0.5
    private var originalTimeout: TimeInterval = 5

    override func setUp() {
        super.setUp()
        mockUserManager = MockUserManager()
        queue = UpdateQueue(userManager: mockUserManager)
        originalDebounce = Config.User.updateDebounceIntervalInSeconds
        originalTimeout = Config.User.pendingUpdateTimeoutInSeconds
    }

    override func tearDown() {
        Config.User.updateDebounceIntervalInSeconds = originalDebounce
        Config.User.pendingUpdateTimeoutInSeconds = originalTimeout
        queue.cleanup()
        queue = nil
        mockUserManager = nil
        super.tearDown()
    }

    // MARK: - waitForPendingWork

    /// The common case: a host that is not identifying pays nothing for the wait.
    func testWaitForPendingWorkResolvesImmediatelyWhenNothingIsQueued() {
        let exp = expectation(description: "resolves without a sync")
        queue.waitForPendingWork { succeeded in
            XCTAssertTrue(succeeded)
            exp.fulfill()
        }
        wait(for: [exp], timeout: eventTimeout)
        XCTAssertEqual(mockUserManager.syncCallCount, 0, "Nothing was queued, so nothing should be sent")
    }

    /// Waiting sends what is queued straight away instead of sitting out the debounce window,
    /// and everything queued so far still goes in a single request.
    func testWaitForPendingWorkFlushesImmediatelyAndCoalesces() {
        queue.set(userId: "user123")
        queue.set(attributes: ["plan": "pro"])
        queue.add(attribute: "eu", forKey: "region")

        let exp = expectation(description: "resolves once the sync finishes")
        queue.waitForPendingWork { succeeded in
            XCTAssertTrue(succeeded)
            exp.fulfill()
        }

        // Flushed synchronously, well inside the 0.5s debounce window it skipped.
        XCTAssertEqual(mockUserManager.syncCallCount, 1, "Rapid writes must coalesce into one request")
        XCTAssertEqual(mockUserManager.lastSyncedUserId, "user123")
        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["plan"], "pro")
        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["region"], "eu")

        queue.syncDidFinish(success: true)
        wait(for: [exp], timeout: eventTimeout)
    }

    /// A failed update must report failure, so the caller can refuse to judge segment membership
    /// on state the write never reached.
    func testWaitForPendingWorkResolvesFalseWhenTheSyncFails() {
        queue.set(userId: "user123")
        queue.set(attributes: ["plan": "pro"])

        let exp = expectation(description: "resolves false")
        queue.waitForPendingWork { succeeded in
            XCTAssertFalse(succeeded)
            exp.fulfill()
        }

        queue.syncDidFinish(success: false)
        wait(for: [exp], timeout: eventTimeout)
    }

    /// Nothing is sent for an anonymous user, so nothing would ever resolve the waiter. It has to
    /// short-circuit rather than sit parked until the timeout.
    func testWaitForPendingWorkDoesNotHangForAnAnonymousUser() {
        // Far beyond the wait below, so only an immediate resolution can fulfil it.
        Config.User.pendingUpdateTimeoutInSeconds = 3600

        queue.set(attributes: ["plan": "pro"])

        let exp = expectation(description: "resolves without waiting out the timeout")
        queue.waitForPendingWork { _ in exp.fulfill() }

        wait(for: [exp], timeout: eventTimeout)
        XCTAssertEqual(mockUserManager.syncCallCount, 0)
    }

    // MARK: - In-flight writes

    /// An attribute written while a request is out used to be dropped: the values sat in the queue
    /// during the request, the success path cleared them wholesale, and the later commit sent
    /// nothing. Now the request *moves* its values out, so a mid-flight write survives and gets
    /// its own request.
    func testAttributeSetDuringAnInFlightSyncIsStillSent() {
        queue.set(userId: "user123")
        queue.set(attributes: ["plan": "pro"])

        let flushed = expectation(description: "first sync resolves")
        queue.waitForPendingWork { _ in flushed.fulfill() }
        XCTAssertEqual(mockUserManager.syncCallCount, 1)
        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["plan"], "pro")

        // The host writes while that request is still out.
        queue.add(attribute: "eu", forKey: "region")

        queue.syncDidFinish(success: true)
        wait(for: [flushed], timeout: eventTimeout)

        XCTAssertTrue(queue.hasScheduledCommit, "The mid-flight write must re-arm the debounce")
        queue.fireScheduledCommit()

        XCTAssertEqual(mockUserManager.syncCallCount, 2, "The mid-flight write needs its own request")
        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["region"], "eu")
        XCTAssertNil(mockUserManager.lastSyncedAttributes?["plan"], "Already-sent values must not be re-sent")
    }

    /// Two concurrent `POST /user` calls race and the later response overwrites segments,
    /// displays and responses wholesale, so a commit has to wait its turn.
    func testCommitIsDeferredWhileASyncIsInFlight() {
        queue.set(userId: "user123")

        let flushed = expectation(description: "first sync resolves")
        queue.waitForPendingWork { _ in flushed.fulfill() }
        XCTAssertEqual(mockUserManager.syncCallCount, 1)

        queue.add(attribute: "eu", forKey: "region")
        let second = expectation(description: "second wait joins the airborne request")
        queue.waitForPendingWork { _ in second.fulfill() }

        XCTAssertEqual(mockUserManager.syncCallCount, 1, "Must not start a second concurrent sync")

        queue.syncDidFinish(success: true)
        wait(for: [flushed, second], timeout: eventTimeout)
    }

    /// The debounce fires by itself on the main run loop. This is the one test that waits for the
    /// real timer; the rest fire it with `fireScheduledCommit()` so they don't race the clock.
    func testSetUserIdTriggersDebounceAndCommit() {
        let synced = expectation(description: "Debounce triggers commit")
        mockUserManager.onSync = { synced.fulfill() }

        queue.set(userId: "user123")
        XCTAssertEqual(mockUserManager.syncCallCount, 0, "Debounced, not sent straight away")

        wait(for: [synced], timeout: eventTimeout)
        XCTAssertEqual(mockUserManager.lastSyncedUserId, "user123")
    }

    func testSetAttributesTriggersDebounceAndCommit() {
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])

        XCTAssertTrue(queue.hasScheduledCommit)
        queue.fireScheduledCommit()

        XCTAssertEqual(mockUserManager.syncCallCount, 1)
        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["foo"], "bar")
    }

    func testAddAttributeToExisting() {
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])
        queue.add(attribute: "baz", forKey: "newKey")

        queue.fireScheduledCommit()

        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["foo"], "bar")
        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["newKey"], "baz")
    }

    func testAddAttributeToNew() {
        queue.set(userId: "user123")
        queue.add(attribute: "baz", forKey: "newKey")

        queue.fireScheduledCommit()

        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["newKey"], "baz")
    }

    func testAddNumberAttribute() {
        queue.set(userId: "user123")
        queue.add(attribute: 42.0, forKey: "age")

        queue.fireScheduledCommit()

        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["age"], 42.0)
    }

    func testSetLanguageWithUserId() {
        queue.set(userId: "user123")
        queue.set(language: "de")

        queue.fireScheduledCommit()

        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["language"], "de")
    }

    func testSetLanguageWithoutUserId() {
        // Only updated locally: nothing is scheduled, so nothing can be sent.
        queue.set(language: "fr")

        XCTAssertFalse(queue.hasScheduledCommit)
        XCTAssertEqual(mockUserManager.syncCallCount, 0)
    }

    func testResetClearsState() {
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])
        queue.set(language: "en")
        queue.reset()

        // Reset leaves the debounce armed; when it fires there must be nothing left to send.
        queue.fireScheduledCommit()

        XCTAssertNil(mockUserManager.lastSyncedUserId)
    }

    func testCleanupStopsTimerAndClearsState() {
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])
        queue.cleanup()

        XCTAssertFalse(queue.hasScheduledCommit, "Cleanup must stop the debounce")
        XCTAssertNil(mockUserManager.lastSyncedUserId)
    }

    func testCommitWithoutUserIdLogsError() {
        // The commit bails out before syncing, and logs an error.
        queue.set(attributes: ["foo": "bar"])

        queue.fireScheduledCommit()

        XCTAssertNil(mockUserManager.lastSyncedUserId)
    }
}
