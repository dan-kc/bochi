import Foundation
import Testing
@testable import bochi

struct EntityDuplicateSupportTests {
    // Behaviour: duplicating a reward should prefill the new form with every
    // editable reward field while giving the duplicate its own identity.
    @Test func rewardDuplicateSnapshotCopiesEditableFieldsWithFreshID() {
        let reward = Reward(
            id: RecordID("reward-original"),
            name: "Fancy Coffee",
            description: "Saturday treat",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            deletedAt: nil,
            maxFrequency: 0.5,
            lockoutDurationSeconds: 86_400,
            basePrice: 450
        )

        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: reward,
            tagIDs: [RecordID("treats"), RecordID("weekend")],
            newID: RecordID("reward-copy")
        )

        #expect(snapshot.selectedEntity == EntityFormKind.reward)
        #expect(snapshot.shared.name == "Fancy Coffee")
        #expect(snapshot.shared.description == "Saturday treat")
        #expect(snapshot.shared.tagIDs == [RecordID("treats"), RecordID("weekend")])
        #expect(snapshot.reward.rewardId == RecordID("reward-copy"))
        #expect(snapshot.reward.recurring == true)
        #expect(snapshot.reward.maxFrequency == 0.5)
        #expect(snapshot.reward.lockoutDurationSeconds == 86_400)
        #expect(snapshot.reward.basePrice == 450)
    }

    // Behaviour: duplicating a one-time reward should keep the one-time cadence
    // so saving the new draft does not silently create a recurring reward.
    @Test func rewardDuplicateSnapshotPreservesOneOffCadence() {
        let reward = Reward(
            id: RecordID("reward-original"),
            recurring: false,
            name: "Concert ticket",
            description: "One night only",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            deletedAt: nil,
            maxFrequency: nil,
            basePrice: 900
        )

        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: reward,
            tagIDs: [],
            newID: RecordID("reward-copy")
        )

        #expect(snapshot.selectedEntity == EntityFormKind.reward)
        #expect(snapshot.reward.rewardId == RecordID("reward-copy"))
        #expect(snapshot.reward.recurring == false)
        #expect(snapshot.reward.maxFrequency == nil)
        #expect(snapshot.reward.basePrice == 900)
    }

    // Behaviour: duplicating a recurringTask should carry over cadence, base price,
    // reminders, lockout, and tags without reusing the original ID.
    @Test func recurringTaskDuplicateSnapshotCopiesEditableFieldsWithFreshID() {
        let recurringTask = RecurringTask(
            id: RecordID("recurringTask-original"),
            name: "Morning Run",
            description: "Easy miles",
            createdAt: Date(timeIntervalSince1970: 1_800_010_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_010_100),
            deletedAt: nil,
            frequency: 1,
            lockoutDurationSeconds: 43_200,
            basePrice: 150
        )
        let reminder = ReminderDraft(id: "recurringTask-reminder", scheduledAt: Date(timeIntervalSince1970: 1_800_010_500))

        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: recurringTask,
            tagIDs: [RecordID("health")],
            reminderDrafts: [reminder],
            newID: RecordID("recurringTask-copy")
        )

        #expect(snapshot.selectedEntity == EntityFormKind.recurringTask)
        #expect(snapshot.shared.name == "Morning Run")
        #expect(snapshot.shared.description == "Easy miles")
        #expect(snapshot.shared.tagIDs == [RecordID("health")])
        #expect(snapshot.recurringTask.recurringTaskId == RecordID("recurringTask-copy"))
        #expect(snapshot.recurringTask.frequency == 1)
        #expect(snapshot.recurringTask.basePrice == 150)
        #expect(snapshot.recurringTask.reminderDrafts.map { $0.id } == ["recurringTask-reminder"])
        #expect(snapshot.recurringTask.lockoutDurationSeconds == 43_200)
    }

    // Behaviour: duplicating a task should make a fresh incomplete task draft
    // while preserving tags, reminders, due date, base price, and dependencies.
    @Test func taskDuplicateSnapshotCopiesDependenciesOntoFreshTaskID() {
        let task = TaskItem(
            id: RecordID("task-original"),
            name: "File Taxes",
            description: "Include receipts",
            createdAt: Date(timeIntervalSince1970: 1_800_020_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_020_100),
            deletedAt: nil,
            basePrice: 350,
            dueDate: Date(timeIntervalSince1970: 1_800_030_000)
        )
        let taskDependency = TaskTaskDependency(
            taskId: task.id,
            dependsOnTaskId: RecordID("prerequisite-task"),
            createdAt: Date(timeIntervalSince1970: 1_800_020_300),
            updatedAt: Date(timeIntervalSince1970: 1_800_020_400),
            deletedAt: nil
        )
        let deletedTaskDependency = TaskTaskDependency(
            taskId: task.id,
            dependsOnTaskId: RecordID("removed-task"),
            createdAt: Date(timeIntervalSince1970: 1_800_020_500),
            updatedAt: Date(timeIntervalSince1970: 1_800_020_600),
            deletedAt: Date(timeIntervalSince1970: 1_800_020_700)
        )
        let recurringTaskDependency = TaskRecurringTaskDependency(
            taskId: task.id,
            recurringTaskId: RecordID("prerequisite-recurringTask"),
            requiredCompletions: 3,
            baselineCompletionCount: 12,
            createdAt: Date(timeIntervalSince1970: 1_800_020_800),
            updatedAt: Date(timeIntervalSince1970: 1_800_020_900),
            deletedAt: nil
        )
        let reminder = ReminderDraft(id: "task-reminder", scheduledAt: Date(timeIntervalSince1970: 1_800_021_000))

        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: task,
            tagIDs: [RecordID("admin")],
            reminderDrafts: [reminder],
            taskDependencies: [taskDependency, deletedTaskDependency],
            recurringTaskDependencies: [recurringTaskDependency],
            newID: RecordID("task-copy")
        )

        #expect(snapshot.selectedEntity == EntityFormKind.task)
        #expect(snapshot.shared.name == "File Taxes")
        #expect(snapshot.shared.description == "Include receipts")
        #expect(snapshot.shared.tagIDs == [RecordID("admin")])
        #expect(snapshot.task.taskId == RecordID("task-copy"))
        #expect(snapshot.task.basePrice == 350)
        #expect(snapshot.task.dueDate == Date(timeIntervalSince1970: 1_800_030_000))
        #expect(snapshot.task.reminderDrafts.map { $0.id } == ["task-reminder"])
        #expect(snapshot.task.taskDependencies.map { $0.taskId } == [RecordID("task-copy")])
        #expect(snapshot.task.taskDependencies.map { $0.dependsOnTaskId } == [RecordID("prerequisite-task")])
        #expect(snapshot.task.recurringTaskDependencies.map { $0.taskId } == [RecordID("task-copy")])
        #expect(snapshot.task.recurringTaskDependencies.map { $0.recurringTaskId } == [RecordID("prerequisite-recurringTask")])
        #expect(snapshot.task.recurringTaskDependencies.map { $0.requiredCompletions } == [3])
    }
}
