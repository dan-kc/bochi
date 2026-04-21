import Foundation

// Reward is the inverse of Habit: instead of earning tofu for doing something,
// the user spends tofu to buy something tempting. The form fields are nearly
// parallel to Habit, but the semantics are inverted:
// - `maxFrequency` is the maximum healthy purchase rate the user wants
// - `damageTier` expresses how harmful/derailing the reward is
struct Reward: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let name: String
    let description: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let maxFrequency: Double?
    let damageTier: RewardDamageTier?

    // Buying is allowed even when optional pricing fields are blank. The
    // calculator now uses the most expensive fallback values by default so
    // filling in more detail can only improve the price.
    var canPurchase: Bool {
        deletedAt == nil
    }
}
