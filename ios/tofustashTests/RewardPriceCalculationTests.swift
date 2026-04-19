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
            purchaseDates: []
        ) == 1.0)
    }

    // Behaviour: Same-day repeat purchases make the next purchase more
    // expensive, and aggressive overuse still clamps at the hard limit.
    @Test func multiplierRisesTowardAndAtCap() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(
            maxFrequency: 3.0,
            createdAt: now.addingTimeInterval(-5 * 86_400)
        )

        let first = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [now],
            now: now
        )
        let second = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [now, now],
            now: now
        )
        let capped = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [now, now, now],
            now: now
        )

        #expect(second > first)
        #expect(capped == 50.0)
    }

    // Behaviour: Equivalent rates should stabilize the same way even if they
    // were entered as different units such as `1/day` and `30/month`.
    @Test func equivalentRatesShareTheSameCadenceModel() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let createdAt = now.addingTimeInterval(-10 * 86_400)
        let dailyReward = makeReward(maxFrequency: 1.0, createdAt: createdAt)
        let monthlyReward = makeReward(maxFrequency: 30.0 / 30.0, createdAt: createdAt)
        let purchaseDates = [now.addingTimeInterval(-86_400)]

        let daily = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: dailyReward,
            purchaseDates: purchaseDates,
            now: now
        )
        let monthly = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: monthlyReward,
            purchaseDates: purchaseDates,
            now: now
        )

        #expect(abs(daily - monthly) < 0.0001)
    }

    // Behaviour: A brand-new low-frequency reward starts near its base price
    // instead of overreacting to sparse history.
    @Test func newRewardStartsNearBasePriceDuringWarmup() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(
            maxFrequency: 2.0 / 30.0,
            createdAt: now.addingTimeInterval(-6 * 3_600)
        )

        let multiplier = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [],
            now: now
        )

        #expect(multiplier == 1.0)
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
            purchaseDates: [],
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
            purchaseDates: [],
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )
        let second = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [Date(timeIntervalSince1970: 2_000_000_000)],
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )
        let third = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [
                Date(timeIntervalSince1970: 2_000_000_000),
                Date(timeIntervalSince1970: 2_000_000_000)
            ],
            now: Date(timeIntervalSince1970: 2_000_000_000),
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
            purchaseDates: [],
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )
        let second = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [Date(timeIntervalSince1970: 2_000_000_000)],
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )
        let total = RewardPriceCalculation.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            quantity: 2,
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )

        #expect(total == first + second)
    }
}
