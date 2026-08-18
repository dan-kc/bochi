import Foundation
import Testing
@testable import bochi

struct ApiErrorTests {

    // Behaviour: When sign-in cannot reach the backend at all, the user sees a
    // connectivity problem instead of a misleading account-specific failure.
    @Test func networkFailureExplainsServerIsUnreachable() {
        let error = ApiError.networkFailure(URLError(.cannotConnectToHost))

        #expect(error.userFacingMessage == "We couldn't connect to the server. Please try again.")
    }

    // Behaviour: When the backend returns multiple validation problems for one
    // auth action, the app shows every issue in one pass.
    @Test func validationErrorsAreCombinedForDisplay() {
        let error = ApiError(
            errors: [
                ApiErrorItem(code: "APPLE_IDENTITY_TOKEN_MISSING", message: "Apple did not return a sign-in token."),
                ApiErrorItem(code: "INVALID_APPLE_IDENTITY_TOKEN", message: "Invalid Apple identity token.")
            ],
            message: nil,
            statusCode: 400
        )

        #expect(error.userFacingMessage == """
Apple did not return a sign-in token.
Invalid Apple identity token.
""")
    }

    // Behaviour: When the app detects that a protected auth action has no active
    // signed-in session, the user gets a session/action message rather than a generic failure.
    @Test func localAuthStateFailureUsesExplicitMessage() {
        let error = ApiError.genericFailure(
            message: "You need to be signed in before you can sync."
        )

        #expect(error.userFacingMessage == "You need to be signed in before you can sync.")
    }
}
