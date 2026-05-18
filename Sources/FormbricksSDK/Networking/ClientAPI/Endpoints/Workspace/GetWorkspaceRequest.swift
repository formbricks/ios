struct GetWorkspaceRequest: CodableRequest {
    typealias Response = WorkspaceResponse
    var requestEndPoint: String { return FormbricksWorkspace.getWorkspaceStateRequestEndpoint }
    var requestType: HTTPMethod { return .get }
}
