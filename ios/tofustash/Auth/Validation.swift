import Foundation

// `private` at file scope = only visible in this file (like Go's unexported lowercase names).
// `try!` force-unwraps a throwing call -- crashes if it throws. Like `.unwrap()` in Rust.
// `#"..."#` is a raw string literal -- like r#"..."# in Rust. No need to escape backslashes.
private let emailRegex = try! NSRegularExpression(
    pattern: #"^[\w\.\-]+@[a-zA-Z\d\.\-]+\.[a-zA-Z]{2,}$"#
)

// `_` before param name means callers omit the label: `validateEmail(str)` not `validateEmail(email: str)`.
func validateEmail(_ email: String) -> [ValidationError] {
    // `var` = mutable binding (vs `let` = immutable). Like `let mut` in Rust.
    var errors: [ValidationError] = []

    // NSRange bridge needed because NSRegularExpression is Obj-C API, not native Swift.
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

    // Closure syntax: { params in body }. `$0` is shorthand for first arg (like Rust's |c| c).
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
