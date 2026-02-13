/// FormbricksService is a service class that handles the network requests for Formbricks API.
class FormbricksService: FormbricksServiceProtocol {
    
    // MARK: - Environment -
    /// Get the current environment state.
    func getEnvironmentState(completion: @escaping (ResultType<GetEnvironmentRequest.Response>) -> Void) {
        let endPointRequest = GetEnvironmentRequest()
        execute(endPointRequest, withCompletion: completion)
    }

    // MARK: - User -
    /// Logs in a user with the given ID or creates one if it doesn't exist.
    func postUser(id: String, attributes: [String: AttributeValue]?, completion: @escaping (ResultType<PostUserRequest.Response>) -> Void) {
        let endPointRequest = PostUserRequest(userId: id, attributes: attributes)
        execute(endPointRequest, withCompletion: completion)
    }
}

protocol FormbricksServiceProtocol {
    func getEnvironmentState(
      completion: @escaping (ResultType<GetEnvironmentRequest.Response>) -> Void
    )
    func postUser(
      id: String,
      attributes: [String: AttributeValue]?,
      completion: @escaping (ResultType<PostUserRequest.Response>) -> Void
    )
  }

private extension FormbricksService {
    /// Creates the APIClient operation and adds it to the queue
    func execute<Request: CodableRequest>(_ request: Request, withCompletion completion: @escaping (ResultType<Request.Response>) -> Void) {
        let operation = APIClient(request: request, completion: completion)
        Formbricks.apiQueue?.addOperation(operation)
    }
}
