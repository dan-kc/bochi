import Foundation

// Tracks habit completion trades — each time a user "claims" a habit reward,
// a Trade is created here. The completion count feeds back into the reward
// calculation (frequency multiplier F), creating a feedback loop where doing
// a habit more often gradually reduces its per-completion reward.
//
// Follows the same pattern as HabitStore: @Observable for automatic SwiftUI
// reactivity, @MainActor for thread safety, in-memory storage.
@Observable
@MainActor
final class TradeStore {

    // All trades, ordered by creation time (newest last).
    // `private(set)` means views can read but only this class can write.
    private(set) var trades: [Trade] = []

    // Creates a trade for completing a habit and appends it to the store.
    // Like dispatching an "addTrade" action in Redux/Zustand.
    func addTrade(habitId: String, amount: Int) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: habitId,
            amount: amount,
            createdAt: Date()
        )
        trades.append(trade)
    }

    // Creates a trade with a specific date — used by tests to simulate
    // trades that happened in the past.
    func addTradeWithDate(habitId: String, amount: Int, createdAt: Date) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: habitId,
            amount: amount,
            createdAt: createdAt
        )
        trades.append(trade)
    }

    // Counts how many times a habit was completed within the last N days.
    // This count feeds into the reward formula's frequency multiplier (F),
    // which reduces rewards for habits that are completed too frequently.
    //
    // Like tradeStore.getTradesInPeriod(userId, habitId, days) in the
    // frontend, but without userId since the iOS app is single-user.
    func tradesInPeriod(habitId: String, days: Int) -> Int {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.habitId == habitId && $0.createdAt >= cutoff
        }.count
    }
}
