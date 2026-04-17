import Foundation

// Stores preferences that affect the numbers the user sees in the app.
// `generalDifficulty` is the global reward scale knob exposed in Settings.
//
// Follows the same @Observable pattern as HabitStore — views that read
// `generalDifficulty` will automatically re-render when it changes.
@Observable
@MainActor
final class UserSettingsStore {

    // Higher values raise all reward payouts. The same default is used on web
    // so users do not see a platform-specific economy shift.
    private(set) var generalDifficulty: Double = 5.0

    // Invalid values are ignored so the current reward scale stays stable.
    func setGeneralDifficulty(_ value: Double) {
        guard value > 0, value < 1000 else { return }
        generalDifficulty = value
    }
}
