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

    // Behaviour: refunding a trade should append a compensating ledger row
    // instead of mutating the original trade in place.
    @Test("refunding a trade appends a compensating trade and updates balance")
    func refundingTradeCreatesCompensatingEntry() throws {
        let storageURL = makeStorageURL("refundable-trades")
        let tradeStore = makeSUT(storageURL: storageURL)
        let balanceStore = makeBalanceStore(storageURL: storageURL)
        let refundedAt = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addHabitTrade(id: "trade-1", habitId: "habit-1", amount: 250, shouldNotifySync: false)
        balanceStore.refresh()
        #expect(balanceStore.balance == 250)

        let refundTrade = try #require(
            tradeStore.refundTrade(id: "trade-1", refundedAt: refundedAt, shouldNotifySync: false)
        )
        balanceStore.refresh()

        let originalTrade = try #require(tradeStore.trades.first(where: { $0.id == "trade-1" }))
        #expect(originalTrade.refundsTradeId == nil)
        #expect(refundTrade.amount == -250)
        #expect(refundTrade.habitId == "habit-1")
        #expect(refundTrade.refundsTradeId == originalTrade.id)
        #expect(tradeStore.trades.count == 2)
        #expect(balanceStore.balance == 0)
    }

    // Behaviour: refunds should only reverse the latest unresolved trade for a
    // source, so older prices cannot be cherry-picked after later activity.
    @Test("refunding an older trade is rejected when a newer source trade exists")
    func refundingOlderTradeIsRejected() {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addHabitTrade(id: "habit-trade-1", habitId: "habit-1", amount: 100, createdAt: firstDate, shouldNotifySync: false)
        sut.addHabitTrade(id: "habit-trade-2", habitId: "habit-1", amount: 200, createdAt: secondDate, shouldNotifySync: false)

        let refundTrade = sut.refundTrade(
            id: "habit-trade-1",
            refundedAt: secondDate.addingTimeInterval(60),
            shouldNotifySync: false
        )

        #expect(refundTrade == nil)
        #expect(sut.trades.count == 2)
    }

    // Behaviour: refunds should never appear before the trade they reverse,
    // even if a caller passes an invalid timestamp directly to the store.
    @Test("refunding a trade before its created date is rejected")
    func refundingTradeBeforeOriginalTimeIsRejected() {
        let sut = makeSUT()
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)

        sut.addHabitTrade(
            id: "habit-trade-1",
            habitId: "habit-1",
            amount: 100,
            createdAt: originalDate,
            shouldNotifySync: false
        )

        let refundTrade = sut.refundTrade(
            id: "habit-trade-1",
            refundedAt: originalDate.addingTimeInterval(-1),
            shouldNotifySync: false
        )

        #expect(refundTrade == nil)
        #expect(sut.trades.count == 1)
    }

    // Behaviour: if two source trades share a created timestamp, the latest
    // unresolved one should be chosen using the same updatedAt tie-breaker the
    // backend uses during refund validation.
    @Test("latest task trade prefers the newer updated timestamp when createdAt ties")
    func latestTaskTradeUsesUpdatedAtTieBreaker() throws {
        let sut = makeSUT()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let firstUpdatedAt = createdAt
        let secondUpdatedAt = createdAt.addingTimeInterval(5)

        sut.addTaskTrade(
            id: "task-trade-1",
            taskId: "task-1",
            amount: 100,
            createdAt: createdAt,
            updatedAt: firstUpdatedAt,
            shouldNotifySync: false
        )
        sut.addTaskTrade(
            id: "task-trade-2",
            taskId: "task-1",
            amount: 120,
            createdAt: createdAt,
            updatedAt: secondUpdatedAt,
            shouldNotifySync: false
        )

        let latestTrade = try #require(sut.latestTaskTrade(taskId: "task-1", includeRefunded: false))
        #expect(latestTrade.id == "task-trade-2")
    }

    // Behaviour: refund trades should stop influencing pricing and lockout
    // calculations that depend on unresolved source timestamps.
    @Test("refund trades exclude the reversed activity from pricing selectors")
    func refundTradesAreExcludedFromActiveSelectors() {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addHabitTrade(id: "habit-trade-1", habitId: "habit-1", amount: 100, createdAt: firstDate, shouldNotifySync: false)
        sut.addHabitTrade(id: "habit-trade-2", habitId: "habit-1", amount: 200, createdAt: secondDate, shouldNotifySync: false)
        sut.addRewardPurchase(id: "reward-trade-1", rewardId: "reward-1", amount: -50, createdAt: secondDate, shouldNotifySync: false)

        _ = sut.refundTrade(id: "habit-trade-2", refundedAt: secondDate.addingTimeInterval(60), shouldNotifySync: false)
        _ = sut.refundTrade(id: "reward-trade-1", refundedAt: secondDate.addingTimeInterval(120), shouldNotifySync: false)

        #expect(sut.habitTradeDates(habitId: "habit-1") == [firstDate])
        #expect(sut.habitCompletionCount(habitId: "habit-1") == 1)
        #expect(sut.rewardPurchaseDates(rewardId: "reward-1").isEmpty)
    }
}
