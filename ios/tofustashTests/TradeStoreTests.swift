import Foundation
import Testing
@testable import tofustash

// Tests for TradeStore — tracks habit completion/reward purchase history and
// exposes timestamp lists for pricing calculations.
@MainActor
struct TradeStoreTests {

    private func makeSUT() -> TradeStore {
        TradeStore(storageURL: TestHelpers.makeTemporaryFileURL("trades"))
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
}
