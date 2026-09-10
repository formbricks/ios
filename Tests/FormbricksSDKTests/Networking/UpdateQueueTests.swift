import XCTest
@testable import FormbricksSDK

class MockUserManager: UserManagerSyncable {
    var lastSyncedUserId: String?
    var lastSyncedAttributes: [String: AttributeValue]?
    var syncCallCount = 0
    func syncUser(withId id: String, attributes: [String : AttributeValue]?) {
        lastSyncedUserId = id
        lastSyncedAttributes = attributes
        syncCallCount += 1
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
        wait(for: [exp], timeout: 1.0)
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
        wait(for: [exp], timeout: 1.0)
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
        wait(for: [exp], timeout: 1.0)
    }

    /// Nothing is sent for an anonymous user, so nothing would ever resolve the waiter. It has to
    /// short-circuit rather than sit parked until the timeout.
    func testWaitForPendingWorkDoesNotHangForAnAnonymousUser() {
        Config.User.pendingUpdateTimeoutInSeconds = 30

        queue.set(attributes: ["plan": "pro"])

        let exp = expectation(description: "resolves without waiting out the timeout")
        queue.waitForPendingWork { _ in exp.fulfill() }

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(mockUserManager.syncCallCount, 0)
    }

    // MARK: - In-flight writes

    /// An attribute written while a request is out used to be dropped: the values sat in the queue
    /// during the request, the success path cleared them wholesale, and the later commit sent
    /// nothing. Now the request *moves* its values out, so a mid-flight write survives and gets
    /// its own request.
    func testAttributeSetDuringAnInFlightSyncIsStillSent() {
        Config.User.updateDebounceIntervalInSeconds = 0.05

        queue.set(userId: "user123")
        queue.set(attributes: ["plan": "pro"])

        let flushed = expectation(description: "first sync resolves")
        queue.waitForPendingWork { _ in flushed.fulfill() }
        XCTAssertEqual(mockUserManager.syncCallCount, 1)
        XCTAssertEqual(mockUserManager.lastSyncedAttributes?["plan"], "pro")

        // The host writes while that request is still out.
        queue.add(attribute: "eu", forKey: "region")

        queue.syncDidFinish(success: true)
        wait(for: [flushed], timeout: 1.0)

        let settled = expectation(description: "re-armed debounce sends the mid-flight write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 1.0)

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
        wait(for: [flushed, second], timeout: 1.0)
    }
    
    func testSetUserIdTriggersDebounceAndCommit() {
        let exp = expectation(description: "Debounce triggers commit")
        queue.set(userId: "user123")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(self.mockUserManager.lastSyncedUserId, "user123")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testSetAttributesTriggersDebounceAndCommit() {
        let exp = expectation(description: "Debounce triggers commit for attributes")
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(self.mockUserManager.lastSyncedAttributes?["foo"], "bar")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testAddAttributeToExisting() {
        let exp = expectation(description: "Add attribute to existing attributes")
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])
        queue.add(attribute: "baz", forKey: "newKey")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(self.mockUserManager.lastSyncedAttributes?["foo"], "bar")
            XCTAssertEqual(self.mockUserManager.lastSyncedAttributes?["newKey"], "baz")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testAddAttributeToNew() {
        let exp = expectation(description: "Add attribute to new attributes")
        queue.set(userId: "user123")
        queue.add(attribute: "baz", forKey: "newKey")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(self.mockUserManager.lastSyncedAttributes?["newKey"], "baz")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testAddNumberAttribute() {
        let exp = expectation(description: "Add number attribute")
        queue.set(userId: "user123")
        queue.add(attribute: 42.0, forKey: "age")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(self.mockUserManager.lastSyncedAttributes?["age"], 42.0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testSetLanguageWithUserId() {
        let exp = expectation(description: "Set language with userId triggers commit")
        queue.set(userId: "user123")
        queue.set(language: "de")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(self.mockUserManager.lastSyncedAttributes?["language"], "de")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testSetLanguageWithoutUserId() {
        // Should not call syncUser, just log
        queue.set(language: "fr")
        let exp = expectation(description: "No commit without userId")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(self.mockUserManager.syncCallCount, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testResetClearsState() {
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])
        queue.set(language: "en")
        queue.reset()
        // Internal state is private, but we can check that no sync happens after reset
        let exp = expectation(description: "No commit after reset")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Should not have called syncUser after reset
            XCTAssertNil(self.mockUserManager.lastSyncedUserId)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testCleanupStopsTimerAndClearsState() {
        queue.set(userId: "user123")
        queue.set(attributes: ["foo": "bar"])
        queue.cleanup()
        let exp = expectation(description: "No commit after cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertNil(self.mockUserManager.lastSyncedUserId)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testCommitWithoutUserIdLogsError() {
        // This will not call syncUser, but will log an error
        queue.set(attributes: ["foo": "bar"])
        let exp = expectation(description: "No commit without userId")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertNil(self.mockUserManager.lastSyncedUserId)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
} 
