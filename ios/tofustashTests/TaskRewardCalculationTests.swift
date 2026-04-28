import Foundation
import Testing
@testable import tofustash

private func makeTask(
    id: RecordID = "task-1",
    difficultyTier: HabitDifficultyTier? = nil,
    durationSeconds: Int? = nil,
    skipConsequence: Int? = nil,
    dueDate: Date? = nil,
    completedAt: Date? = nil,
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
        completedAt: completedAt,
        difficultyTier: difficultyTier,
        durationSeconds: durationSeconds,
        skipConsequence: skipConsequence,
        dueDate: dueDate
    )
}

struct TaskRewardCalculationTests {
    // Behaviour: Leaving every optional pricing input blank should still let
    // the user claim the task, but only at the minimum reward amount.
    @Test func missingFieldsUseTheMinimumReward() {
        let reward = TaskRewardCalculation.calculateReward(task: makeTask())
        #expect(reward == 20)
    }

    // Behaviour: Filling in harder, longer, and more consequential task details
    // should improve the reward compared with the blank default.
    @Test func richerTaskDetailsIncreaseReward() {
        let cheapest = makeTask()
        let richer = makeTask(
            difficultyTier: .hard,
            durationSeconds: 1_800,
            skipConsequence: 4
        )

        #expect(TaskRewardCalculation.calculateReward(task: richer) > TaskRewardCalculation.calculateReward(task: cheapest))
    }

    // Behaviour: Only the pricing fields should affect reward. Metadata like
    // due date or completion timestamps must not change the payout.
    @Test func dueDateAndCompletionDoNotChangeReward() {
        let baseline = makeTask(
            difficultyTier: .medium,
            durationSeconds: 900,
            skipConsequence: 3,
            dueDate: nil,
            completedAt: nil
        )
        let rescheduled = makeTask(
            difficultyTier: .medium,
            durationSeconds: 900,
            skipConsequence: 3,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            completedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        #expect(TaskRewardCalculation.calculateReward(task: baseline) == TaskRewardCalculation.calculateReward(task: rescheduled))
    }
}
