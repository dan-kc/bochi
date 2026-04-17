import Foundation

// Tracks every tofu-changing event in the app: habit completions add tofu and
// reward purchases subtract tofu. The same store therefore feeds both the
// habit frequency curve and the reward max-frequency curve.
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
    func addHabitTrade(habitId: String, amount: Int) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: habitId,
            rewardId: nil,
            amount: amount,
            createdAt: Date()
        )
        trades.append(trade)
    }

    // Records one reward purchase. Amount should be negative because the user
    // is spending tofu rather than earning it.
    func addRewardPurchase(rewardId: String, amount: Int) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: nil,
            rewardId: rewardId,
            amount: amount,
            createdAt: Date()
        )
        trades.append(trade)
    }

    // Test-only helper for simulating older completions.
    func addHabitTradeWithDate(habitId: String, amount: Int, createdAt: Date) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: habitId,
            rewardId: nil,
            amount: amount,
            createdAt: createdAt
        )
        trades.append(trade)
    }

    // Test-only helper for simulating older purchases.
    func addRewardPurchaseWithDate(rewardId: String, amount: Int, createdAt: Date) {
        let trade = Trade(
            id: UUID().uuidString,
            habitId: nil,
            rewardId: rewardId,
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

    // Reward prices look back over recent purchases of that same reward only.
    func rewardPurchasesInPeriod(rewardId: String, days: Int) -> Int {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.rewardId == rewardId && $0.createdAt >= cutoff
        }.count
    }
}
