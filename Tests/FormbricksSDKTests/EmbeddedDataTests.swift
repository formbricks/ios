import XCTest
@testable import FormbricksSDK

/// The Embedded Data bag (ENG-1844 / ENG-2472): host-supplied context attached to future responses
/// without tying it to a trigger. These pin the contract the four SDKs share, so a divergence here
/// is a divergence from the JS SDK too.
final class EmbeddedDataTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Formbricks.cleanup()
        clearPersistedUserId()
        EmbeddedDataManager.shared.removeAll()
    }

    override func tearDown() {
        clearPersistedUserId()
        EmbeddedDataManager.shared.removeAll()
        Formbricks.cleanup()
        super.tearDown()
    }

    /// Removes a seeded identity on both sides of every test.
    ///
    /// `Formbricks.cleanup()` clears it only when a `UserManager` exists to log out, which it does
    /// not before the first `setup`. Without this, a seeded id would outlive this class — which
    /// runs first alphabetically — and `FormbricksSDKTests` asserts `userManager?.userId` is nil
    /// before setup.
    private func clearPersistedUserId() {
        UserDefaults.standard.removeObject(forKey: "userIdKey")
    }

    /// Initializes the SDK against the mock service, so identity changes can be exercised without
    /// the network.
    private func setUpSdk() {
        Formbricks.setup(
            with: FormbricksConfig.Builder(appUrl: "https://app.formbricks.com", workspaceId: "ws-1")
                .setLogLevel(.debug)
                .service(MockFormbricksService())
                .build())
    }

    /// Seeds a persisted identity, the way a previous app session would have left one.
    ///
    /// Not `Formbricks.setUserId`: that only enqueues into the debounced `UpdateQueue`, so
    /// `userManager?.userId` stays nil until a network sync lands, and a test driving it that way
    /// would silently take the first-identification branch and pass for the wrong reason. Writing
    /// the same `UserDefaults` key the getter falls back to is exact, needs no timer or request, and
    /// models the honest scenario — the app relaunches already identified, then a different user
    /// signs in.
    ///
    /// Must be called **before** `setUpSdk()`: `UserManager` caches `backingUserId` on first read,
    /// so the value has to be in place when the fresh manager is created. The key is
    /// `UserManager`'s own private constant, repeated here because that is the storage contract
    /// this seeds.
    private func seedPersistedUserId(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: "userIdKey")
    }

    /// `snapshot()` returns `[String: Any]`, so comparisons go through `NSDictionary`, which
    /// compares element-wise with the bridged equality each value type already has.
    private func assertSnapshot(_ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(
            EmbeddedDataManager.shared.snapshot() as NSDictionary,
            expected as NSDictionary,
            file: file,
            line: line
        )
    }

    // MARK: - Merge semantics

    func testMergesInsteadOfReplacing() {
        Formbricks.setEmbeddedData(["plan": "pro", "screen": "product"])
        Formbricks.setEmbeddedData(["screen": "checkout"])

        assertSnapshot(["plan": "pro", "screen": "checkout"])
    }

    func testNilRemovesTheKey() {
        Formbricks.setEmbeddedData(["plan": "pro", "screen": "product"])
        Formbricks.setEmbeddedData(["screen": nil])

        assertSnapshot(["plan": "pro"])
    }

    func testLastWriteWinsPerKey() {
        Formbricks.setEmbeddedData(["plan": "free"])
        Formbricks.setEmbeddedData(["plan": "pro"])

        assertSnapshot(["plan": "pro"])
    }

    func testOmittedKeysAreUntouched() {
        // Swift has no `undefined`, so "skip this field" is spelled by leaving the key out — and
        // that must not disturb what an earlier call set. `nil` is the explicit "remove" spelling.
        Formbricks.setEmbeddedData(["plan": "pro", "screen": "product"])
        Formbricks.setEmbeddedData(["seats": 4])

        assertSnapshot(["plan": "pro", "screen": "product", "seats": 4.0])
    }

    // MARK: - Clearing

    func testClearOneKeyLeavesTheRest() {
        Formbricks.setEmbeddedData(["plan": "pro", "screen": "product", "seats": 4])

        Formbricks.clearEmbeddedData("screen")

        assertSnapshot(["plan": "pro", "seats": 4.0])
    }

    func testClearingAnUnsetKeyIsANoOp() {
        Formbricks.setEmbeddedData(["plan": "pro"])

        Formbricks.clearEmbeddedData("neverSet")

        assertSnapshot(["plan": "pro"])
    }

    func testClearEverything() {
        Formbricks.setEmbeddedData(["plan": "pro", "screen": "product"])

        Formbricks.clearEmbeddedData()

        assertSnapshot([:])
    }

    // MARK: - Value types

    func testEveryScalarSurvivesInItsJsonForm() {
        let signedUpAt = Date(timeIntervalSince1970: 1_787_000_000)

        Formbricks.setEmbeddedData([
            "plan": "pro",
            "seats": 25,
            "score": 9.5,
            "isTrial": false,
            "signedUpAt": .date(signedUpAt),
        ])

        let snapshot = EmbeddedDataManager.shared.snapshot()
        XCTAssertEqual(snapshot["plan"] as? String, "pro")
        XCTAssertEqual(snapshot["seats"] as? Double, 25)
        XCTAssertEqual(snapshot["score"] as? Double, 9.5)
        XCTAssertEqual(snapshot["isTrial"] as? Bool, false)
        // ISO 8601 is what the renderer's ingest contract accepts for a `date` field.
        XCTAssertEqual(snapshot["signedUpAt"] as? String, ISO8601DateFormatter().string(from: signedUpAt))
    }

    func testASnapshotIsSerializableAsJson() {
        // The snapshot is embedded in the survey WebView's props blob, which goes through
        // JSONSerialization. If it ever threw, the failure would not be a missing field — it would
        // be no survey at all.
        Formbricks.setEmbeddedData([
            "plan": "pro",
            "seats": 25,
            "isTrial": true,
            "signedUpAt": .date(Date()),
        ])

        XCTAssertTrue(JSONSerialization.isValidJSONObject(EmbeddedDataManager.shared.snapshot()))
        XCTAssertNoThrow(
            try JSONSerialization.data(withJSONObject: EmbeddedDataManager.shared.snapshot(), options: []))
    }

    func testANonFiniteNumberIsSkippedRatherThanCostingTheSurvey() {
        // THE guard: JSONSerialization throws on a non-finite Double, and the payload it would
        // refuse is the whole survey's props blob. Dropping the key is the only safe answer.
        Formbricks.setEmbeddedData(["plan": "pro"])

        Formbricks.setEmbeddedData([
            "broken": .number(Double.nan),
            "alsoBroken": .number(Double.infinity),
        ])

        assertSnapshot(["plan": "pro"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(EmbeddedDataManager.shared.snapshot()))
    }

    // MARK: - Lifetime

    func testSnapshotIsDetachedFromLaterWrites() {
        // What "a value set after a survey is displayed does not change that response" rests on:
        // the WebView payload holds this dictionary for the life of the survey.
        Formbricks.setEmbeddedData(["plan": "pro"])
        let snapshot = EmbeddedDataManager.shared.snapshot()

        Formbricks.setEmbeddedData(["plan": "enterprise", "extra": "later"])

        XCTAssertEqual(snapshot as NSDictionary, ["plan": "pro"] as NSDictionary)
    }

    func testWorksBeforeSetup() {
        // Deliberately unlike the other public methods: a host that pushes context at launch must
        // not have the value dropped because initialization had not finished yet.
        XCTAssertFalse(Formbricks.isInitialized)

        Formbricks.setEmbeddedData(["plan": "pro"])

        assertSnapshot(["plan": "pro"])
    }

    func testIsNotPersisted() {
        // A cold start begins empty. Nothing host-supplied may reach UserDefaults, where it would
        // outlive the session and blur the Embedded Data ↔ contact-attribute boundary. A UUID
        // marker so the search cannot collide with unrelated defaults.
        let marker = "fb-embedded-probe-\(UUID().uuidString)"

        Formbricks.setEmbeddedData(["probe": .string(marker)])

        // Only the marker is asserted, deliberately: comparing the whole key set would also catch a
        // write from some earlier test's in-flight sync and fail for a reason this test is not about.
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        XCTAssertFalse(defaults.values.contains { String(describing: $0).contains(marker) })
    }

    func testCleanupClearsTheBag() {
        Formbricks.setEmbeddedData(["plan": "pro"])

        Formbricks.cleanup()

        assertSnapshot([:])
    }

    // MARK: - Identity changes

    func testSwitchingUserClearsTheBag() {
        seedPersistedUserId("user-a")
        setUpSdk()
        XCTAssertEqual(Formbricks.userManager?.userId, "user-a")
        Formbricks.setEmbeddedData(["plan": "pro"])

        Formbricks.setUserId("user-b")

        assertSnapshot([:])
    }

    func testFirstIdentificationKeepsTheBag() {
        // The host pushes context before it knows who the user is — that is the normal order, and
        // clearing here would throw away the value the API exists to carry.
        setUpSdk()
        // `userId` is persisted in UserDefaults, so an id left by an earlier test would make this
        // take the switch branch. Log out first — which also empties the bag, hence the ordering.
        Formbricks.logout()
        XCTAssertNil(Formbricks.userManager?.userId)
        Formbricks.setEmbeddedData(["plan": "pro"])

        Formbricks.setUserId("user-a")

        assertSnapshot(["plan": "pro"])
    }

    func testSettingTheSameUserIdKeepsTheBag() {
        seedPersistedUserId("user-a")
        setUpSdk()
        XCTAssertEqual(Formbricks.userManager?.userId, "user-a")
        Formbricks.setEmbeddedData(["plan": "pro"])

        Formbricks.setUserId("user-a")

        assertSnapshot(["plan": "pro"])
    }

    func testLogoutClearsTheBag() {
        setUpSdk()
        Formbricks.setEmbeddedData(["plan": "pro"])

        Formbricks.logout()

        assertSnapshot([:])
    }

    // MARK: - Thread safety

    func testConcurrentWritesDoNotCrash() {
        // The host may call from any thread while the main queue reads the snapshot to present a
        // survey. Without the serial queue this trips the dictionary's exclusivity checks.
        let iterations = 200
        let done = expectation(description: "concurrent writes")
        done.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            Formbricks.setEmbeddedData(["key\(index % 8)": .number(Double(index))])
            _ = EmbeddedDataManager.shared.snapshot()
            done.fulfill()
        }

        wait(for: [done], timeout: 10)
        XCTAssertFalse(EmbeddedDataManager.shared.snapshot().isEmpty)
    }
}
