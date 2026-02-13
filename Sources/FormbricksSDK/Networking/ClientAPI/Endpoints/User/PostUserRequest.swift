final class PostUserRequest: EncodableRequest<PostUserRequest.Body>, CodableRequest {
    var requestEndPoint: String { return FormbricksEnvironment.postUserRequestEndpoint }
    var requestType: HTTPMethod { return .post }
    
    
    struct Response: Codable {
        let data: UserResponseData
    }
    
    struct Body: Codable {
        let userId: String
        let attributes: [String: AttributeValue]?
    }
    
        
    init(userId: String, attributes: [String: AttributeValue]?) {
        super.init(object: Body(userId: userId, attributes: attributes))
    }
}
