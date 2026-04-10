import Foundation
@testable import tofustash

// A caseless enum used as a namespace for static methods — like a Go package or
// a TS module with only exported functions. Can't be instantiated (no cases = no values).
// Same trick as Rust's `enum Void {}` — the compiler enforces it, unlike a class where
// you'd need `private init()`.
enum TestHelpers {
    /// Creates a fake JWT token with the given subject and expiration.
    /// The token is not cryptographically signed but has valid structure for parsing.
    // `static func` = like a static method in a TS class, or a standalone function in Go/Rust
    static func makeJWT(subject: String, expiresAt: Int) -> String {
        let header = Data("{}".utf8).base64EncodedString()
        let payload: [String: Any] = ["sub": subject, "exp": expiresAt]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payloadBase64).fakesig"
    }

    /// Creates AuthTokens with fake JWTs for the given user.
    // Default parameter values — same as TS/Go defaults. Callers can omit any of these.
    static func makeTokens(
        userId: String = "user-123",
        isAnonymous: Bool = false,
        expiresIn: Int = 3600
    ) -> AuthTokens {
        // Date() = new Date() in JS. timeIntervalSince1970 = Date.now()/1000 (seconds, not ms)
        let exp = Int(Date().timeIntervalSince1970) + expiresIn
        return AuthTokens(
            accessToken: makeJWT(subject: userId, expiresAt: exp),
            refreshToken: "refresh-token-\(userId)"
        )
    }
}
