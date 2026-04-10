// Like a Rust enum (no associated data here). Equatable = derive(PartialEq), Sendable = Send+Sync.
enum ValidationError: Equatable, Sendable {
    case invalidEmailAddress
    case emailTooLong
    case passwordNotAscii
    case passwordTooLong
    case passwordTooShort

    // Computed property -- like a getter in TS. No stored backing; re-evaluates each access.
    var message: String {
        // switch must be exhaustive (like Rust's match), compiler enforces all cases handled.
        switch self {
        case .invalidEmailAddress:
            return "Please enter a valid email address"
        case .emailTooLong:
            return "Email address is too long (max 254 characters)"
        case .passwordNotAscii:
            return "Password must contain only ASCII characters"
        case .passwordTooLong:
            return "Password is too long (max 64 characters)"
        case .passwordTooShort:
            return "Password must be at least 8 characters"
        }
    }
}
