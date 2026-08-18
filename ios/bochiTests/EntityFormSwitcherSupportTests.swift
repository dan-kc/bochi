import Foundation
import Testing
@testable import bochi

struct EntityFormSwitcherSupportTests {
    // Behaviour: edit forms show a compact entity label, while new-entity forms
    // keep the full selection control for switching between entity types.
    @Test func switcherLayoutMatchesWhetherEntitySelectionIsAvailable() {
        #expect(EntityFormSwitcherSupport.layout(hasEntitySelection: false).rawValue == "compactLabel")
        #expect(EntityFormSwitcherSupport.layout(hasEntitySelection: true).rawValue == "segmentedControl")
    }

    // Behaviour: a fresh new-entity form requires the user to choose a price
    // instead of silently submitting an entity with an old default.
    @Test func initialSnapshotLeavesBasePricesUnset() {
        let snapshot = EntityFormSwitcherSupport.makeInitialSnapshot(selectedEntity: .task)

        #expect(snapshot.selectedEntity == EntityFormKind.task)
        #expect(snapshot.task.basePrice == nil)
        #expect(snapshot.recurringTask.basePrice == nil)
        #expect(snapshot.reward.basePrice == nil)
    }

    // Behaviour: derived form snapshots should rehydrate the exact entity view
    // data the user expects after toggling away and back.
    @Test func derivedSnapshotsRehydrateSharedAndSpecificFields() {
        let reminder = ReminderDraft(id: "shared-reminder", scheduledAt: Date(timeIntervalSince1970: 1_800_020_100))
        let snapshot = NewEntityFormSnapshot(
            selectedEntity: .recurringTask,
            shared: NewEntitySharedDraft(
                name: "Workout",
                description: "Morning block",
                tagIDs: [RecordID("health")]
            ),
            task: NewTaskDraft(
                basePrice: 250,
                dueDate: Date(timeIntervalSince1970: 1_800_020_000),
                timerSelection: .duration,
                reminderDrafts: [reminder],
                taskId: RecordID("task-1"),
                taskDependencies: [],
                recurringTaskDependencies: []
            ),
            recurringTask: NewRecurringTaskDraft(
                frequency: 4,
                lockoutDurationSeconds: 3_600,
                basePrice: 125,
                timerSelection: .named(RecordID("timer-1")),
                reminderDrafts: [reminder],
                recurringTaskId: RecordID("recurringTask-1")
            ),
            reward: NewRewardDraft(
                recurring: true,
                maxFrequency: 1,
                lockoutDurationSeconds: 7_200,
                basePrice: 450,
                timerSelection: .none,
                rewardId: RecordID("reward-1"),
                taskDependencies: [],
                recurringTaskDependencies: []
            )
        )

        let taskSnapshot = EntityFormSwitcherSupport.taskSnapshot(from: snapshot)
        let recurringTaskSnapshot = EntityFormSwitcherSupport.recurringTaskSnapshot(from: snapshot)
        let rewardSnapshot = EntityFormSwitcherSupport.rewardSnapshot(from: snapshot)

        #expect(taskSnapshot.name == "Workout")
        #expect(taskSnapshot.basePrice == 250)
        #expect(taskSnapshot.tagIDs == [RecordID("health")])
        #expect(taskSnapshot.reminderDrafts.map { $0.id } == ["shared-reminder"])
        #expect(recurringTaskSnapshot.name == "Workout")
        #expect(recurringTaskSnapshot.frequency == 4)
        #expect(recurringTaskSnapshot.lockoutDurationSeconds == 3_600)
        #expect(recurringTaskSnapshot.basePrice == 125)
        #expect(recurringTaskSnapshot.timerSelection == EntityTimerSelection.named(RecordID("timer-1")))
        #expect(rewardSnapshot.name == "Workout")
        #expect(rewardSnapshot.recurring == true)
        #expect(rewardSnapshot.maxFrequency == 1)
        #expect(rewardSnapshot.lockoutDurationSeconds == 7_200)
        #expect(rewardSnapshot.basePrice == 450)
        #expect(rewardSnapshot.tagIDs == [RecordID("health")])
    }

    // Behaviour: the unified draft should still offer recovery after the user
    // changed only one of the entity-specific base prices before dismissing.
    @Test func recoverableContentChecksAllEntityDrafts() {
        let blankSnapshot = EntityFormSwitcherSupport.makeInitialSnapshot(selectedEntity: .task)
        #expect(EntityFormSwitcherSupport.hasRecoverableContent(blankSnapshot) == false)

        let rewardOnlySnapshot = NewEntityFormSnapshot(
            selectedEntity: blankSnapshot.selectedEntity,
            shared: blankSnapshot.shared,
            task: blankSnapshot.task,
            recurringTask: blankSnapshot.recurringTask,
            reward: NewRewardDraft(
                recurring: blankSnapshot.reward.recurring,
                maxFrequency: blankSnapshot.reward.maxFrequency,
                lockoutDurationSeconds: blankSnapshot.reward.lockoutDurationSeconds,
                basePrice: 600,
                timerSelection: blankSnapshot.reward.timerSelection,
                rewardId: blankSnapshot.reward.rewardId,
                taskDependencies: blankSnapshot.reward.taskDependencies,
                recurringTaskDependencies: blankSnapshot.reward.recurringTaskDependencies
            )
        )

        #expect(EntityFormSwitcherSupport.hasRecoverableContent(rewardOnlySnapshot) == true)
    }
}
