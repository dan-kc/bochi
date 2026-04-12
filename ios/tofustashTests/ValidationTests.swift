import Testing
@testable import tofustash

struct ValidationTests {

    // MARK: - Email validation  ← MARK is a pragma for Xcode's jump bar (like #region in TS, but actually useful)

    @Test func validEmailPasses() {
        let errors = validateEmail("user@example.com")
        #expect(errors.isEmpty)
    }

    @Test func emailWithoutAtSignFails() {
        let errors = validateEmail("userexample.com")
        #expect(errors.contains(.invalidEmailAddress))
    }

    @Test func emailWithoutTLDFails() {
        let errors = validateEmail("user@example")
        #expect(errors.contains(.invalidEmailAddress))
    }

    @Test func emptyEmailFails() {
        let errors = validateEmail("")
        #expect(errors.contains(.invalidEmailAddress))
    }

    @Test func emailOver254CharsFails() {
        let longLocal = String(repeating: "a", count: 243)
        let email = "\(longLocal)@example.com" // 255 chars
        let errors = validateEmail(email)
        #expect(errors.contains(.emailTooLong))
    }

    @Test func emailExactly254CharsPasses() {
        let longLocal = String(repeating: "a", count: 242)
        let email = "\(longLocal)@example.com" // 254 chars
        let errors = validateEmail(email)
        #expect(!errors.contains(.emailTooLong))
    }

    // MARK: - Password validation

    @Test func validPasswordPasses() {
        let errors = validatePassword("securepass123")
        #expect(errors.isEmpty)
    }

    @Test func passwordExactly8CharsPasses() {
        let errors = validatePassword("12345678")
        #expect(errors.isEmpty)
    }

    @Test func passwordExactly64CharsPasses() {
        let errors = validatePassword(String(repeating: "a", count: 64))
        #expect(errors.isEmpty)
    }

    @Test func passwordUnder8CharsFails() {
        let errors = validatePassword("short")
        #expect(errors.contains(.passwordTooShort))
    }

    @Test func passwordOver64CharsFails() {
        let errors = validatePassword(String(repeating: "a", count: 65))
        #expect(errors.contains(.passwordTooLong))
    }

    @Test func passwordWithNonASCIIFails() {
        let errors = validatePassword("pässwörd123")
        #expect(errors.contains(.passwordNotAscii))
    }

    @Test func emptyPasswordFails() {
        let errors = validatePassword("")
        #expect(errors.contains(.passwordTooShort))
    }

    // MARK: - Combined validation

    @Test func validAuthInputReturnsNoErrors() {
        let errors = validateAuthInput(email: "user@example.com", password: "securepass123")
        #expect(errors.isEmpty)
    }

    @Test func invalidBothReturnsMultipleErrors() {
        let errors = validateAuthInput(email: "invalid", password: "short")
        #expect(errors.contains(.invalidEmailAddress))
        #expect(errors.contains(.passwordTooShort))
    }

}
