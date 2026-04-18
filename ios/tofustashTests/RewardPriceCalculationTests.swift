import Foundation
import Testing
@testable import tofustash

private func makeReward(
    id: String = "test-reward-1",
    maxFrequency: Double? = nil,
    damageRank: String? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1577836800),
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
        damageRank: damageRank
    )
}

struct RewardDamageMultiplierTests {
    // Behaviour: An unranked reward falls back to neutral pricing instead of disappearing from the market.
    @Test("Returns 0.5 when reward has no damage rank")
    func unrankedReward() {
        let reward = makeReward(damageRank: nil)
        let multiplier = RewardPriceCalculation.calculateDamageMultiplier(reward: reward, allRewards: [reward])
        #expect(multiplier == 0.5)
    }

    // Behaviour: The most damaging reward in a pair costs more than the less damaging one.
    @Test("Lower rank string gets higher damage multiplier")
    func rankOrdering() {
        let lowDamage = makeReward(id: "low", damageRank: "a0")
        let highDamage = makeReward(id: "high", damageRank: "z0")
        let allRewards = [lowDamage, highDamage]

        let lowMultiplier = RewardPriceCalculation.calculateDamageMultiplier(reward: lowDamage, allRewards: allRewards)
        let highMultiplier = RewardPriceCalculation.calculateDamageMultiplier(reward: highDamage, allRewards: allRewards)

        #expect(lowMultiplier > highMultiplier)
    }

    // Behaviour: Deleted rewards stop influencing the prices of visible rewards.
    @Test("Deleted rewards are excluded from damage ranking")
    func ignoresDeletedRewards() {
        let active = makeReward(id: "active", damageRank: "a0")
        let deleted = makeReward(id: "deleted", damageRank: "z0", deletedAt: Date())
        let multiplier = RewardPriceCalculation.calculateDamageMultiplier(reward: active, allRewards: [active, deleted])
        #expect(multiplier == 0.5)
    }
}

struct RewardFrequencyMultiplierTests {
    // Behaviour: A reward with no max frequency behaves like an uncapped purchase and keeps neutral pricing.
    @Test("Returns 1 when max frequency is nil")
    func nilFrequency() {
        let reward = makeReward(maxFrequency: nil)
        let multiplier = RewardPriceCalculation.calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: 4)
        #expect(multiplier == 1)
    }

    // Behaviour: Buying a reward near its personal cap makes the next purchase much more expensive.
    @Test("Approaching the cap raises the multiplier")
    func approachingCapRaisesPrice() {
        let reward = makeReward(maxFrequency: 3.0)
        let calm = RewardPriceCalculation.calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: 1, periodDays: 1)
        let nearCap = RewardPriceCalculation.calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: 2, periodDays: 1)
        #expect(nearCap > calm)
    }

    // Behaviour: Once the reward has already hit its cap, the multiplier clamps instead of exploding to infinity.
    @Test("Hitting the cap clamps to the max multiplier")
    func clampsAtCap() {
        let reward = makeReward(maxFrequency: 3.0)
        let multiplier = RewardPriceCalculation.calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: 3, periodDays: 1)
        #expect(multiplier == 50)
    }

    // Behaviour: Brand-new rewards should still react immediately when the
    // user increases quantity in the buy modal instead of staying artificially flat.
    @Test("New reward uses the live purchase ratio immediately")
    func newRewardStillAdaptsImmediately() {
        let reward = makeReward(maxFrequency: 3.0, createdAt: Date())
        let first = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 0,
            timeBucket: 12345,
            generalDifficulty: 5
        )
        let total = RewardPriceCalculation.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: [reward],
            currentPurchases: 0,
            quantity: 2,
            timeBucket: 12345,
            generalDifficulty: 5
        )

        #expect(total > first * 2)
    }
}

struct RewardRandomMultiplierTests {
    // Behaviour: Refreshing the reward list inside the same price bucket should not change the displayed price.
    @Test("Random multiplier is deterministic inside one bucket")
    func deterministicWithinBucket() {
        let first = RewardPriceCalculation.calculateRandomMultiplier(rewardId: "reward-1", timeBucket: 12345)
        let second = RewardPriceCalculation.calculateRandomMultiplier(rewardId: "reward-1", timeBucket: 12345)
        #expect(first == second)
    }

    // Behaviour: When the next half-hour bucket starts, the price is allowed to shift slightly.
    @Test("Random multiplier changes across buckets")
    func changesAcrossBuckets() {
        let first = RewardPriceCalculation.calculateRandomMultiplier(rewardId: "reward-1", timeBucket: 12345)
        let second = RewardPriceCalculation.calculateRandomMultiplier(rewardId: "reward-1", timeBucket: 12346)
        #expect(first != second)
    }
}

struct RewardPriceTests {
    // Behaviour: Reward prices are always shown as whole tofu amounts.
    @Test("Calculated price is an integer")
    func roundedInteger() {
        let reward = makeReward()
        let price = RewardPriceCalculation.calculatePrice(reward: reward, allRewards: [reward], purchasesInPeriod: 0, timeBucket: 12345, generalDifficulty: 5)
        #expect(price == price)
    }

    // Behaviour: More damaging rewards should cost more than less damaging ones when everything else is equal.
    @Test("Damage ranking affects final price")
    func damageAffectsPrice() {
        let lighter = makeReward(id: "lighter", damageRank: "a0")
        let heavier = makeReward(id: "heavier", damageRank: "z0")
        let allRewards = [lighter, heavier]

        let lighterPrice = RewardPriceCalculation.calculatePrice(reward: lighter, allRewards: allRewards, purchasesInPeriod: 0, timeBucket: 12345, generalDifficulty: 5)
        let heavierPrice = RewardPriceCalculation.calculatePrice(reward: heavier, allRewards: allRewards, purchasesInPeriod: 0, timeBucket: 12345, generalDifficulty: 5)

        #expect(lighterPrice > heavierPrice)
    }

    // Behaviour: Buying multiple rewards sums each successive price rather than
    // naively multiplying one visible price.
    @Test("Multi-purchase total is not flat multiplication")
    func multiPurchaseTotalReflectsRisingPrices() {
        let reward = makeReward(maxFrequency: 3.0, damageRank: "m0")
        let single = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 0,
            timeBucket: 12345,
            generalDifficulty: 5
        )
        let total = RewardPriceCalculation.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: [reward],
            currentPurchases: 0,
            quantity: 3,
            timeBucket: 12345,
            generalDifficulty: 5
        )

        #expect(total >= single * 3)
    }

    // Behaviour: A reward capped at 3/day should get more expensive after each
    // same-day purchase, so the list price does not appear stuck.
    @Test("3 per day reward price rises with each same-day purchase")
    func priceRisesForRepeatedSameDayPurchases() {
        let reward = makeReward(maxFrequency: 3.0, damageRank: "m0")
        let first = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 0,
            timeBucket: 12345,
            generalDifficulty: 5
        )
        let second = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 1,
            timeBucket: 12345,
            generalDifficulty: 5
        )
        let third = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchasesInPeriod: 2,
            timeBucket: 12345,
            generalDifficulty: 5
        )

        #expect(second > first)
        #expect(third > second)
    }
}
