import Foundation
import Testing
@testable import tofustash

private func makeReward(
    id: RecordID = "reward-1",
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
    private let tolerance = 0.0001

    // Behaviour: Reward damage is now a fixed tier, so more damaging rewards
    // always cost more without depending on rank strings.
    @Test func heavierTiersAlwaysCostMore() {
        let harmless = makeReward(damageTier: .harmless)
        let extreme = makeReward(damageTier: .extreme)

        #expect(abs(RewardPriceCalculation.calculateDamageMultiplier(reward: harmless, allRewards: [harmless]) - 0.2) < tolerance)
        #expect(abs(RewardPriceCalculation.calculateDamageMultiplier(reward: extreme, allRewards: [extreme]) - 2.0) < tolerance)
    }

    // Behaviour: If the user has not classified a reward yet, pricing falls
    // back to the most expensive extreme tier so blank fields never make rewards cheaper.
    @Test func missingTierFallsBackToExtremeMultiplier() {
        let reward = makeReward(damageTier: nil)
        #expect(RewardPriceCalculation.calculateDamageMultiplier(reward: reward, allRewards: [reward]) == 2.0)
    }
}

struct RewardFrequencyMultiplierTests {
    // Behaviour: Leaving max frequency blank should price the reward like the
    // strictest selectable cap instead of a separate punitive fallback path.
    @Test func nilFrequencyMatchesStrictestConfiguredCap() {
        let createdAt = Date(timeIntervalSince1970: 1_577_836_800)
        let blank = makeReward(maxFrequency: nil, createdAt: createdAt)
        let configured = makeReward(
            maxFrequency: FrequencyBounds.minimumDailyRate,
            createdAt: createdAt
        )

        let blankMultiplier = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: blank,
            purchaseDates: []
        )
        let configuredMultiplier = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: configured,
            purchaseDates: []
        )

        #expect(blankMultiplier == configuredMultiplier)
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
        #expect(capped == 20.0)
    }

    // Behaviour: A reward configured for several times per day should tolerate
    // a short burst better than a strict "every N hours" spacing rule.
    @Test func highFrequencyRewardGetsBurstSlackBeforeCap() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(
            maxFrequency: 4.0,
            createdAt: now.addingTimeInterval(-10 * 86_400)
        )
        let purchaseDates = [
            now.addingTimeInterval(-86_400),
            now,
            now
        ]

        let multiplier = RewardPriceCalculation.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: purchaseDates,
            now: now
        )

        #expect(multiplier > 1.0)
        #expect(multiplier < 20.0)
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

        #expect(price == 700)
    }

    // Behaviour: Changing general difficulty should make the same reward more
    // or less expensive, so the setting still changes spending pressure.
    @Test func generalDifficultyRaisesRewardPrice() {
        let reward = makeReward(maxFrequency: 3.0, damageTier: .medium)

        let easierPrice = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            generalDifficulty: 2
        )
        let harderPrice = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            generalDifficulty: 8
        )

        #expect(harderPrice > easierPrice)
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

    // Behaviour: A 4/day reward should not jump straight to the maximum price
    // after one purchase yesterday and two purchases today.
    @Test func clusteredHighFrequencyPurchasesStayBelowPriceCap() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(
            maxFrequency: 4.0,
            damageTier: .light,
            createdAt: now.addingTimeInterval(-10 * 86_400)
        )
        let secondToday = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [now.addingTimeInterval(-86_400), now],
            now: now,
            generalDifficulty: 5
        )
        let nextPrice = RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [
                now.addingTimeInterval(-86_400),
                now,
                now
            ],
            now: now,
            generalDifficulty: 5
        )

        #expect(nextPrice > secondToday)
        #expect(nextPrice < 6_000)
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

    // Behaviour: Leaving all optional reward pricing inputs blank should be
    // more expensive than a configured moderate reward.
    @Test func missingFieldsUseLargestRewardFallbacks() {
        let blank = makeReward(maxFrequency: nil, damageTier: nil)
        let configured = makeReward(maxFrequency: 3.0, damageTier: .medium)

        let blankPrice = RewardPriceCalculation.calculatePrice(
            reward: blank,
            allRewards: [blank],
            purchaseDates: [],
            generalDifficulty: 5
        )
        let configuredPrice = RewardPriceCalculation.calculatePrice(
            reward: configured,
            allRewards: [configured],
            purchaseDates: [],
            generalDifficulty: 5
        )

        #expect(blankPrice > configuredPrice)
    }

    // Behaviour: A blank reward should match the strictest selectable
    // frequency cap plus the highest damage tier, not a separate nil-only rule.
    @Test func blankRewardPriceMatchesExtremeConfiguredReward() {
        let createdAt = Date(timeIntervalSince1970: 1_577_836_800)
        let blank = makeReward(maxFrequency: nil, damageTier: nil, createdAt: createdAt)
        let configured = makeReward(
            maxFrequency: FrequencyBounds.minimumDailyRate,
            damageTier: .extreme,
            createdAt: createdAt
        )

        let blankPrice = RewardPriceCalculation.calculatePrice(
            reward: blank,
            allRewards: [blank],
            purchaseDates: [],
            generalDifficulty: 5
        )
        let configuredPrice = RewardPriceCalculation.calculatePrice(
            reward: configured,
            allRewards: [configured],
            purchaseDates: [],
            generalDifficulty: 5
        )

        #expect(blankPrice == configuredPrice)
    }
}
