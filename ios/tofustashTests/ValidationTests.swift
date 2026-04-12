import Testing
@testable import tofustash

struct ValidationTests {

    // MARK: - Email validation  ← MARK is a pragma for Xcode's jump bar (like #region in TS, but actually useful)

    // Behaviour: When a user enters a valid email address, no validation errors are shown.
    @Test func validEmailPasses() {
        let errors = validateEmail("user@example.com")
        #expect(errors.isEmpty)
    }

    // Behaviour: When a user enters an email without an @ sign, they see an invalid email error.
    @Test func emailWithoutAtSignFails() {
        let errors = validateEmail("userexample.com")
        #expect(errors.contains(.invalidEmailAddress))
    }

    // Behaviour: When a user enters an email without a domain extension (e.g. "user@example"),
    // they see an invalid email error.
    @Test func emailWithoutTLDFails() {
        let errors = validateEmail("user@example")
        #expect(errors.contains(.invalidEmailAddress))
    }

    // Behaviour: When a user submits the form with an empty email field, they see
    // an invalid email error.
    @Test func emptyEmailFails() {
        let errors = validateEmail("")
        #expect(errors.contains(.invalidEmailAddress))
    }

    // Behaviour: When a user enters an email longer than 254 characters (RFC 5321 limit),
    // they see a "too long" error.
    @Test func emailOver254CharsFails() {
        let longLocal = String(repeating: "a", count: 243)
        let email = "\(longLocal)@example.com" // 255 chars
        let errors = validateEmail(email)
        #expect(errors.contains(.emailTooLong))
    }

    // Behaviour: An email of exactly 254 characters (the RFC maximum) is accepted.
    @Test func emailExactly254CharsPasses() {
        let longLocal = String(repeating: "a", count: 242)
        let email = "\(longLocal)@example.com" // 254 chars
        let errors = validateEmail(email)
        #expect(!errors.contains(.emailTooLong))
    }

    // MARK: - Password validation

    // Behaviour: When a user enters a valid password (8-64 ASCII chars), no
    // validation errors are shown.
    @Test func validPasswordPasses() {
        let errors = validatePassword("securepass123")
        #expect(errors.isEmpty)
    }

    // Behaviour: A password of exactly 8 characters (the minimum) is accepted.
    @Test func passwordExactly8CharsPasses() {
        let errors = validatePassword("12345678")
        #expect(errors.isEmpty)
    }

    // Behaviour: A password of exactly 64 characters (the maximum) is accepted.
    @Test func passwordExactly64CharsPasses() {
        let errors = validatePassword(String(repeating: "a", count: 64))
        #expect(errors.isEmpty)
    }

    // Behaviour: When a user enters a password shorter than 8 characters, they
    // see a "too short" error.
    @Test func passwordUnder8CharsFails() {
        let errors = validatePassword("short")
        #expect(errors.contains(.passwordTooShort))
    }

    // Behaviour: When a user enters a password longer than 64 characters, they
    // see a "too long" error.
    @Test func passwordOver64CharsFails() {
        let errors = validatePassword(String(repeating: "a", count: 65))
        #expect(errors.contains(.passwordTooLong))
    }

    // Behaviour: When a user enters a password with non-ASCII characters (e.g.
    // accented letters), they see a "not ASCII" error.
    @Test func passwordWithNonASCIIFails() {
        let errors = validatePassword("pässwörd123")
        #expect(errors.contains(.passwordNotAscii))
    }

    // Behaviour: When a user submits the form with an empty password field, they
    // see a "too short" error.
    @Test func emptyPasswordFails() {
        let errors = validatePassword("")
        #expect(errors.contains(.passwordTooShort))
    }

    // MARK: - Combined validation

    // Behaviour: When a user enters valid email and password, the form has no errors
    // and can be submitted.
    @Test func validAuthInputReturnsNoErrors() {
        let errors = validateAuthInput(email: "user@example.com", password: "securepass123")
        #expect(errors.isEmpty)
    }

    // Behaviour: When a user enters both an invalid email and invalid password,
    // they see errors for both fields at once (not one at a time).
    @Test func invalidBothReturnsMultipleErrors() {
        let errors = validateAuthInput(email: "invalid", password: "short")
        #expect(errors.contains(.invalidEmailAddress))
        #expect(errors.contains(.passwordTooShort))
    }

}
