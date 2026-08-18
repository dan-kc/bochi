import Testing
@testable import bochi

@MainActor
struct OmniSearchStoreTests {
    // Behaviour: closing omni search should remove the overlay before clearing
    // the query, so users do not see empty search content flash during dismiss.
    @Test("Collapse dismisses before clearing query")
    func collapseDismissesBeforeClearingQuery() async throws {
        let store = OmniSearchStore()
        store.present()
        store.text = "alpha"

        store.collapse()

        #expect(store.isPresented == false)
        #expect(store.text == "alpha")

        try await Task.sleep(for: OmniSearchStore.collapseClearDelay + .milliseconds(80))

        #expect(store.text == "")
    }

    // Behaviour: if a user reopens search immediately, their fresh typing
    // should not be erased by the delayed cleanup from the previous close.
    @Test("Reopen before delayed cleanup preserves fresh query")
    func reopenBeforeDelayedCleanupPreservesFreshQuery() async throws {
        let store = OmniSearchStore()
        store.present()
        store.text = "alpha"

        store.collapse()
        store.present()
        store.text = "beta"

        try await Task.sleep(for: OmniSearchStore.collapseClearDelay + .milliseconds(80))

        #expect(store.isPresented)
        #expect(store.text == "beta")
    }
}
