import Testing
@testable import tofustash

// Tests for BalanceStore — tracks the user's tofu currency balance.
@MainActor
struct BalanceStoreTests {

    private func makeSUT() -> BalanceStore {
        BalanceStore(storageURL: TestHelpers.makeTemporaryFileURL("balances"))
    }

    // Behaviour: A brand-new user starts with no tofu before completing any habits.
    @Test("Initial balance is 0")
    func initialBalance() {
        let sut = makeSUT()
        #expect(sut.balance == 0)
    }

    // Behaviour: Completing a habit increases the tofu balance by that reward amount.
    @Test("addTofu increases the balance")
    func addTofu() {
        let sut = makeSUT()
        sut.addTofu(250)
        #expect(sut.balance == 250)
    }

    // Behaviour: Spending tofu decreases the balance by the purchase cost.
    @Test("subtractTofu decreases the balance")
    func subtractTofu() {
        let sut = makeSUT()
        sut.addTofu(500)
        sut.subtractTofu(200)
        #expect(sut.balance == 300)
    }

    // Behaviour: Multiple earned rewards accumulate into one running balance.
    @Test("Multiple adds accumulate")
    func multipleAdds() {
        let sut = makeSUT()
        sut.addTofu(100)
        sut.addTofu(200)
        sut.addTofu(300)
        #expect(sut.balance == 600)
    }
}
