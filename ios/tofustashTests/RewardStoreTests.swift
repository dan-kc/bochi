import Foundation
import Testing
@testable import tofustash

@MainActor
struct RewardStoreTests {
    private func makeSUT() -> RewardStore {
        RewardStore(storageURL: TestHelpers.makeTemporaryFileURL("rewards"))
    }

    // Behaviour: Creating a reward trims accidental whitespace so duplicate-looking names are avoided.
    @Test("addReward trims the saved name")
    func addRewardTrimsName() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "  Soda  ", maxFrequency: 1.0, damageTier: .medium)

        #expect(reward?.name == "Soda")
        #expect(sut.activeRewards.count == 1)
    }

    // Behaviour: Editing a reward can explicitly clear max frequency and damage instead of leaving stale values behind.
    @Test("updateReward can clear optional fields")
    func updateRewardCanClearFields() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "Dessert", maxFrequency: 1.0, damageTier: .medium)!

        sut.updateReward(
            id: reward.id,
            maxFrequency: .some(nil),
            damageTier: .some(nil)
        )

        let updated = sut.activeRewards[0]
        #expect(updated.maxFrequency == nil)
        #expect(updated.damageTier == nil)
    }

    // Behaviour: Reward lockout needs to persist like other reward settings so
    // locked sections stay stable after the app restarts.
    @Test("reward lockout duration saves, loads, and can be cleared")
    func rewardLockoutPersistsAndClears() {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-lockout-persistence")
        let sut = RewardStore(storageURL: storageURL)
        let reward = sut.addReward(
            name: "Dessert",
            maxFrequency: 1.0,
            damageTier: .medium,
            lockoutDurationSeconds: 3_600
        )!

        #expect(sut.activeRewards[0].lockoutDurationSeconds == 3_600)

        let reloaded = RewardStore(storageURL: storageURL)
        #expect(reloaded.activeRewards[0].lockoutDurationSeconds == 3_600)

        reloaded.updateReward(id: reward.id, lockoutDurationSeconds: .some(nil))

        #expect(reloaded.activeRewards[0].lockoutDurationSeconds == nil)
    }

    // Behaviour: Deleting a reward removes it from the active list and from future damage comparisons.
    @Test("deleteReward soft deletes the reward")
    func deleteRewardSoftDeletes() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "Game")!

        sut.deleteReward(id: reward.id)

        #expect(sut.rewards[0].deletedAt != nil)
        #expect(sut.activeRewards.isEmpty)
    }
}
