import Foundation
@testable import tofustash

enum TestHelpers {
    /// Creates a fake JWT token with the given subject and expiration.
    /// The token is not cryptographically signed but has valid structure for parsing.
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
    static func makeTokens(
        userId: String = "user-123",
        isAnonymous: Bool = false,
        expiresIn: Int = 3600
    ) -> AuthTokens {
        let exp = Int(Date().timeIntervalSince1970) + expiresIn
        return AuthTokens(
            accessToken: makeJWT(subject: userId, expiresAt: exp),
            refreshToken: "refresh-token-\(userId)"
        )
    }
}
