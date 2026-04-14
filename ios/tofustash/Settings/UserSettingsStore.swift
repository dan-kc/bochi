import Foundation

// Stores user preferences that affect gameplay mechanics.
// Currently only holds generalDifficulty, which scales all reward amounts.
//
// Follows the same @Observable pattern as HabitStore — views that read
// `generalDifficulty` will automatically re-render when it changes.
@Observable
@MainActor
final class UserSettingsStore {

    // Controls the overall scale of rewards. Higher values = larger rewards.
    // Default is 5.0, matching the frontend.
    // Valid range: (0, 1000) — must be strictly greater than 0 and less than 1000.
    private(set) var generalDifficulty: Double = 5.0

    // Updates the general difficulty, with validation.
    // Silently rejects invalid values (like the frontend modal's validation).
    func setGeneralDifficulty(_ value: Double) {
        guard value > 0, value < 1000 else { return }
        generalDifficulty = value
    }
}
