import Foundation

// Lockout is driven entirely by the latest non-deleted claim for that habit.
// This prevents rapid re-claims without altering the actual reward formula.
enum HabitLockout {
    static func remainingSeconds(
        habit: Habit,
        tradeStore: TradeStore,
        now: Date = Date()
    ) -> Int? {
        guard let lockoutDurationSeconds = habit.lockoutDurationSeconds, lockoutDurationSeconds > 0 else {
            return nil
        }

        guard let latestClaim = tradeStore.habitTradeDates(habitId: habit.id).max() else {
            return nil
        }

        let unlockDate = latestClaim.addingTimeInterval(TimeInterval(lockoutDurationSeconds))
        let remainingSeconds = Int(ceil(unlockDate.timeIntervalSince(now)))
        guard remainingSeconds > 0 else { return nil }
        return remainingSeconds
    }

    static func isLocked(
        habit: Habit,
        tradeStore: TradeStore,
        now: Date = Date()
    ) -> Bool {
        remainingSeconds(habit: habit, tradeStore: tradeStore, now: now) != nil
    }
}
