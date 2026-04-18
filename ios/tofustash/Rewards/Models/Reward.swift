import Foundation

// Reward is the inverse of Habit: instead of earning tofu for doing something,
// the user spends tofu to buy something tempting. The form fields are nearly
// parallel to Habit, but the semantics are inverted:
// - `maxFrequency` is the maximum healthy purchase rate the user wants
// - `damageRank` expresses how harmful/derailing the reward is relative to others
struct Reward: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let name: String
    let description: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let maxFrequency: Double?
    let damageRank: String?

    // Rewards follow the same gating rule as habits: the user must define both
    // the cap (max frequency) and the relative ranking (damage) before the app
    // shows a market price or purchase action.
    var canPurchase: Bool {
        deletedAt == nil && maxFrequency != nil && damageRank != nil
    }
}
