import Foundation
import Testing
@testable import tofustash

@MainActor
struct RewardStoreTests {
    private func makeSUT() -> RewardStore {
        RewardStore()
    }

    // Behaviour: Creating a reward trims accidental whitespace so duplicate-looking names are avoided.
    @Test("addReward trims the saved name")
    func addRewardTrimsName() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "  Soda  ", maxFrequency: 1.0, damageRank: "m")

        #expect(reward?.name == "Soda")
        #expect(sut.activeRewards.count == 1)
    }

    // Behaviour: Editing a reward can explicitly clear max frequency and damage instead of leaving stale values behind.
    @Test("updateReward can clear optional fields")
    func updateRewardCanClearFields() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "Dessert", maxFrequency: 1.0, damageRank: "m")!

        sut.updateReward(
            id: reward.id,
            maxFrequency: .some(nil),
            damageRank: .some(nil)
        )

        let updated = sut.activeRewards[0]
        #expect(updated.maxFrequency == nil)
        #expect(updated.damageRank == nil)
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
