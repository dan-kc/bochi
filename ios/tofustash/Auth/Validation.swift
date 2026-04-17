import Foundation

// These helpers define what the auth forms treat as acceptable user input.
// They return explicit validation errors so the UI can show all relevant
// feedback at once instead of failing one field at a time.
//
// `#"..."#` is Swift's raw string literal syntax, which keeps regexes readable.
private let emailRegex = try! NSRegularExpression(
    pattern: #"^[\w\.\-]+@[a-zA-Z\d\.\-]+\.[a-zA-Z]{2,}$"#
)

func validateEmail(_ email: String) -> [ValidationError] {
    var errors: [ValidationError] = []

    // NSRegularExpression is an older Foundation API, so Swift strings must be
    // bridged into `NSRange` before matching.
    let range = NSRange(email.startIndex..., in: email)
    if emailRegex.firstMatch(in: email, range: range) == nil {
        errors.append(.invalidEmailAddress)
    }
    if email.count > 254 {
        errors.append(.emailTooLong)
    }

    return errors
}

func validatePassword(_ password: String) -> [ValidationError] {
    var errors: [ValidationError] = []

    // Passwords are intentionally restricted to ASCII here so backend and client
    // validation behave the same for every user.
    if !password.allSatisfy({ $0.asciiValue != nil }) {
        errors.append(.passwordNotAscii)
    }
    if password.count > 64 {
        errors.append(.passwordTooLong)
    }
    if password.count < 8 {
        errors.append(.passwordTooShort)
    }

    return errors
}

func validateAuthInput(email: String, password: String) -> [ValidationError] {
    // Concatenate the two error arrays so the UI can show both field problems
    // from a single submit attempt.
    return validateEmail(email) + validatePassword(password)
}
