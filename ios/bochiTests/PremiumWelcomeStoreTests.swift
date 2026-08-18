import Testing
@testable import bochi

@MainActor
struct PremiumWelcomeStoreTests {

    // Behaviour: the root presentation task should ignore stale delayed
    // requests so only the latest successful purchase can open the welcome.
    @Test func stalePresentationRequestDoesNotOpenWelcome() {
        let store = PremiumWelcomeStore()

        store.requestPresentation()
        let firstRequestID = store.presentationRequestID
        store.requestPresentation()

        store.present(requestID: firstRequestID)

        #expect(store.isPresented == false)
    }

    // Behaviour: a current request opens the welcome sheet and dismissal clears it.
    @Test func currentPresentationRequestCanOpenAndDismissWelcome() {
        let store = PremiumWelcomeStore()

        store.requestPresentation()
        store.present(requestID: store.presentationRequestID)

        #expect(store.isPresented == true)

        store.dismiss()

        #expect(store.isPresented == false)
    }
}
