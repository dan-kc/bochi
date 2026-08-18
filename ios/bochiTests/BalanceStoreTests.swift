import Testing
@testable import bochi

// Tests for BalanceStore — tracks the user's points currency balance.
@MainActor
struct BalanceStoreTests {

    private func makeSUT() -> BalanceStore {
        BalanceStore(storageURL: TestHelpers.makeTemporaryFileURL("balances"))
    }

    // Behaviour: A brand-new user starts with no points before completing any recurringTasks.
    @Test("Initial balance is 0")
    func initialBalance() {
        let sut = makeSUT()
        #expect(sut.balance == 0)
    }

    // Behaviour: Completing a recurringTask increases the points balance by that price amount.
    @Test("addPoints increases the balance")
    func addPoints() {
        let sut = makeSUT()
        sut.addPoints(250)
        #expect(sut.balance == 250)
    }

    // Behaviour: Spending points decreases the balance by the purchase cost.
    @Test("subtractPoints decreases the balance")
    func subtractPoints() {
        let sut = makeSUT()
        sut.addPoints(500)
        sut.subtractPoints(200)
        #expect(sut.balance == 300)
    }

    // Behaviour: Multiple earned rewards accumulate into one running balance.
    @Test("Multiple adds accumulate")
    func multipleAdds() {
        let sut = makeSUT()
        sut.addPoints(100)
        sut.addPoints(200)
        sut.addPoints(300)
        #expect(sut.balance == 600)
    }
}
