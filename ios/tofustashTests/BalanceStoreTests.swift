import Testing
@testable import tofustash

// Tests for BalanceStore — tracks the user's tofu currency balance.
@MainActor
struct BalanceStoreTests {

    private func makeSUT() -> BalanceStore {
        BalanceStore()
    }

    @Test("Initial balance is 0")
    func initialBalance() {
        let sut = makeSUT()
        #expect(sut.balance == 0)
    }

    @Test("addTofu increases the balance")
    func addTofu() {
        let sut = makeSUT()
        sut.addTofu(250)
        #expect(sut.balance == 250)
    }

    @Test("subtractTofu decreases the balance")
    func subtractTofu() {
        let sut = makeSUT()
        sut.addTofu(500)
        sut.subtractTofu(200)
        #expect(sut.balance == 300)
    }

    @Test("Multiple adds accumulate")
    func multipleAdds() {
        let sut = makeSUT()
        sut.addTofu(100)
        sut.addTofu(200)
        sut.addTofu(300)
        #expect(sut.balance == 600)
    }
}
