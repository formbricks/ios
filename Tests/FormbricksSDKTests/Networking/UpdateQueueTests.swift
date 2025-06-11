import XCTest
@testable import FormbricksSDK

class MockUserManager: UserManagerSyncable {
    var lastSyncedUserId: String?
    var lastSyncedAttributes: [String: String]?
    var syncCallCount = 0
    func syncUser(withId id: String, attributes: [String : String]?, isTried: Bool) {
        lastSyncedUserId = id
        lastSyncedAttributes = attributes
        syncCallCount += 1
    }
}

final class UpdateQueueTests: XCTestCase {
    var queue: UpdateQueue!
    var mockUserManager: MockUserManager!
    
    override func setUp() {
        super.setUp()
        mockUserManager = MockUserManager()
        queue = UpdateQueue(userManager: mockUserManager)
    }
    
    override func tearDown() {
        queue.cleanup()
        queue = nil
        mockUserManager = nil
        super.tearDown()
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
