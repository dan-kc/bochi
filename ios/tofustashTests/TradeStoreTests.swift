import Foundation
import Testing
@testable import tofustash

// Tests for TradeStore — tracks habit completion trades and provides
// completion counts for reward price calculations.
@MainActor
struct TradeStoreTests {

    private func makeSUT() -> TradeStore {
        TradeStore()
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
        sut.addTrade(habitId: "habit-1", amount: 250)
        #expect(sut.trades.count == 1)
        #expect(sut.trades[0].habitId == "habit-1")
        #expect(sut.trades[0].amount == 250)
    }

    // Behaviour: Two completions of the same habit create two distinct history entries.
    @Test("addTrade generates a unique ID for each trade")
    func uniqueIds() {
        let sut = makeSUT()
        sut.addTrade(habitId: "h1", amount: 100)
        sut.addTrade(habitId: "h1", amount: 200)
        #expect(sut.trades[0].id != sut.trades[1].id)
    }

    // Behaviour: Reward calculations only count this habit's recent completions inside the selected window.
    @Test("tradesInPeriod counts trades for the specified habit within the period")
    func countsCorrectly() {
        let sut = makeSUT()
        sut.addTrade(habitId: "h1", amount: 100)
        sut.addTrade(habitId: "h1", amount: 200)
        #expect(sut.tradesInPeriod(habitId: "h1", days: 7) == 2)
    }

    // Behaviour: Another habit's completions do not lower this habit's reward.
    @Test("tradesInPeriod excludes trades for other habits")
    func excludesOtherHabits() {
        let sut = makeSUT()
        sut.addTrade(habitId: "h1", amount: 100)
        sut.addTrade(habitId: "h2", amount: 200)
        #expect(sut.tradesInPeriod(habitId: "h1", days: 7) == 1)
    }

    // Behaviour: Old completions fall out of the recent window so stale history stops affecting current rewards.
    @Test("tradesInPeriod excludes trades older than the period")
    func excludesOldTrades() {
        let sut = makeSUT()
        // Add a trade that's 10 days old
        sut.addTradeWithDate(habitId: "h1", amount: 100, createdAt: Date(timeIntervalSinceNow: -10 * 86400))
        // Add a fresh trade
        sut.addTrade(habitId: "h1", amount: 200)
        // 7-day window should only include the fresh trade
        #expect(sut.tradesInPeriod(habitId: "h1", days: 7) == 1)
    }
}
