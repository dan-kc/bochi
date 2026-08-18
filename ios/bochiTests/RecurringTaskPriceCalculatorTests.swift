import Foundation
import Testing
@testable import bochi

private func makeRecurringTask(
    id: RecordID = "recurringTask-1",
    frequency: Double? = nil,
    lockoutDurationSeconds: Int? = nil,
    basePrice: Int = 100,
    createdAt: Date = Date(timeIntervalSince1970: 1_577_836_800),
    deletedAt: Date? = nil
) -> RecurringTask {
    RecurringTask(
        id: id,
        name: "Test RecurringTask",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: deletedAt,
        frequency: frequency,
        lockoutDurationSeconds: lockoutDurationSeconds,
        basePrice: basePrice
    )
}

struct RecurringTaskFrequencyMultiplierTests {
    // Behaviour: Leaving a recurringTask frequency blank should price it exactly like
    // the highest selectable minimum cadence instead of a separate magic rule.
    @Test func nilFrequencyMatchesHighestConfiguredFrequency() {
        let createdAt = Date(timeIntervalSince1970: 1_577_836_800)
        let blank = makeRecurringTask(frequency: nil, createdAt: createdAt)
        let configured = makeRecurringTask(
            frequency: FrequencyBounds.maximumDailyRate,
            createdAt: createdAt
        )

        let blankMultiplier = RecurringTaskPriceCalculator.calculateFrequencyMultiplier(
            recurringTask: blank,
            completionDates: []
        )
        let configuredMultiplier = RecurringTaskPriceCalculator.calculateFrequencyMultiplier(
            recurringTask: configured,
            completionDates: []
        )

        #expect(blankMultiplier == configuredMultiplier)
    }

    // Behaviour: Equivalent rates should stabilize the same way even if the
    // user picked different UI units such as `1/day` or `30/month`.
    @Test func equivalentRatesShareTheSameCadenceModel() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let createdAt = now.addingTimeInterval(-10 * 86_400)
        let dailyRecurringTask = makeRecurringTask(frequency: 1.0, createdAt: createdAt)
        let monthlyRecurringTask = makeRecurringTask(frequency: 30.0 / 30.0, createdAt: createdAt)
        let completionDates = [now.addingTimeInterval(-86_400)]

        let daily = RecurringTaskPriceCalculator.calculateFrequencyMultiplier(
            recurringTask: dailyRecurringTask,
            completionDates: completionDates,
            now: now
        )
        let monthly = RecurringTaskPriceCalculator.calculateFrequencyMultiplier(
            recurringTask: monthlyRecurringTask,
            completionDates: completionDates,
            now: now
        )

        #expect(abs(daily - monthly) < 0.0001)
    }

    // Behaviour: A newly created recurringTask should not jump straight to the maximum
    // price before the app has enough history to judge the user's cadence.
    @Test func newRecurringTaskStartsNearNeutralDuringWarmup() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let newRecurringTask = makeRecurringTask(
            frequency: 1.0,
            createdAt: now.addingTimeInterval(-6 * 3_600)
        )

        let multiplier = RecurringTaskPriceCalculator.calculateFrequencyMultiplier(
            recurringTask: newRecurringTask,
            completionDates: [],
            now: now
        )

        #expect(multiplier > 1.0)
        #expect(multiplier < 2.0)
    }

    // Behaviour: A brand-new recurringTask should still react once the user has already
    // completed it several times, so same-day overuse does not stay visually
    // flat just because the recurringTask is inside its age-based warm-up window.
    @Test func newRecurringTaskOveruseReactsBeforeAgeWarmupCompletes() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recurringTask = makeRecurringTask(
            frequency: 2.0,
            basePrice: 200,
            createdAt: now
        )
        let completionDates = Array(repeating: now, count: 3)

        let price = RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: completionDates,
            now: now
        )

        #expect(price < recurringTask.basePrice)
    }
}

struct RecurringTaskCalculatePriceTests {
    // Behaviour: A new recurring recurringTask starts at the submitted base price
    // because the warm-up model treats it as on target.
    @Test func newRecurringTaskStartsAtBasePrice() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recurringTask = makeRecurringTask(frequency: 1.0, basePrice: 280, createdAt: now)

        let price = RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: [],
            now: now
        )

        #expect(price == 280)
    }

    // Behaviour: Changing the submitted base price changes the visible recurringTask
    // amount while cadence inputs stay the same.
    @Test func basePriceControlsTheNeutralRecurringTaskPrice() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cheap = makeRecurringTask(id: "cheap", frequency: 1.0, basePrice: 80, createdAt: now)
        let expensive = makeRecurringTask(id: "expensive", frequency: 1.0, basePrice: 240, createdAt: now)

        #expect(RecurringTaskPriceCalculator.calculatePrice(recurringTask: cheap, allRecurringTasks: [cheap], now: now) == 80)
        #expect(RecurringTaskPriceCalculator.calculatePrice(recurringTask: expensive, allRecurringTasks: [expensive], now: now) == 240)
    }

    // Behaviour: one-time price adjustments should change a single recurringTask claim,
    // while lapsed premium ignores that adjustment.
    @Test func oneTimeAdjustmentsStackOnlyWithPremiumAccess() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recurringTask = makeRecurringTask(frequency: 1.0, basePrice: 200, createdAt: now)

        let adjustedPrice = RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: [],
            now: now,
            oneTimeAdjustmentMultiplier: 0.5,
            hasPremiumAccess: true
        )
        let lapsedPrice = RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: [],
            now: now,
            oneTimeAdjustmentMultiplier: 0.5,
            hasPremiumAccess: false
        )

        #expect(adjustedPrice == 100)
        #expect(lapsedPrice == 200)
    }
}

struct RecurringTaskMultiClaimTotalTests {
    // Behaviour: Claiming a recurringTask multiple times in one modal sums each
    // incremental price, so repeated claims reflect diminishing returns.
    @Test func multiClaimMatchesIncrementalPrices() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recurringTask = makeRecurringTask(frequency: 1.0, basePrice: 120, createdAt: now.addingTimeInterval(-10 * 86_400))

        let first = RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: [],
            now: now
        )
        let second = RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: [now],
            now: now
        )
        let total = RecurringTaskPriceCalculator.calculateMultiClaimTotal(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: [],
            quantity: 2,
            now: now
        )

        #expect(total == first + second)
    }
}

struct RecurringTaskTradeQuoteTests {
    // Behaviour: when the user taps a visible recurringTask price, the completion modal
    // should open with that exact quoted amount instead of repricing against a
    // later clock tick.
    @Test func modalOpeningUsesTheTappedListPriceSnapshot() {
        let listedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let modalOpenedAt = listedAt.addingTimeInterval(6 * 86_400)
        let recurringTask = makeRecurringTask(
            frequency: 1.0,
            basePrice: 200,
            createdAt: listedAt.addingTimeInterval(-45 * 86_400)
        )
        let completionDates = [
            listedAt.addingTimeInterval(-86_400)
        ]
        let listPrice = RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: recurringTask,
            allRecurringTasks: [recurringTask],
            completionDates: completionDates,
            now: listedAt
        )

        let quote = RecurringTaskTradeQuote(
            completionDates: completionDates,
            pricedAt: listedAt
        )

        #expect(
            quote.totalPrice(
                recurringTask: recurringTask,
                allRecurringTasks: [recurringTask],
                quantity: 1,
                fallbackNow: modalOpenedAt
            ) == listPrice
        )
    }
}
