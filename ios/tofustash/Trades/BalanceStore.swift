import Foundation

// Tracks the user's tofu currency balance. Tofu is earned by completing
// habits (addTofu) and spent by purchasing rewards (subtractTofu).
//
// Follows the same @Observable pattern as HabitStore and TradeStore.
// Views that read `balance` will automatically re-render when it changes.
@Observable
@MainActor
final class BalanceStore {

    // Current tofu balance. Can go negative (no floor enforced).
    // `private(set)` means views can read but only this class can write.
    private(set) var balance: Int = 0

    // Adds tofu to the balance (called when completing a habit).
    func addTofu(_ amount: Int) {
        balance += amount
    }

    // Subtracts tofu from the balance (called when purchasing a reward).
    func subtractTofu(_ amount: Int) {
        balance -= amount
    }
}
