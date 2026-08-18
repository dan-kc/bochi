import Foundation
import Testing
@testable import bochi

@MainActor
struct AppNavigationStoreTests {
    // Behaviour: launching the app should land on Earn so the user sees every
    // available earning action before choosing a narrower entity list.
    @Test func defaultSelectedTabIsEarn() {
        let store = AppNavigationStore()

        #expect(store.selectedTab == .earn)
    }

    // Behaviour: a successful create can queue a reveal request so the owning
    // list highlights the new item after the shared sheet dismisses.
    @Test func queueEntityRevealStoresPendingRevealRequest() {
        let store = AppNavigationStore()
        let route = PendingEntityFormRoute.recurringTask(RecordID("recurringTask-1"))

        store.queueEntityReveal(route)

        #expect(store.pendingEntityRevealRequest?.route == route)
    }
}
