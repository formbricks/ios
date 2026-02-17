import UIKit
@testable import FormbricksSDK

/// This can be extended later when needed
enum MockResponse: String {
    case environment = "Environment"
    case user = "User"
    case userWithErrors = "UserWithErrors"
    case userWithMessages = "UserWithMessages"
    case userWithErrorsAndMessages = "UserWithErrorsAndMessages"
}

class MockFormbricksService: FormbricksService {
    
    var isErrorResponseNeeded = false
    /// Controls which mock JSON file is used for postUser responses.
    /// Defaults to `.user` (the standard User.json).
    var userMockResponse: MockResponse = .user
    
    override func getEnvironmentState(completion: @escaping (ResultType<GetEnvironmentRequest.Response>) -> Void) {
        if isErrorResponseNeeded {
            completion(.failure(RuntimeError(message: "")))
        } else {
            execute(.environment, completion: completion)
        }
    }
    
    override func postUser(id: String, attributes: [String : AttributeValue]?, completion: @escaping (ResultType<PostUserRequest.Response>) -> Void) {
        if isErrorResponseNeeded {
            completion(.failure(RuntimeError(message: "")))
        } else {
            execute(userMockResponse, completion: completion)
        }
    }
    
    func execute<T: Decodable>(_ response: MockResponse, completion: @escaping (ResultType<T>) -> Void) {
        guard let url = Bundle.module.url(forResource: response.rawValue, withExtension: "json"), let data = try? Data(contentsOf: url) else {
        completion(.failure(RuntimeError(message: "Unable to parse response")))
        return
      }
      
      do {
        let body = try JSONDecoder.iso8601Full.decode(T.self, from: data)
        completion(.success(body))
      } catch {
        completion(.failure(error))
      }
    }

}
