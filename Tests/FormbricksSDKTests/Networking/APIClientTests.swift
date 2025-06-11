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
    
    private struct MockVoidRequest: CodableRequest {
        typealias Response = VoidResponse
        
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
        //wait(for: [expectation], timeout: 1.0)
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
            requestType: .get,
            headers: [
                "some": "some"
            ]
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
        //wait(for: [expectation], timeout: 1.0)
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
                XCTAssertEqual(error.type, .invalidAppUrl)
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
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testVoidResponse() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        
        // Create a request that expects a VoidResponse
        var request = MockVoidRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        request.pathParams = [
            "{someId}": "someValue",
        ]
        
        mockURLSession.mockData = Data() // Empty data for a void response
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let apiClient = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success(let response):
                // Ensure the response is of type VoidResponse
                XCTAssertTrue(response is VoidResponse)
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        apiClient.main()
        //wait(for: [expectation], timeout: 1.0)
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
        //wait(for: [expectation], timeout: 1.0)
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
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testHttpSchemeBlocked() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with invalid app URL error")
        var request = MockRequest(
            requestEndPoint: "/test",
            requestType: .get
        )
        request.baseURL = "http://api.test.com"
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .failure(let error as FormbricksSDKError):
                XCTAssertEqual(error.type, .invalidAppUrl)
            default:
                XCTFail("Expected FormbricksSDKError with type invalidAppUrl, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDataIsNil() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with invalid response error")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        mockURLSession.mockData = nil // Data is nil
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
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .invalidResponse)
            default:
                XCTFail("Expected FormbricksAPIClientError with type invalidResponse, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testInvalidResponse() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with invalid response error")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        mockURLSession.mockResponse = nil // Response is not an HTTPURLResponse
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .invalidResponse)
            default:
                XCTFail("Expected FormbricksAPIClientError with type invalidResponse, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testResponseErrorWithoutData() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with response error")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        mockURLSession.mockData = nil // Data is nil
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        sut = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .responseError)
            default:
                XCTFail("Expected FormbricksAPIClientError with type responseError, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testDecodingDataCorrupted() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with decoding error")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        let corruptedData = "corrupted data".data(using: .utf8)
        mockURLSession.mockData = corruptedData
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
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .invalidResponse)
            default:
                XCTFail("Expected FormbricksAPIClientError with type invalidResponse, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testDecodingKeyNotFound() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with decoding error")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        // JSON missing the 'name' key
        let incompleteData = "{\"id\": \"123\"}".data(using: .utf8)
        mockURLSession.mockData = incompleteData
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
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .invalidResponse)
            default:
                XCTFail("Expected FormbricksAPIClientError with type invalidResponse, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testDecodingValueNotFound() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with decoding error")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        // 'name' key has a null value, which is not expected
        let nullValueData = "{\"id\": \"123\", \"name\": null}".data(using: .utf8)
        mockURLSession.mockData = nullValueData
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
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .invalidResponse)
            default:
                XCTFail("Expected FormbricksAPIClientError with type invalidResponse, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testDecodingTypeMismatch() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes with decoding error")
        let request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test",
            requestType: .get
        )
        
        // 'id' is a number instead of a string
        let typeMismatchData = "{\"id\": 123, \"name\": \"Test\"}".data(using: .utf8)
        mockURLSession.mockData = typeMismatchData
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
            case .failure(let error as FormbricksAPIClientError):
                XCTAssertEqual(error.type, .invalidResponse)
            default:
                XCTFail("Expected FormbricksAPIClientError with type invalidResponse, but got something else.")
            }
            expectation.fulfill()
        }
        
        sut.main()
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testSuccessfulResponseWithBody() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        let mockResponse = MockResponse(id: "123", name: "Test")
        let responseData = try! JSONEncoder().encode(mockResponse)
        
        var request = MockRequest(
            baseURL: "https://api.test.com",
            requestEndPoint: "/test/{environmentId}",
            requestType: .get
        )
        
        request.requestBody = "test".data(using: .utf8)
        
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
        //wait(for: [expectation], timeout: 1.0)
    }
    
    func testEnvironmentResponse() {
        // Given
        let expectation = XCTestExpectation(description: "API call completes")
        
        let request = GetEnvironmentRequest()
        Formbricks.appUrl = "https://api.test.com"
        addTeardownBlock {
            Formbricks.appUrl = nil
        }
        
        let mockJSON = """
        {
            "data": {
                "data": {
                    "project": {}
                },
                "expiresAt": "2099-12-31T23:59:59.999Z"
            }
        }
        """
        
        let mockData = mockJSON.data(using: .utf8)!
        
        mockURLSession.mockData = mockData
        mockURLSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let apiClient = APIClient(request: request, session: mockURLSession) { result in
            // Then
            switch result {
            case .success(let response):
                // Additional check to see if the responseString is populated
                XCTAssertNotNil(response.responseString)
                XCTAssertTrue(response.responseString!.contains("2099-12-31T23:59:59.999Z"))
            case .failure(let error):
                XCTFail("Expected success, but got an error: \(error.localizedDescription)")
            }
            expectation.fulfill()
        }
        
        apiClient.main()
        //wait(for: [expectation], timeout: 1.0)
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
