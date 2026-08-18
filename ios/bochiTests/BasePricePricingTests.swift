import Foundation
import Testing
@testable import bochi

struct BasePricePricingTests {
    // Behaviour: a one-time task pays exactly the user-entered price unless the
    // user applies a one-time adjustment while claiming it.
    @Test func taskUsesBasePriceDirectly() {
        let task = TaskItem(
            id: RecordID("task-1"),
            name: "Submit report",
            description: "",
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            basePrice: 275,
            dueDate: nil
        )

        #expect(TaskPriceCalculator.calculatePrice(task: task) == 275)
        #expect(TaskPriceCalculator.calculatePrice(task: task, oneTimeAdjustmentMultiplier: 2) == 550)
    }

    // Behaviour: visible action prices are ledger amounts, so multiplier math
    // must still stay inside the signed i32 range accepted by sync.
    @Test func adjustedPricesClampToBackendMaximum() {
        let task = TaskItem(
            id: RecordID("task-1"),
            name: "Submit report",
            description: "",
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            basePrice: BackendIntegerContract.max,
            dueDate: nil
        )

        #expect(
            TaskPriceCalculator.calculatePrice(task: task, oneTimeAdjustmentMultiplier: 2)
                == BackendIntegerContract.max
        )
    }

    // Behaviour: a typed adjusted total for a multi-claim is split across the
    // generated trade rows without losing or adding points to the visible total.
    @Test func adjustedTotalsDistributeExactlyAcrossTradeRows() {
        let prices = PriceAdjustmentSupport.distributedPrices(
            adjustedTotal: 1,
            basePrices: [1, 1]
        )

        #expect(prices.count == 2)
        #expect(prices.reduce(0, +) == 1)
    }

    // Behaviour: a new recurring recurringTask starts at its submitted base price
    // because the warm-up model treats it as on target.
    @Test func newRecurringTaskStartsAtBasePrice() {
        let now = Date()
        let recurringTask = RecurringTask(
            id: RecordID("recurringTask-1"),
            name: "Walk",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            frequency: 1,
            basePrice: 120
        )

        #expect(RecurringTaskPriceCalculator.calculatePrice(recurringTask: recurringTask, allRecurringTasks: [], now: now) == 120)
    }

    // Behaviour: a one-time reward costs exactly the submitted price and ignores
    // purchase cadence.
    @Test func oneOffRewardUsesBasePriceDirectly() {
        let now = Date()
        let reward = Reward(
            id: RecordID("reward-1"),
            recurring: false,
            name: "Dessert",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            maxFrequency: nil,
            basePrice: 450
        )

        let purchases = [now.addingTimeInterval(-60), now.addingTimeInterval(-30)]
        #expect(RewardPriceCalculator.calculatePrice(reward: reward, allRewards: [], purchaseDates: purchases, now: now) == 450)
    }

    // Behaviour: the action button delta is omitted when the live price equals
    // base price, and shown as a signed percentage when cadence changes it.
    @Test func priceDeltaPercentComparesLivePriceToBasePrice() {
        #expect(PriceDeltaSupport.percent(currentPrice: 100, basePrice: 100) == nil)
        #expect(PriceDeltaSupport.percent(currentPrice: 112, basePrice: 100) == 12)
        #expect(PriceDeltaSupport.percent(currentPrice: 40, basePrice: 100) == -60)
    }
}
