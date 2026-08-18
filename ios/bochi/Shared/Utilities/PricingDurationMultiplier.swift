import Foundation

// Shared expected-effort curve for recurringTask and task rewards. Both user actions
// treat no duration as neutral and scale configured durations up to the same cap.
enum PricingDurationMultiplier {
    nonisolated private static let maxDurationSeconds = 43_200.0
    nonisolated private static let multiplierRange = 19.0

    nonisolated static func calculate(durationSeconds: Int?) -> Double {
        guard let durationSeconds, durationSeconds > 0 else {
            return 1.0
        }

        let normalized = Double(durationSeconds) / maxDurationSeconds
        return 1.0 + (normalized * multiplierRange)
    }
}
