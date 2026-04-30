import Foundation
import Testing
@testable import tofustash

// Tests for TradeStore — tracks habit completion/reward purchase history and
// exposes timestamp lists for pricing calculations.
@MainActor
struct TradeStoreTests {

    private func makeStorageURL(_ name: String = "trades") -> URL {
        TestHelpers.makeTemporaryFileURL(name)
    }

    private func makeSUT(storageURL: URL? = nil) -> TradeStore {
        TradeStore(storageURL: storageURL ?? makeStorageURL())
    }

    private func makeBalanceStore(storageURL: URL) -> BalanceStore {
        BalanceStore(storageURL: storageURL)
    }

    // Behaviour: Before the user completes any habits, there is no trade history.
    @Test("Initial store has no trades")
    func initiallyEmpty() {
        let sut = makeSUT()
        #expect(sut.trades.isEmpty)
    }

    // Behaviour: Completing a habit records a trade with the correct habit and reward amount.
    @Test("addTrade appends a trade with the correct habitId and amount")
    func addTradeAppends() {
        let sut = makeSUT()
        sut.addHabitTrade(habitId: "habit-1", amount: 250)
        #expect(sut.trades.count == 1)
        #expect(sut.trades[0].habitId == "habit-1")
        #expect(sut.trades[0].rewardId == nil)
        #expect(sut.trades[0].amount == 250)
    }

    // Behaviour: Two completions of the same habit create two distinct history entries.
    @Test("addTrade generates a unique ID for each trade")
    func uniqueIds() {
        let sut = makeSUT()
        sut.addHabitTrade(habitId: "h1", amount: 100)
        sut.addHabitTrade(habitId: "h1", amount: 200)
        #expect(sut.trades[0].id != sut.trades[1].id)
    }

    // Behaviour: Habit pricing only sees completion timestamps for the selected
    // habit, in chronological order.
    @Test("habitTradeDates returns matching habit completion timestamps")
    func habitTradeDatesAreScopedAndOrdered() {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addHabitTradeWithDate(habitId: "h1", amount: 100, createdAt: firstDate)
        sut.addHabitTradeWithDate(habitId: "h1", amount: 200, createdAt: secondDate)

        #expect(sut.habitTradeDates(habitId: "h1") == [firstDate, secondDate])
    }

    // Behaviour: Another habit's completions do not lower this habit's reward.
    @Test("habitTradeDates excludes trades for other habits")
    func habitTradeDatesExcludeOtherHabits() {
        let sut = makeSUT()
        sut.addHabitTrade(habitId: "h1", amount: 100)
        sut.addHabitTrade(habitId: "h2", amount: 200)
        #expect(sut.habitTradeDates(habitId: "h1").count == 1)
    }

    // Behaviour: Old completions still remain in history because the pricing
    // curve now fades them continuously instead of dropping them at a hard cutoff.
    @Test("habitTradeDates keeps older completion timestamps")
    func habitTradeDatesKeepOlderTrades() {
        let sut = makeSUT()
        let olderDate = Date(timeIntervalSinceNow: -10 * 86400)
        let freshDate = Date()

        sut.addHabitTradeWithDate(habitId: "h1", amount: 100, createdAt: olderDate)
        sut.addHabitTradeWithDate(habitId: "h1", amount: 200, createdAt: freshDate)

        #expect(sut.habitTradeDates(habitId: "h1").count == 2)
    }

    // Behaviour: Reward pricing only counts past purchases of that same reward,
    // not habit completions or purchases of other rewards.
    @Test("rewardPurchaseDates returns only matching reward purchases")
    func rewardPurchasesAreScopedToReward() {
        let sut = makeSUT()
        sut.addRewardPurchase(rewardId: "reward-1", amount: -250)
        sut.addRewardPurchase(rewardId: "reward-1", amount: -300)
        sut.addRewardPurchase(rewardId: "reward-2", amount: -150)
        sut.addHabitTrade(habitId: "habit-1", amount: 100)

        #expect(sut.rewardPurchaseDates(rewardId: "reward-1").count == 2)
    }

    // Behaviour: Completing a task should create trade history tied to that
    // task, without pretending it came from a habit or reward.
    @Test("addTaskTrade stores a task-linked trade")
    func addTaskTradeStoresTaskSource() {
        let sut = makeSUT()
        sut.addTaskTrade(taskId: "task-1", amount: 120)

        #expect(sut.trades.count == 1)
        #expect(sut.trades[0].taskId == "task-1")
        #expect(sut.trades[0].habitId == nil)
        #expect(sut.trades[0].rewardId == nil)
    }

    // Behaviour: refunding a trade should remove it from the running balance
    // without erasing the history row, and un-refunding should restore it.
    @Test("refunding a trade updates balance without deleting the record")
    func refundingTradeUpdatesBalance() throws {
        let storageURL = makeStorageURL("refundable-trades")
        let tradeStore = makeSUT(storageURL: storageURL)
        let balanceStore = makeBalanceStore(storageURL: storageURL)
        let refundedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let unrefundedAt = refundedAt.addingTimeInterval(300)

        tradeStore.addHabitTrade(id: "trade-1", habitId: "habit-1", amount: 250, shouldNotifySync: false)
        balanceStore.refresh()
        #expect(balanceStore.balance == 250)

        tradeStore.refundTrade(id: "trade-1", refundedAt: refundedAt, shouldNotifySync: false)
        balanceStore.refresh()

        let refundedTrade = try #require(tradeStore.trades.first(where: { $0.id == "trade-1" }))
        #expect(refundedTrade.refundedAt == refundedAt)
        #expect(balanceStore.balance == 0)

        tradeStore.unrefundTrade(id: "trade-1", updatedAt: unrefundedAt, shouldNotifySync: false)
        balanceStore.refresh()

        let activeTrade = try #require(tradeStore.trades.first(where: { $0.id == "trade-1" }))
        #expect(activeTrade.refundedAt == nil)
        #expect(balanceStore.balance == 250)
    }

    // Behaviour: refunded trades should stop influencing pricing and lockout
    // calculations that depend on active trade timestamps.
    @Test("refunding a trade excludes it from active trade selectors")
    func refundedTradesAreExcludedFromActiveSelectors() {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addHabitTrade(id: "habit-trade-1", habitId: "habit-1", amount: 100, createdAt: firstDate, shouldNotifySync: false)
        sut.addHabitTrade(id: "habit-trade-2", habitId: "habit-1", amount: 200, createdAt: secondDate, shouldNotifySync: false)
        sut.addRewardPurchase(id: "reward-trade-1", rewardId: "reward-1", amount: -50, createdAt: secondDate, shouldNotifySync: false)

        sut.refundTrade(id: "habit-trade-2", refundedAt: secondDate.addingTimeInterval(60), shouldNotifySync: false)
        sut.refundTrade(id: "reward-trade-1", refundedAt: secondDate.addingTimeInterval(120), shouldNotifySync: false)

        #expect(sut.habitTradeDates(habitId: "habit-1") == [firstDate])
        #expect(sut.habitCompletionCount(habitId: "habit-1") == 1)
        #expect(sut.rewardPurchaseDates(rewardId: "reward-1").isEmpty)
    }
}
