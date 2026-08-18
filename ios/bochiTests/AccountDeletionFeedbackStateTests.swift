import Testing
@testable import bochi

struct AccountDeletionFeedbackStateTests {

    // Behaviour: a successful deletion waits for the confirmation sheet to
    // disappear before showing the user that their account was deleted.
    @Test func successfulDeletionPresentsConfirmationAfterSheetDismissal() {
        var state = AccountDeletionFeedbackState()

        state.deletionSucceeded()

        #expect(state.isConfirmationPresented == false)

        state.sheetDismissed()

        #expect(state.isConfirmationPresented)
    }

    // Behaviour: closing the deletion sheet without deleting an account does
    // not show a misleading success confirmation.
    @Test func sheetDismissalWithoutDeletionDoesNotPresentConfirmation() {
        var state = AccountDeletionFeedbackState()

        state.sheetDismissed()

        #expect(state.isConfirmationPresented == false)
    }
}
