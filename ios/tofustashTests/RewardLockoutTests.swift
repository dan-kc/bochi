import Foundation
import Testing
@testable import tofustash

@MainActor
struct RewardLockoutTests {
    private func makeStore() -> TradeStore {
        TradeStore(storageURL: TestHelpers.makeTemporaryFileURL("reward-lockout-trades"))
    }

    private func makeReward(
        id: RecordID = "reward-1",
        lockoutDurationSeconds: Int? = nil
    ) -> Reward {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        return Reward(
            id: id,
            name: "Test Reward",
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            maxFrequency: nil,
            damageTier: nil,
            lockoutDurationSeconds: lockoutDurationSeconds
        )
    }

    // Behaviour: After a user buys a reward, the configured lockout should
    // stop another purchase until that cooldown has passed.
    @Test func latestPurchaseStartsLockoutWindow() {
        let tradeStore = makeStore()
        let reward = makeReward(lockoutDurationSeconds: 3_600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRewardPurchase(
            rewardId: reward.id,
            amount: -100,
            createdAt: now.addingTimeInterval(-1_800),
            shouldNotifySync: false
        )

        #expect(RewardLockout.isLocked(reward: reward, tradeStore: tradeStore, now: now) == true)
    }

    // Behaviour: Once the cooldown expires, the user should be able to buy the
    // reward again without editing the reward itself.
    @Test func rewardUnlocksAfterLockoutExpires() {
        let tradeStore = makeStore()
        let reward = makeReward(lockoutDurationSeconds: 3_600)
        let purchaseDate = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRewardPurchase(
            rewardId: reward.id,
            amount: -100,
            createdAt: purchaseDate,
            shouldNotifySync: false
        )

        #expect(RewardLockout.isLocked(reward: reward, tradeStore: tradeStore, now: purchaseDate.addingTimeInterval(3_601)) == false)
    }

    // Behaviour: Soft-deleted purchase history should stop influencing
    // lockout so stale tombstones do not keep the reward unavailable.
    @Test func deletedTradesDoNotKeepRewardLocked() {
        let tradeStore = makeStore()
        let reward = makeReward(lockoutDurationSeconds: 3_600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRewardPurchase(
            rewardId: reward.id,
            amount: -100,
            createdAt: now.addingTimeInterval(-600),
            deletedAt: now.addingTimeInterval(-300),
            shouldNotifySync: false
        )

        #expect(RewardLockout.isLocked(reward: reward, tradeStore: tradeStore, now: now) == false)
    }

    // Behaviour: A real refund trade should remove the original purchase from
    // lockout calculations so the reward unlocks immediately after reversal.
    @Test func refundedTradesDoNotKeepRewardLocked() throws {
        let tradeStore = makeStore()
        let reward = makeReward(lockoutDurationSeconds: 3_600)
        let purchaseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let refundedAt = purchaseDate.addingTimeInterval(300)

        tradeStore.addRewardPurchase(
            id: "reward-trade-1",
            rewardId: reward.id,
            amount: -100,
            createdAt: purchaseDate,
            shouldNotifySync: false
        )

        let refundTrade = try #require(
            tradeStore.refundTrade(
                id: "reward-trade-1",
                refundedAt: refundedAt,
                shouldNotifySync: false
            )
        )

        #expect(refundTrade.refundsTradeId == "reward-trade-1")
        #expect(RewardLockout.isLocked(reward: reward, tradeStore: tradeStore, now: refundedAt) == false)
    }
}
