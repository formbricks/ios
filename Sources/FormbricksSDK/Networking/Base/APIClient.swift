import Foundation

/// The one call `APIClient` makes on `URLSession`. Tests answer it directly instead of
/// subclassing `URLSession`, whose initializers are deprecated for subclasses.
protocol DataTaskProviding {
    func startDataTask(
        with request: URLRequest, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void)
}

extension URLSession: DataTaskProviding {
    func startDataTask(
        with request: URLRequest, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) {
        dataTask(with: request, completionHandler: completionHandler).resume()
    }
}

class APIClient<Request: CodableRequest>: Operation, @unchecked Sendable {

    private let session: DataTaskProviding
    private let request: Request
    private let completion: ((ResultType<Request.Response>) -> Void)?

    init(
        request: Request, session: DataTaskProviding = URLSession.shared,
        completion: ((ResultType<Request.Response>) -> Void)?
    ) {
        self.request = request
        self.session = session
        self.completion = completion
    }

    override func main() {
        guard let finalURL = buildFinalURL() else {
            completion?(.failure(FormbricksSDKError(type: .invalidAppUrl)))
            return
        }

        let urlRequest = createURLRequest(forURL: finalURL)
        logRequest(urlRequest)

        session.startDataTask(with: urlRequest) { data, response, error in
            self.processResponse(data: data, response: response, error: error)
        }
    }

    private func buildFinalURL() -> URL? {
        guard let apiURL = request.baseURL, var components = URLComponents(string: apiURL) else { return nil }

        // Ensure only HTTPS requests are allowed (block HTTP)
        guard let scheme = components.scheme?.lowercased(), scheme == "https" else {
            let errorMessage =
                "HTTP requests are blocked for security. Only HTTPS requests are allowed. Provided app url: \(apiURL)"
            Formbricks.logger?.error(errorMessage)
            return nil
        }

        components.queryItems = request.queryParams?.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard var url = components.url, let path = setPathParams(request.requestEndPoint) else { return nil }

        url.appendPathComponent(path)
        return url
    }

    private func processResponse(data: Data?, response: URLResponse?, error: Error?) {
        guard let httpStatus = (response as? HTTPURLResponse)?.status else {
            let error = FormbricksAPIClientError(type: .invalidResponse)
            Formbricks.logger?.error("ERROR \(error.message)")
            completion?(.failure(error))
            return
        }

        var message = "\(httpStatus.rawValue) <<< \(response?.url?.absoluteString ?? "")"

        if httpStatus.responseType == .success {
            handleSuccessResponse(data: data, statusCode: httpStatus.rawValue, message: &message)
        } else {
            handleFailureResponse(data: data, error: error, statusCode: httpStatus.rawValue, message: message)
        }
    }

    private func handleSuccessResponse(data: Data?, statusCode: Int, message: inout String) {
        guard let data = data else {
            let error = FormbricksAPIClientError(type: .invalidResponse, statusCode: statusCode)
            completion?(.failure(error))
            return
        }

        if let responseString = String(data: data, encoding: .utf8) {
            message.append("\n\(responseString)\n")
        }

        do {
            if let voidResponse = VoidResponse() as? Request.Response {
                Formbricks.logger?.info(message)
                completion?(.success(voidResponse))
            } else {
                var body = try request.decoder.decode(Request.Response.self, from: data)
                if var workspace = body as? WorkspaceResponse, let jsonString = String(data: data, encoding: .utf8) {
                    workspace.responseString = jsonString
                    if let patched = workspace as? Request.Response {
                        body = patched
                    }
                }
                Formbricks.logger?.info(message)
                completion?(.success(body))
            }
        } catch {
            handleDecodingError(error, message: &message, statusCode: statusCode)
        }
    }

    private func handleFailureResponse(data: Data?, error: Error?, statusCode: Int, message: String) {
        var log = message

        if let error = error {
            log.append("\nError: \(error.localizedDescription)")
            Formbricks.logger?.error(log)
            completion?(.failure(error))
        } else if let data = data, let apiError = try? request.decoder.decode(FormbricksAPIError.self, from: data) {
            Formbricks.logger?.error("\(log)\n\(apiError.getDetailedErrorMessage())")
            completion?(.failure(apiError))
        } else {
            let error = FormbricksAPIClientError(type: .responseError, statusCode: statusCode)
            Formbricks.logger?.error("\(log)\n\(error.message)")
            completion?(.failure(error))
        }
    }

    private func handleDecodingError(_ error: Error, message: inout String, statusCode: Int) {
        switch error {
        case DecodingError.dataCorrupted(let context):
            message.append("Data corrupted: \(context)")
        case DecodingError.keyNotFound(let key, let context):
            message.append("Key '\(key)' not found: \(context.debugDescription)\ncodingPath: \(context.codingPath)")
        case DecodingError.valueNotFound(let value, let context):
            message.append("Value '\(value)' not found: \(context.debugDescription)\ncodingPath: \(context.codingPath)")
        case DecodingError.typeMismatch(let type, let context):
            message.append("Type '\(type)' mismatch: \(context.debugDescription)\ncodingPath: \(context.codingPath)")
        default:
            message.append("Error: \(error.localizedDescription)")
        }

        let error = FormbricksAPIClientError(type: .invalidResponse, statusCode: statusCode)
        Formbricks.logger?.error(error.message)
        completion?(.failure(error))
    }

    private func logRequest(_ request: URLRequest) {
        var message = "\(request.httpMethod ?? "") >>> \(request.url?.absoluteString ?? "")"

        if let headers = request.allHTTPHeaderFields {
            message.append("\nHeaders: \(headers)")
        }

        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            message.append("\nBody: \(bodyString)")
        }

        Formbricks.logger?.info(message)
    }

}

extension APIClient {
    fileprivate func createURLRequest(forURL url: URL) -> URLRequest {
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)

        for (field, value) in request.headers ?? [:] {
            urlRequest.addValue(value, forHTTPHeaderField: field)
        }

        urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        urlRequest.httpMethod = request.requestType.rawValue

        if let body = request.requestBody {
            urlRequest.httpBody = body
        }

        return urlRequest
    }

    fileprivate func setPathParams(_ path: String) -> String? {
        var newPath = path
        if let workspaceId = Formbricks.workspaceId {
            newPath = newPath.replacingOccurrences(of: "{workspaceId}", with: workspaceId)
            // Backward-compatible: still replace the legacy `{environmentId}` placeholder.
            newPath = newPath.replacingOccurrences(of: "{environmentId}", with: workspaceId)
        }

        for (key, value) in request.pathParams ?? [:] {
            newPath = newPath.replacingOccurrences(of: key, with: value)
        }

        return newPath
    }
}
