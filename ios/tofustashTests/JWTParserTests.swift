import Foundation
import Testing
@testable import tofustash

struct JWTParserTests {

    // Helper to create a fake JWT with a given payload
    private func makeJWT(payload: [String: Any]) -> String {
        let header = Data("{}".utf8).base64EncodedString()
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let signature = "fakesig"
        return "\(header).\(payloadBase64).\(signature)"
    }

    @Test func parsesSubjectFromValidJWT() {
        let token = makeJWT(payload: ["sub": "user-123", "exp": 1710000000])
        let result = JWTParser.parse(token)
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

    @Test func returnsNilForEmptyString() {
        let result = JWTParser.parse("")
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

    @Test func handlesPayloadWithOnlyExpiration() {
        let token = makeJWT(payload: ["exp": 1710000000])
        let result = JWTParser.parse(token)
        #expect(result?.subject == nil)
        #expect(result?.expiresAt == 1710000000)
    }
}
