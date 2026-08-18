import Foundation

// Shared frequency limits for both recurringTasks and rewards.
//
// These bounds matter for two reasons:
// 1. the editor should only accept values the backend will persist
// 2. unset pricing fields should fall back to a real selectable extreme,
//    rather than a separate magic multiplier
enum FrequencyBounds {
    nonisolated static let minimumDailyRate = 1.0 / 30.0   // 1/month
    nonisolated static let maximumDailyRate = 100.0        // 100/day

    nonisolated static func contains(_ rate: Double) -> Bool {
        (minimumDailyRate...maximumDailyRate).contains(rate)
    }
}
