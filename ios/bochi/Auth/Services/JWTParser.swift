import Foundation

// struct = value type (like Rust struct, NOT a class). Copied on assignment, no reference sharing.
// String? = Optional<String>, like Rust's Option<String>. nil = None, a value = Some(value).
struct JWTPayload {
    let subject: String?
    let expiresAt: Int?
}

// enum with no cases = caseless enum. Used as a namespace (like a TS module or Go package-level funcs).
// Prevents instantiation — you can only call JWTParser.parse(), never create a JWTParser instance.
enum JWTParser {
    // static func = like a static method in a TS class. The _ means callers omit the label: parse(token) not parse(token: token).
    // Return type JWTPayload? = Optional, so this can return nil on failure (like Rust returning Option).
    static func parse(_ token: String) -> JWTPayload? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        // guard = early return. Like `if !condition { return }` but Swift enforces that the else branch exits scope.
        guard parts.count == 3 else { return nil }

        // var = mutable binding (let = immutable). Like Rust's let mut vs let.
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(contentsOf: String(repeating: "=", count: 4 - remainder))
        }

        // Multi-clause guard: both conditions must succeed or we bail. Commas act like && but each can bind a new variable.
        // try? = convert a throwing call to Optional (returns nil on error). Like Rust's .ok() on a Result.
        // `as? [String: Any]` = conditional downcast. Like a TS type guard — returns nil if the cast fails.
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        // as? String = conditional cast from Any to String. Like a TS `as` but safe — returns nil instead of crashing.
        let subject = json["sub"] as? String
        let expiresAt = json["exp"] as? Int

        return JWTPayload(subject: subject, expiresAt: expiresAt)
    }
}
