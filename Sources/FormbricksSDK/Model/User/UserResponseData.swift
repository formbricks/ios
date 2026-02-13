struct UserResponseData: Codable {
    let state: UserState?
    let messages: [String]?
    let errors: [String]?
}
