struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}
