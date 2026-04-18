import Foundation
import Testing
@testable import tofustash

private func makeReward(
    id: String = "reward-1",
    maxFrequency: Double? = nil,
    damageTier: RewardDamageTier? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_577_836_800),
    deletedAt: Date? = nil
) -> Reward {
    Reward(
        id: id,
        name: "Test Reward",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: deletedAt,
        maxFrequency: maxFrequency,
        damageTier: damageTier
    )
}

struct RewardDamageMultiplierTests {
    // Behaviour: Reward damage is now a fixed tier, so more damaging rewards
    // always cost more without depending on rank strings.
    @Test func heavierTiersAlwaysCostMore() {
        let harmless = makeReward(damageTier: .harmless)
        let extreme = makeReward(damageTier: .extreme)

        #expect(RewardPriceCalculation.calculateDamageMultiplier(reward: harmless, allRewards: [harmless]) == 0.8)
        #expect(RewardPriceCalculation.calculateDamageMultiplier(reward: extreme, allRewards: [extreme]) == 1.25)
    }

    // Behaviour: If the user has not classified a reward yet, pricing falls
    // back to the neutral medium tier.
    @Test func missingTierFallsBackToMediumMultiplier() {
        let reward = makeReward(damageTier: nil)
        #expect(RewardPriceCalculation.calculateDamageMultiplier(reward: reward, allRewards: [reward]) == 1.0)
    }
}

struct RewardFrequencyMultiplierTests {
    // Behaviour: A reward with no cap behaves like an uncapped purchase and
    // keeps the neutral price multiplier.
    @Test func nilFrequencyUsesNeutralMultiplier() {
        #expect(RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: makeReward(maxFrequency: nil),
            purchasesInPeriod: 4
        ) == 1.0)
    }

    // Behaviour: Same-day repeat purchases make the next purchase more
    // expensive, and hitting the cap clamps at the hard limit.
    @Test func multiplierRisesTowardAndAtCap() {
        let reward = makeReward(maxFrequency: 3.0)

        let first = RewardPriceCalculation.calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: 1, periodDays: 1)
        let second = RewardPriceCalculation.calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: 2, periodDays: 1)
        let capped = RewardPriceCalculation.calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: 3, periodDays: 1)

        #expect(second > first)
        #expect(capped == 50.0)
    }
}

struct RewardPriceTests {
    // Behaviour: A reward price is deterministic and uses the fixed tier
    // multiplier with no random bucket component.
    @Test func priceUsesTierAndFrequencyWithoutRandomness() {
        let reward = makeReward(maxFrequency: 3.0, damageTier: .heavy)

        let price = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 0,
            generalDifficulty: 5
        )

        #expect(price == 550)
    }

    // Behaviour: The reward list price rises with repeated same-day purchases
    // instead of staying flat.
    @Test func repeatedPurchasesRaiseVisiblePrice() {
        let reward = makeReward(maxFrequency: 3.0, damageTier: .medium)

        let first = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 0,
            generalDifficulty: 5
        )
        let second = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 1,
            generalDifficulty: 5
        )
        let third = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 2,
            generalDifficulty: 5
        )

        #expect(second > first)
        #expect(third > second)
    }

    // Behaviour: Buying several rewards in one go sums each incremental price
    // rather than multiplying a flat base price.
    @Test func multiPurchaseMatchesIncrementalTotals() {
        let reward = makeReward(maxFrequency: 3.0, damageTier: .medium)

        let first = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 0,
            generalDifficulty: 5
        )
        let second = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 1,
            generalDifficulty: 5
        )
        let total = RewardPriceCalculation.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: [reward],
            currentPurchases: 0,
            quantity: 2,
            generalDifficulty: 5
        )

        #expect(total == first + second)
    }
}
