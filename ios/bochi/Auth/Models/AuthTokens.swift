// Codable = auto JSON serialize/deserialize (like serde's Serialize+Deserialize in Rust).
// `let` fields are immutable -- like `readonly` in TS or non-mut fields in Rust.
struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}
