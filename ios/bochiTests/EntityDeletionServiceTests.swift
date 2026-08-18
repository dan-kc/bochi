import Foundation
import Testing
@testable import bochi

@MainActor
struct EntityDeletionServiceTests {
    private func makeStorageURL() -> URL {
        TestHelpers.makeTemporaryFileURL("entity-deletion-service")
    }

    // Behaviour: deleting a task should clear its reminders and every dependency
    // pointing at it, so no list or reward stays blocked by a deleted task.
    @Test func deletingTaskClearsRemindersAndDependencies() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let taskDependencyStore = TaskDependencyStore(storageURL: storageURL)
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)
        let deletedAt = Date(timeIntervalSince1970: 1_800_001_000)

        let deletedTask = try #require(taskStore.addTask(id: "task-delete", name: "File taxes"))
        let blockedTask = try #require(taskStore.addTask(id: "task-blocked", name: "Submit forms"))
        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))

        reminderStore.replaceReminders(
            for: .task(deletedTask.id),
            with: [ReminderDraft(id: "task-reminder", scheduledAt: Date().addingTimeInterval(600))]
        )
        taskDependencyStore.replaceDependencies(
            for: blockedTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: blockedTask.id,
                    dependsOnTaskId: deletedTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 7
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )
        rewardDependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: deletedTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 8
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        EntityDeletionService.deleteTask(
            deletedTask,
            reminderStore: reminderStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore,
            deletedAt: deletedAt
        )

        #expect(taskStore.tasks.first { $0.id == deletedTask.id }?.deletedAt == deletedAt)
        #expect(reminderStore.reminders(for: .task(deletedTask.id)).isEmpty)
        #expect(taskDependencyStore.taskTaskDependencies.count == 1)
        #expect(taskDependencyStore.taskTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(taskDependencyStore.taskTaskDependencies.allSatisfy { $0.serverRevision == 7 })
        #expect(rewardDependencyStore.rewardTaskDependencies.count == 1)
        #expect(rewardDependencyStore.rewardTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(rewardDependencyStore.rewardTaskDependencies.allSatisfy { $0.serverRevision == 8 })
    }

    // Behaviour: deleting a recurring task should remove its reminders at the
    // same time as dependent rows, so stale notifications and prerequisites
    // cannot survive deletion.
    @Test func deletingRecurringTaskClearsRemindersAndDependencies() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let taskDependencyStore = TaskDependencyStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)
        let deletedAt = Date(timeIntervalSince1970: 1_800_001_100)

        let task = try #require(taskStore.addTask(id: "task-1", name: "Submit forms"))
        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let recurringTask = try #require(
            recurringTaskStore.addRecurringTask(id: "recurring-task-1", name: "Stretch")
        )
        reminderStore.replaceReminders(
            for: .recurringTask(recurringTask.id),
            with: [ReminderDraft(id: "recurring-reminder", scheduledAt: Date().addingTimeInterval(600))]
        )
        taskDependencyStore.replaceDependencies(
            for: task.id,
            taskDependencies: [],
            recurringTaskDependencies: [
                TaskRecurringTaskDependency(
                    taskId: task.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 1,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 9
                )
            ],
            shouldNotifySync: false
        )
        rewardDependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 2,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 10
                )
            ],
            shouldNotifySync: false
        )

        EntityDeletionService.deleteRecurringTask(
            recurringTask,
            reminderStore: reminderStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            deletedAt: deletedAt
        )

        #expect(recurringTaskStore.recurringTasks.first { $0.id == recurringTask.id }?.deletedAt == deletedAt)
        #expect(reminderStore.reminders(for: .recurringTask(recurringTask.id)).isEmpty)
        #expect(taskDependencyStore.taskRecurringTaskDependencies.count == 1)
        #expect(taskDependencyStore.taskRecurringTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(taskDependencyStore.taskRecurringTaskDependencies.allSatisfy { $0.serverRevision == 9 })
        #expect(rewardDependencyStore.rewardRecurringTaskDependencies.count == 1)
        #expect(rewardDependencyStore.rewardRecurringTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(rewardDependencyStore.rewardRecurringTaskDependencies.allSatisfy { $0.serverRevision == 10 })
    }

    // Behaviour: deleting a reward should tombstone all of its prerequisites so
    // sync cannot later resurrect stale lock conditions for a hidden reward.
    @Test func deletingRewardClearsRewardDependencies() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let deletedAt = Date(timeIntervalSince1970: 1_800_001_200)

        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurring-task-1", name: "Walk"))
        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))

        rewardDependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 11
                )
            ],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 1,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 12
                )
            ],
            shouldNotifySync: false
        )

        EntityDeletionService.deleteReward(
            reward,
            rewardDependencyStore: rewardDependencyStore,
            rewardStore: rewardStore,
            deletedAt: deletedAt
        )

        #expect(rewardStore.rewards.first { $0.id == reward.id }?.deletedAt == deletedAt)
        #expect(!rewardDependencyStore.hasDependencies(for: reward.id))
        #expect(rewardDependencyStore.rewardTaskDependencies.count == 1)
        #expect(rewardDependencyStore.rewardRecurringTaskDependencies.count == 1)
        #expect(rewardDependencyStore.rewardTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(rewardDependencyStore.rewardRecurringTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(rewardDependencyStore.rewardTaskDependencies.allSatisfy { $0.serverRevision == 11 })
        #expect(rewardDependencyStore.rewardRecurringTaskDependencies.allSatisfy { $0.serverRevision == 12 })
    }
}
