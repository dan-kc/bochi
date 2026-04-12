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

    // @Test = Jest's test() / it(). The func name is the test label.
    @Test func parsesSubjectFromValidJWT() {
        let token = makeJWT(payload: ["sub": "user-123", "exp": 1710000000])
        let result = JWTParser.parse(token)
        // #expect() = Jest's expect().toBe(). It's a macro (compile-time code transform, like Rust macros).
        // ?. is optional chaining — same as TS's ?.
        #expect(result?.subject == "user-123")
    }

    @Test func parsesExpirationFromValidJWT() {
        let token = makeJWT(payload: ["sub": "user-123", "exp": 1710000000])
        let result = JWTParser.parse(token)
        #expect(result?.expiresAt == 1710000000)
    }

    @Test func returnsNilForMalformedToken() {
        let result = JWTParser.parse("not-a-jwt")
        #expect(result == nil)
    }

    @Test func returnsNilForTokenWithInvalidBase64() {
        let result = JWTParser.parse("header.!!!invalid!!!.signature")
        #expect(result == nil)
    }

    @Test func handlesPayloadWithOnlySubject() {
        let token = makeJWT(payload: ["sub": "user-456"])
        let result = JWTParser.parse(token)
        #expect(result?.subject == "user-456")
        #expect(result?.expiresAt == nil)
    }

}
