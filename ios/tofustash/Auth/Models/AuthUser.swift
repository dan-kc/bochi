// No Codable here -- this struct isn't decoded from JSON directly.
struct AuthUser: Equatable, Sendable {
    let id: String
    let isAnonymous: Bool
}
