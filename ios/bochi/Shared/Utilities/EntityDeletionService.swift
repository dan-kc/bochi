import Foundation

// Sync flow: user deletions go through here so dependent rows are tombstoned by
// their stores and pushed consistently instead of leaving dangling records.
@MainActor
enum EntityDeletionService {
    static func deleteTask(
        _ task: TaskItem,
        reminderStore: ReminderStore,
        taskDependencyStore: TaskDependencyStore,
        rewardDependencyStore: RewardDependencyStore,
        taskStore: TaskStore,
        deletedAt: Date = Date()
    ) {
        reminderStore.deleteAllReminders(for: .task(task.id))
        taskDependencyStore.deleteDependenciesReferencingTask(task.id, deletedAt: deletedAt)
        rewardDependencyStore.deleteDependenciesReferencingTask(task.id, deletedAt: deletedAt)
        taskStore.deleteTask(id: task.id, deletedAt: deletedAt)
    }

    static func deleteRecurringTask(
        _ recurringTask: RecurringTask,
        reminderStore: ReminderStore,
        taskDependencyStore: TaskDependencyStore,
        rewardDependencyStore: RewardDependencyStore,
        recurringTaskStore: RecurringTaskStore,
        deletedAt: Date = Date()
    ) {
        reminderStore.deleteAllReminders(for: .recurringTask(recurringTask.id))
        taskDependencyStore.deleteDependenciesReferencingRecurringTask(recurringTask.id, deletedAt: deletedAt)
        rewardDependencyStore.deleteDependenciesReferencingRecurringTask(recurringTask.id, deletedAt: deletedAt)
        recurringTaskStore.deleteRecurringTask(id: recurringTask.id, deletedAt: deletedAt)
    }

    static func deleteReward(
        _ reward: Reward,
        rewardDependencyStore: RewardDependencyStore,
        rewardStore: RewardStore,
        deletedAt: Date = Date()
    ) {
        rewardDependencyStore.deleteDependenciesReferencingReward(reward.id, deletedAt: deletedAt)
        rewardStore.deleteReward(id: reward.id, deletedAt: deletedAt)
    }
}
