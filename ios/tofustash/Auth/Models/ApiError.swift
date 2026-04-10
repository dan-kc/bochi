import Foundation

struct ApiErrorItem: Codable, Sendable {
    let code: String
    let message: String
}

// Conforming to Error protocol makes this throwable (like implementing std::error::Error in Rust).
struct ApiError: Error, Sendable {
    // `?` suffix = Optional -- like `T | null` in TS or `Option<T>` in Rust.
    let errors: [ApiErrorItem]?
    let message: String?
    let statusCode: Int?

    var displayMessage: String {
        // `if let` unwraps optionals -- like Rust's `if let Some(x) = ...`.
        // Shorthand: `if let errors` is sugar for `if let errors = errors` (same-name binding).
        if let errors, let first = errors.first {
            return first.message
        }
        // `??` is nil-coalescing -- same as `??` in TS or `.unwrap_or()` in Rust.
        return message ?? "An unknown error occurred"
    }
}

struct ApiErrorResponse: Codable {
    let errors: [ApiErrorItem]?
    let message: String?
}
