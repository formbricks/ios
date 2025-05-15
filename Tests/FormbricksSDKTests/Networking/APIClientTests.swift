import XCTest
@testable import FormbricksSDK

final class APIClientTests: XCTestCase {
    
    // MARK: - Test Doubles
    
    private struct MockRequest: CodableRequest {
        typealias Response = MockResponse
        
        var baseURL: String?
        var requestEndPoint: String
        var requestType: HTTPMethod
        var headers: [String: String]?
        var queryParams: [String: String]?
        var pathParams: [String: String]?
        var requestBody: Data?
        
        var decoder: JSONDecoder {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    }
    
    private struct MockResponse: Codable {
        let id: String
        let name: String
    }
    
    private struct MockEnvironmentResponse: Codable {
        var responseString: String?
        let id: String
        let name: String
    }
    
    // MARK: - Properties
    
    private var mockURLSession: MockURLSession!
    private var sut: APIClient<MockRequest>!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        mockURLSession = MockURLSession()
        Formbricks.environmentId = "test-env-id"
    }
    
    override func tearDown() {
        mockURLSession = nil
        sut = nil
        Formbricks.environmentId = nil
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testSuccessfulResponse() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let mockResponse = MockResponse(id: "123", name: "Test")
        let responseData = try! JSONEncoder().encode(mockResponse)
        
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test/{environmentId}",
            requestType: .get
        )
        
        mockURLSession.mockData = responseData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success(let response):
                XCTAssertEqual(response.id, "123")
                XCTAssertEqual(response.name, "Test")
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testFailedResponseWithAPIError() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let apiError = FormbricksAPIError(
            code: "TEST_ERROR",
            message: "Test error",
            details: ["field": "test_field"]
        )
        let errorData = try! JSONEncoder().encode(apiError)
        
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        mockURLSession.mockData = errorData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success:
                XCTFail("Expected failure but got success")
            case .failure(let error as FormbricksAPIError):
                XCTAssertEqual(error.message, "Test error")
                XCTAssertEqual(error.code, "TEST_ERROR")
                XCTAssertEqual(error.details?["field"], "test_field")
            case .failure(let error):
                XCTFail("Expected FormbricksAPIError but got: \(type(of: error))")
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testInvalidURL() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let request = MockRequest(
            baseURL: nil,
            requestEndPoint: "/test",
            requestType: .get
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success:
                XCTFail("Expected failure but got success")
            case .failure(let error as FormbricksSDKError):
                XCTAssertEqual(error.type, .sdkIsNotInitialized)
            case .failure(let error):
                XCTFail("Expected FormbricksSDKError but got: \(type(of: error))")
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDecodingError() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let invalidData = "invalid json".data(using: .utf8)!
        
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        mockURLSession.mockData = invalidData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success:
                XCTFail("Expected failure but got success")
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .invalidResponse)
            case .failure(let error):
                XCTFail("Expected FormbricksAPIClientError but got: \(type(of: error))")
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testVoidResponse() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        mockURLSession.mockData = "{}".data(using: .utf8)
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success:
                XCTAssertTrue(true)
            case .failure(let error):
                let normalized = error.localizedDescription
                    .replacingOccurrences(of: "’", with: "'") // curly to straight apostrophe
                    .replacingOccurrences(of: "‘", with: "'") // opening curly to straight
                    .lowercased() // optional: ignore case

                XCTAssertTrue(normalized.contains("couldn't be completed"))
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testNetworkError() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let networkError = NSError(domain: "test", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet connection"])
        
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        mockURLSession.mockError = networkError
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 0,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success:
                XCTFail("Expected failure but got success")
            case .failure(let error):
                let normalized = error.localizedDescription
                    .replacingOccurrences(of: "’", with: "'") // curly to straight apostrophe
                    .replacingOccurrences(of: "‘", with: "'") // opening curly to straight
                    .lowercased() // optional: ignore case

                XCTAssertTrue(normalized.contains("couldn't be completed"))
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRequestWithQueryParams() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let mockResponse = MockResponse(id: "123", name: "Test")
        let responseData = try! JSONEncoder().encode(mockResponse)
        
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get,
            queryParams: ["key": "value", "filter": "active"]
        )
        
        mockURLSession.mockData = responseData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success(let response):
                XCTAssertEqual(response.id, "123")
                XCTAssertEqual(response.name, "Test")
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRequestWithHeaders() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let mockResponse = MockResponse(id: "123", name: "Test")
        let responseData = try! JSONEncoder().encode(mockResponse)
        
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get,
            headers: ["Authorization": "Bearer token", "Content-Type": "application/json"]
        )
        
        mockURLSession.mockData = responseData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success(let response):
                XCTAssertEqual(response.id, "123")
                XCTAssertEqual(response.name, "Test")
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock URLSession

private class MockURLSession: URLSession {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    
    override func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return MockURLSessionDataTask {
            completionHandler(self.mockData, self.mockResponse, self.mockError)
        }
    }
}

private class MockURLSessionDataTask: URLSessionDataTask {
    private let completion: () -> Void
    
    init(completion: @escaping () -> Void) {
        self.completion = completion
    }
    
    override func resume() {
        completion()
    }
} 
