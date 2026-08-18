import Foundation

// Reward lockout mirrors recurringTask lockout: it is driven by the latest unresolved
// purchase so the user can pace access to a reward without changing its price.
enum RewardLockout {
    static func remainingSeconds(
        reward: Reward,
        tradeStore: TradeStore,
        now: Date = Date(),
        hasPremiumAccess: Bool = true
    ) -> Int? {
        remainingSeconds(
            reward: reward,
            purchaseDates: tradeStore.rewardPurchaseDates(rewardId: reward.id),
            now: now,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    nonisolated static func remainingSeconds(
        reward: Reward,
        purchaseDates: [Date],
        now: Date = Date(),
        hasPremiumAccess: Bool = true
    ) -> Int? {
        guard hasPremiumAccess else { return nil }
        guard let lockoutDurationSeconds = reward.lockoutDurationSeconds, lockoutDurationSeconds > 0 else {
            return nil
        }

        guard let latestPurchase = purchaseDates.max() else {
            return nil
        }

        let unlockDate = latestPurchase.addingTimeInterval(TimeInterval(lockoutDurationSeconds))
        let remainingSeconds = Int(ceil(unlockDate.timeIntervalSince(now)))
        guard remainingSeconds > 0 else { return nil }
        return remainingSeconds
    }

    static func isLocked(
        reward: Reward,
        tradeStore: TradeStore,
        now: Date = Date(),
        hasPremiumAccess: Bool = true
    ) -> Bool {
        remainingSeconds(
            reward: reward,
            tradeStore: tradeStore,
            now: now,
            hasPremiumAccess: hasPremiumAccess
        ) != nil
    }
}
