import Foundation
import Testing
@testable import bochi

private func makeReward(
    id: RecordID = "reward-1",
    recurring: Bool = true,
    maxFrequency: Double? = nil,
    basePrice: Int = 500,
    createdAt: Date = Date(timeIntervalSince1970: 1_577_836_800),
    deletedAt: Date? = nil
) -> Reward {
    Reward(
        id: id,
        recurring: recurring,
        name: "Test Reward",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: deletedAt,
        maxFrequency: maxFrequency,
        basePrice: basePrice
    )
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

        let blankMultiplier = RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: blank,
            purchaseDates: []
        )
        let configuredMultiplier = RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: configured,
            purchaseDates: []
        )

        #expect(blankMultiplier == configuredMultiplier)
    }

    // Behaviour: One-time rewards ignore cadence and always use a neutral
    // frequency multiplier.
    @Test func oneOffRewardsIgnoreFrequencyHistory() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(recurring: false, maxFrequency: 1.0, createdAt: now.addingTimeInterval(-10 * 86_400))

        #expect(RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [now, now, now],
            now: now
        ) == 1.0)
    }

    // Behaviour: Same-day repeat purchases make the next purchase more
    // expensive, while only heavy overuse clamps at the hard limit.
    @Test func multiplierRisesTowardAndAtCap() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(
            maxFrequency: 3.0,
            createdAt: now.addingTimeInterval(-5 * 86_400)
        )

        let first = RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [now],
            now: now
        )
        let second = RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [now, now],
            now: now
        )
        let capped = RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: Array(repeating: now, count: 9),
            now: now
        )

        #expect(second > first)
        #expect(second < capped)
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

        let multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(
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

        let daily = RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: dailyReward,
            purchaseDates: purchaseDates,
            now: now
        )
        let monthly = RewardPriceCalculator.calculateFrequencyMultiplier(
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

        let multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: [],
            now: now
        )

        #expect(multiplier == 1.0)
    }
}

struct RewardPriceTests {
    // Behaviour: A one-time reward costs exactly the submitted price and ignores
    // purchase cadence.
    @Test func oneOffRewardUsesBasePriceDirectly() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(recurring: false, maxFrequency: nil, basePrice: 450, createdAt: now)

        let purchases = [now.addingTimeInterval(-60), now.addingTimeInterval(-30)]
        #expect(RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: purchases,
            now: now
        ) == 450)
    }

    // Behaviour: The reward list price rises with repeated same-day purchases
    // instead of staying flat.
    @Test func repeatedPurchasesRaiseVisiblePrice() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(maxFrequency: 3.0, basePrice: 200, createdAt: now.addingTimeInterval(-5 * 86_400))

        let first = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            now: now
        )
        let second = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [now],
            now: now
        )
        let third = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [now, now],
            now: now
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
            basePrice: 500,
            createdAt: now.addingTimeInterval(-10 * 86_400)
        )
        let secondToday = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [now.addingTimeInterval(-86_400), now],
            now: now
        )
        let nextPrice = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [
                now.addingTimeInterval(-86_400),
                now,
                now
            ],
            now: now
        )

        #expect(nextPrice > secondToday)
        #expect(nextPrice < reward.basePrice * 20)
    }

    // Behaviour: A user who normally buys a 2/day reward twice per day should
    // see a stern but not maximum-price penalty when buying a fourth time after
    // a single same-day burst.
    @Test func mildlyOverCapDailyRewardUsesSoftPenaltyBeforeMaximumPrice() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(
            maxFrequency: 2.0,
            basePrice: 300,
            createdAt: now.addingTimeInterval(-10 * 86_400)
        )
        var purchaseDates: [Date] = []

        for dayOffset in 1...5 {
            let day = now.addingTimeInterval(-Double(dayOffset) * 86_400)
            purchaseDates.append(day.addingTimeInterval(-12 * 3_600))
            purchaseDates.append(day)
        }
        purchaseDates.append(now.addingTimeInterval(-2 * 3_600))
        purchaseDates.append(now.addingTimeInterval(-3_600))
        purchaseDates.append(now)

        let fourthTodayPrice = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: purchaseDates,
            now: now
        )

        #expect(fourthTodayPrice > reward.basePrice)
        #expect(fourthTodayPrice < reward.basePrice * 20)
    }

    // Behaviour: Buying several rewards in one go sums each incremental price
    // rather than multiplying a flat base price.
    @Test func multiPurchaseMatchesIncrementalTotals() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(maxFrequency: 3.0, basePrice: 200, createdAt: now.addingTimeInterval(-5 * 86_400))

        let first = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            now: now
        )
        let second = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [now],
            now: now
        )
        let total = RewardPriceCalculator.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            quantity: 2,
            now: now
        )

        #expect(total == first + second)
    }

    // Behaviour: Leaving max frequency blank should match the strictest
    // selectable frequency cap when the submitted base price is the same.
    @Test func blankRewardPriceMatchesStrictestConfiguredReward() {
        let createdAt = Date(timeIntervalSince1970: 1_577_836_800)
        let blank = makeReward(maxFrequency: nil, basePrice: 500, createdAt: createdAt)
        let configured = makeReward(
            maxFrequency: FrequencyBounds.minimumDailyRate,
            basePrice: 500,
            createdAt: createdAt
        )

        let blankPrice = RewardPriceCalculator.calculatePrice(
            reward: blank,
            allRewards: [blank],
            purchaseDates: []
        )
        let configuredPrice = RewardPriceCalculator.calculatePrice(
            reward: configured,
            allRewards: [configured],
            purchaseDates: []
        )

        #expect(blankPrice == configuredPrice)
    }

    // Behaviour: one-time price adjustments should change a single purchase,
    // while lapsed premium ignores that adjustment.
    @Test func oneTimeAdjustmentsStackOnlyWithPremiumAccess() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reward = makeReward(recurring: false, basePrice: 400, createdAt: now)

        let adjustedPrice = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            now: now,
            oneTimeAdjustmentMultiplier: 0.5,
            hasPremiumAccess: true
        )
        let lapsedPrice = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: [],
            now: now,
            oneTimeAdjustmentMultiplier: 0.5,
            hasPremiumAccess: false
        )

        #expect(adjustedPrice == 200)
        #expect(lapsedPrice == 400)
    }

    // Behaviour: when the user taps a visible reward price, the purchase modal
    // should open with that exact quoted amount instead of repricing against a
    // later clock tick.
    @Test func modalOpeningUsesTheTappedListPriceSnapshot() {
        let listedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let modalOpenedAt = listedAt.addingTimeInterval(6 * 86_400)
        let reward = makeReward(
            maxFrequency: 1.0,
            basePrice: 500,
            createdAt: listedAt.addingTimeInterval(-45 * 86_400)
        )
        let purchaseDates = [
            listedAt.addingTimeInterval(-86_400)
        ]
        let listPrice = RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: [reward],
            purchaseDates: purchaseDates,
            now: listedAt
        )

        let quote = RewardPurchaseQuote(
            purchaseDates: purchaseDates,
            pricedAt: listedAt
        )

        #expect(
            quote.totalPrice(
                reward: reward,
                allRewards: [reward],
                quantity: 1,
                fallbackNow: modalOpenedAt
            ) == listPrice
        )
    }
}
