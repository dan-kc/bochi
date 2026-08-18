import Foundation

// Lockout is driven entirely by the latest non-deleted claim for that recurringTask.
// This prevents rapid re-claims without altering the actual reward formula.
enum RecurringTaskLockout {
    static func remainingSeconds(
        recurringTask: RecurringTask,
        tradeStore: TradeStore,
        now: Date = Date(),
        hasPremiumAccess: Bool = true
    ) -> Int? {
        remainingSeconds(
            recurringTask: recurringTask,
            completionDates: tradeStore.recurringTaskTradeDates(recurringTaskId: recurringTask.id),
            now: now,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    nonisolated static func remainingSeconds(
        recurringTask: RecurringTask,
        completionDates: [Date],
        now: Date = Date(),
        hasPremiumAccess: Bool = true
    ) -> Int? {
        guard hasPremiumAccess else { return nil }
        guard let lockoutDurationSeconds = recurringTask.lockoutDurationSeconds, lockoutDurationSeconds > 0 else {
            return nil
        }

        guard let latestClaim = completionDates.max() else {
            return nil
        }

        let unlockDate = latestClaim.addingTimeInterval(TimeInterval(lockoutDurationSeconds))
        let remainingSeconds = Int(ceil(unlockDate.timeIntervalSince(now)))
        guard remainingSeconds > 0 else { return nil }
        return remainingSeconds
    }

    static func isLocked(
        recurringTask: RecurringTask,
        tradeStore: TradeStore,
        now: Date = Date(),
        hasPremiumAccess: Bool = true
    ) -> Bool {
        remainingSeconds(
            recurringTask: recurringTask,
            tradeStore: tradeStore,
            now: now,
            hasPremiumAccess: hasPremiumAccess
        ) != nil
    }
}
