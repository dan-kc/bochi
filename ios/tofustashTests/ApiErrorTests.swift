import Foundation
import Testing
@testable import tofustash

struct ApiErrorTests {

    // Behaviour: When a login attempt cannot reach the backend at all, the user
    // sees a connectivity problem instead of being told their password was wrong.
    @Test func networkFailureExplainsServerIsUnreachable() {
        let error = ApiError.networkFailure(URLError(.cannotConnectToHost))

        #expect(error.userFacingMessage == "We couldn't connect to the server. Please try again.")
    }

    // Behaviour: When the backend returns multiple validation problems for one
    // auth action, the app shows every issue so the user can fix the full form in one pass.
    @Test func validationErrorsAreCombinedForDisplay() {
        let error = ApiError(
            errors: [
                ApiErrorItem(code: "INVALID_EMAIL_ADDRESS", message: "Invalid email address."),
                ApiErrorItem(code: "PASSWORD_TOO_SHORT", message: "Password too short. The min password length is 8.")
            ],
            message: nil,
            statusCode: 400
        )

        #expect(error.userFacingMessage == """
Invalid email address.
Password too short. The min password length is 8.
""")
    }

    // Behaviour: When the app detects that a protected auth action has no active
    // signed-in session, the user gets a session/action message rather than a generic failure.
    @Test func localAuthStateFailureUsesExplicitMessage() {
        let error = ApiError.genericFailure(
            message: "You need to be signed in before you can change your email."
        )

        #expect(error.userFacingMessage == "You need to be signed in before you can change your email.")
    }
}
