import XCTest
@testable import FormbricksSDK

final class GetEnvironmentRequestTests: XCTestCase {
    func testInit() {
        let req = GetEnvironmentRequest()
        XCTAssertEqual(req.requestType, .get)
        XCTAssertFalse(req.requestEndPoint.isEmpty)
    }
}

final class PostUserRequestTests: XCTestCase {
    func testInit() {
        let req = PostUserRequest(userId: "abc", attributes: ["foo": "bar"])
        XCTAssertEqual(req.requestType, .post)
        XCTAssertFalse(req.requestEndPoint.isEmpty)
    }
}