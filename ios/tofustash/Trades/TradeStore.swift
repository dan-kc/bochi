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

    // Completion history in the order it happened. Other parts of the app read
    // this to show reward state and derive recent completion counts.
    private(set) var trades: [Trade] = []

    // Records one user completion at the current time.
    func addTrade(habitId: String, amount: Int) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: habitId,
            amount: amount,
            createdAt: Date()
        )
        trades.append(trade)
    }

    // Test-only helper for simulating older completions.
    func addTradeWithDate(habitId: String, amount: Int, createdAt: Date) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: habitId,
            amount: amount,
            createdAt: createdAt
        )
        trades.append(trade)
    }

    // This is the count the reward formula uses for "how many times has the
    // user already done this habit recently?"
    func tradesInPeriod(habitId: String, days: Int) -> Int {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.habitId == habitId && $0.createdAt >= cutoff
        }.count
    }
}
