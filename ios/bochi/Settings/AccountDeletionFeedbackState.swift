struct AccountDeletionFeedbackState {
    private(set) var isConfirmationPresented = false
    private var shouldConfirmAfterSheetDismissal = false

    mutating func deletionSucceeded() {
        shouldConfirmAfterSheetDismissal = true
    }

    mutating func sheetDismissed() {
        guard shouldConfirmAfterSheetDismissal else { return }

        shouldConfirmAfterSheetDismissal = false
        isConfirmationPresented = true
    }

    mutating func setConfirmationPresented(_ isPresented: Bool) {
        isConfirmationPresented = isPresented
    }
}
