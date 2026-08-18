import Foundation
import Testing
@testable import bochi

private func makeTask(
    id: RecordID = "task-1",
    basePrice: Int = 200,
    dueDate: Date? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_577_836_800),
    deletedAt: Date? = nil
) -> TaskItem {
    TaskItem(
        id: id,
        name: "Test Task",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: deletedAt,
        basePrice: basePrice,
        dueDate: dueDate
    )
}

struct TaskPriceCalculatorTests {
    // Behaviour: one-time task pricing should use the user-entered price directly.
    @Test func taskPriceUsesBasePriceDirectly() {
        #expect(TaskPriceCalculator.calculatePrice(task: makeTask(basePrice: 40)) == 40)
        #expect(TaskPriceCalculator.calculatePrice(task: makeTask(basePrice: 420)) == 420)
    }

    // Behaviour: task metadata should not change the submitted price.
    @Test func dueDateDoesNotChangePrice() {
        let baseline = makeTask(basePrice: 175, dueDate: nil)
        let rescheduled = makeTask(
            basePrice: 175,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(TaskPriceCalculator.calculatePrice(task: baseline) == TaskPriceCalculator.calculatePrice(task: rescheduled))
    }

    // Behaviour: one-time price adjustments should change a single task claim
    // without requiring any permanent task-level price field.
    @Test func oneTimeAdjustmentStacksOnlyWithPremiumAccess() {
        let task = makeTask(basePrice: 200)
        let adjustedPrice = TaskPriceCalculator.calculatePrice(
            task: task,
            oneTimeAdjustmentMultiplier: 1.5,
            hasPremiumAccess: true
        )
        let lapsedPrice = TaskPriceCalculator.calculatePrice(
            task: task,
            oneTimeAdjustmentMultiplier: 1.5,
            hasPremiumAccess: false
        )

        #expect(adjustedPrice == 300)
        #expect(lapsedPrice == 200)
    }
}
