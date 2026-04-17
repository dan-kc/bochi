import Foundation

// Tracks the tofu balance the user sees in the toolbar and spends on rewards.
//
// Follows the same @Observable pattern as HabitStore and TradeStore.
// Views that read `balance` will automatically re-render when it changes.
@Observable
@MainActor
final class BalanceStore {

    // Current tofu balance. Can go negative (no floor enforced).
    // `private(set)` means views can read but only this class can write.
    private(set) var balance: Int = 0

    // Called after a successful habit trade so the visible balance increases.
    func addTofu(_ amount: Int) {
        balance += amount
    }

    // Called when the user spends tofu on something else in the app.
    func subtractTofu(_ amount: Int) {
        balance -= amount
    }
}
