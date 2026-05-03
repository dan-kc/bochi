import Foundation

// Reward lockout mirrors habit lockout: it is driven by the latest unresolved
// purchase so the user can pace access to a reward without changing its price.
enum RewardLockout {
    static func remainingSeconds(
        reward: Reward,
        tradeStore: TradeStore,
        now: Date = Date()
    ) -> Int? {
        guard let lockoutDurationSeconds = reward.lockoutDurationSeconds, lockoutDurationSeconds > 0 else {
            return nil
        }

        guard let latestPurchase = tradeStore.rewardPurchaseDates(rewardId: reward.id).max() else {
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
        now: Date = Date()
    ) -> Bool {
        remainingSeconds(reward: reward, tradeStore: tradeStore, now: now) != nil
    }
}
