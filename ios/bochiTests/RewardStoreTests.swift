import Foundation
import Testing
@testable import bochi

@MainActor
struct RewardStoreTests {
    private func makeSUT() -> RewardStore {
        RewardStore(storageURL: TestHelpers.makeTemporaryFileURL("rewards"))
    }

    // Behaviour: Creating a reward trims accidental whitespace so duplicate-looking names are avoided.
    @Test("addReward trims the saved name")
    func addRewardTrimsName() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "  Soda  ", maxFrequency: 1.0, basePrice: 250)

        #expect(reward?.name == "Soda")
        #expect(reward?.basePrice == 250)
        #expect(sut.activeRewards.count == 1)
    }

    // Behaviour: Editing a reward can explicitly clear max frequency instead
    // of leaving stale cadence values behind.
    @Test("updateReward can clear optional fields")
    func updateRewardCanClearFields() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "Dessert", maxFrequency: 1.0)!

        sut.updateReward(
            id: reward.id,
            maxFrequency: .some(nil)
        )

        let updated = sut.activeRewards[0]
        #expect(updated.maxFrequency == nil)
    }

    // Behaviour: the submitted reward price should survive app restart and be
    // editable without relying on removed derived pricing fields.
    @Test("reward base price saves, loads, and updates")
    func rewardBasePricePersistsAndUpdates() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-base-price-persistence")
        let sut = RewardStore(storageURL: storageURL)
        let reward = try #require(sut.addReward(name: "Dessert", basePrice: 450))

        #expect(sut.activeRewards[0].basePrice == 450)

        let reloaded = RewardStore(storageURL: storageURL)
        #expect(reloaded.activeRewards[0].basePrice == 450)

        reloaded.updateReward(id: reward.id, basePrice: 300)

        #expect(reloaded.activeRewards[0].basePrice == 300)
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
            lockoutDurationSeconds: 3_600
        )!

        #expect(sut.activeRewards[0].lockoutDurationSeconds == 3_600)

        let reloaded = RewardStore(storageURL: storageURL)
        #expect(reloaded.activeRewards[0].lockoutDurationSeconds == 3_600)

        reloaded.updateReward(id: reward.id, lockoutDurationSeconds: .some(nil))

        #expect(reloaded.activeRewards[0].lockoutDurationSeconds == nil)
    }

    // Behaviour: local persistence should enforce that one-time rewards cannot
    // retain a recurring reward's max frequency, even if a caller bypasses the store API.
    @Test("one-time rewards reject max frequency at the database layer")
    func oneOffRewardsRejectMaxFrequencyAtDatabaseLayer() {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-recurring-constraint")
        _ = RewardStore(storageURL: storageURL)

        var didRejectInvalidShape = false
        do {
            try AppDatabase.shared.execute(
                """
                INSERT INTO rewards (
                    id, owner_id, recurring, name, description, created_at, updated_at, max_daily_frequency, base_price
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text("reward-bad-shape"),
                    .text(StorageOwner.local),
                    .int(0),
                    .text("One-time splurge"),
                    .text(""),
                    .double(Date().timeIntervalSince1970),
                    .double(Date().timeIntervalSince1970),
                    .double(1.0),
                    .int(500)
                ],
                at: storageURL
            )
        } catch {
            didRejectInvalidShape = true
        }

        #expect(didRejectInvalidShape)
    }

    // Behaviour: Deleting a reward removes it from the active list.
    @Test("deleteReward soft deletes the reward")
    func deleteRewardSoftDeletes() {
        let sut = makeSUT()
        let reward = sut.addReward(name: "Game")!

        sut.deleteReward(id: reward.id)

        #expect(sut.rewards[0].deletedAt != nil)
        #expect(sut.activeRewards.isEmpty)
    }

    // Behaviour: pinning a reward should survive a store reload so its list
    // priority is not lost when the app restarts.
    @Test("pinReward persists")
    func pinRewardPersists() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-pin-persistence")
        let sut = RewardStore(storageURL: storageURL)
        let reward = try #require(sut.addReward(name: "Game"))

        sut.setPinned(id: reward.id, pinned: true)

        #expect(sut.rewards.first?.pinned == true)
        let reloaded = RewardStore(storageURL: storageURL)
        #expect(reloaded.rewards.first?.pinned == true)
    }

    // Behaviour: hiding a reward should persist for sync without removing it
    // from the current list while the UI hiding rules are still pending.
    @Test("hideReward persists without filtering")
    func hideRewardPersistsWithoutFiltering() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-hidden-persistence")
        let sut = RewardStore(storageURL: storageURL)
        let reward = try #require(sut.addReward(name: "Game"))

        sut.setHidden(id: reward.id, hidden: true)

        #expect(sut.rewards.first?.hidden == true)
        #expect(sut.activeRewards.first?.hidden == true)
        let reloaded = RewardStore(storageURL: storageURL)
        #expect(reloaded.rewards.first?.hidden == true)
    }
}
