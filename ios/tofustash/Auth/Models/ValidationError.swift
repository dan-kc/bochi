enum ValidationError: Equatable, Sendable {
    case invalidEmailAddress
    case emailTooLong
    case passwordNotAscii
    case passwordTooLong
    case passwordTooShort

    var message: String {
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
