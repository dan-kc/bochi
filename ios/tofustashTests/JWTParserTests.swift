import Foundation
import Testing // Swift Testing framework — the modern replacement for XCTest
@testable import tofustash // Like importing from '../src' but bypassing access control (exposes `internal` symbols to tests)

// A plain struct works as a test suite — no base class needed. Think: `describe("JWTParser", ...)` in Jest.
struct JWTParserTests {

    // [String: Any] is like Record<string, any> in TS — a loosely-typed dictionary
    private func makeJWT(payload: [String: Any]) -> String {
        let header = Data("{}".utf8).base64EncodedString()
        // try! force-unwraps a throwing call — like Rust's .unwrap(). Panics if it fails.
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let signature = "fakesig"
        // String interpolation: \(...) is Swift's ${...}
        return "\(header).\(payloadBase64).\(signature)"
    }

    // Behaviour: When the app receives an auth token, it correctly identifies which
    // user it belongs to by parsing the subject claim.
    @Test func parsesSubjectFromValidJWT() {
        let token = makeJWT(payload: ["sub": "user-123", "exp": 1710000000])
        let result = JWTParser.parse(token)
        #expect(result?.subject == "user-123")
    }

    // Behaviour: When the app receives an auth token, it can determine when the
    // token expires so it knows when to refresh.
    @Test func parsesExpirationFromValidJWT() {
        let token = makeJWT(payload: ["sub": "user-123", "exp": 1710000000])
        let result = JWTParser.parse(token)
        #expect(result?.expiresAt == 1710000000)
    }

    // Behaviour: When the app receives a corrupted token (e.g. network error),
    // it gracefully returns nil instead of crashing.
    @Test func returnsNilForMalformedToken() {
        let result = JWTParser.parse("not-a-jwt")
        #expect(result == nil)
    }

    // Behaviour: When the app receives a token with invalid encoding, it
    // gracefully returns nil instead of crashing.
    @Test func returnsNilForTokenWithInvalidBase64() {
        let result = JWTParser.parse("header.!!!invalid!!!.signature")
        #expect(result == nil)
    }

    // Behaviour: When a token has no expiration claim (e.g. long-lived service token),
    // the subject is still parsed and expiresAt is nil.
    @Test func handlesPayloadWithOnlySubject() {
        let token = makeJWT(payload: ["sub": "user-456"])
        let result = JWTParser.parse(token)
        #expect(result?.subject == "user-456")
        #expect(result?.expiresAt == nil)
    }

}
