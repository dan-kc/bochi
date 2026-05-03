import Foundation
import Testing
@testable import tofustash

private func makeTask(
    id: RecordID = "task-1",
    difficultyTier: HabitDifficultyTier? = nil,
    durationSeconds: Int? = nil,
    commitment: Int? = nil,
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
        commitment: commitment,
        dueDate: dueDate
    )
}

struct TaskRewardCalculationTests {
    // Behaviour: Leaving every optional pricing input blank should still let
    // the user claim the task, but only at the minimum reward amount.
    @Test func missingFieldsUseTheMinimumReward() {
        let reward = TaskRewardCalculation.calculateReward(task: makeTask())
        #expect(reward == 40)
    }

    // Behaviour: Filling in harder, longer, and more committed task details
    // should improve the reward compared with the blank default.
    @Test func richerTaskDetailsIncreaseReward() {
        let cheapest = makeTask()
        let richer = makeTask(
            difficultyTier: .hard,
            durationSeconds: 1_800,
            commitment: 4
        )

        #expect(TaskRewardCalculation.calculateReward(task: richer) > TaskRewardCalculation.calculateReward(task: cheapest))
    }

    // Behaviour: Only the pricing fields should affect reward. Metadata like
    // due date or completion timestamps must not change the payout.
    @Test func dueDateAndCompletionDoNotChangeReward() {
        let baseline = makeTask(
            difficultyTier: .medium,
            durationSeconds: 900,
            commitment: 3,
            dueDate: nil,
            completedAt: nil
        )
        let rescheduled = makeTask(
            difficultyTier: .medium,
            durationSeconds: 900,
            commitment: 3,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            completedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        #expect(TaskRewardCalculation.calculateReward(task: baseline) == TaskRewardCalculation.calculateReward(task: rescheduled))
    }

    // Behaviour: task special offers should boost the one-shot reward by the
    // same percentage shown in the task list.
    @Test func specialOfferRaisesTaskReward() {
        let task = makeTask(
            difficultyTier: .hard,
            durationSeconds: 1_800,
            commitment: 4
        )

        let baseReward = TaskRewardCalculation.calculateReward(task: task)
        let boostedReward = TaskRewardCalculation.calculateReward(
            task: task,
            specialOfferModifierPercent: 40
        )

        #expect(boostedReward == Int((Double(baseReward) * 1.4).rounded()))
    }

    // Behaviour: Higher commitment should use the doubled-impact multiplier curve.
    @Test func commitmentUsesDoubledImpactCurve() {
        #expect(TaskRewardCalculation.calculateCommitmentMultiplier(task: makeTask(commitment: 1)) == 1.0)
        #expect(TaskRewardCalculation.calculateCommitmentMultiplier(task: makeTask(commitment: 3)) == 1.6)
        #expect(TaskRewardCalculation.calculateCommitmentMultiplier(task: makeTask(commitment: 5)) == 2.5)
    }
}
