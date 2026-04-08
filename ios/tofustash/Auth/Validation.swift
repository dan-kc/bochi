import Foundation

private let emailRegex = try! NSRegularExpression(
    pattern: #"^[\w\.\-]+@[a-zA-Z\d\.\-]+\.[a-zA-Z]{2,}$"#
)

func validateEmail(_ email: String) -> [ValidationError] {
    var errors: [ValidationError] = []

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
    return validateEmail(email) + validatePassword(password)
}
