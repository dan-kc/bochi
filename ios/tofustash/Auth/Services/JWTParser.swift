import Foundation

struct JWTPayload {
    let subject: String?
    let expiresAt: Int?
}

enum JWTParser {
    static func parse(_ token: String) -> JWTPayload? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(contentsOf: String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let subject = json["sub"] as? String
        let expiresAt = json["exp"] as? Int

        return JWTPayload(subject: subject, expiresAt: expiresAt)
    }
}
