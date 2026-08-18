import SwiftUI

enum DependencyDraftSupport {
    static func addTaskDependency(
        to dependencies: inout [TaskTaskDependency],
        taskID: RecordID,
        selectedTask: TaskItem,
        now: Date = Date()
    ) {
        let dependencyID = RecordID("\(taskID):\(selectedTask.id)")
        let existingDependency = dependencies.first { $0.id == dependencyID }
        let updatedAt = nextDependencyUpdateTimestamp(after: existingDependency?.updatedAt, now: now)
        let dependency = TaskTaskDependency(
            taskId: taskID,
            dependsOnTaskId: selectedTask.id,
            createdAt: existingDependency?.createdAt ?? updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            serverRevision: existingDependency?.serverRevision
        )
        dependencies = OwnerScopedRecordSupport.mergeRecords(local: dependencies, remote: [dependency])
    }

    static func addTaskDependency(
        to dependencies: inout [RewardTaskDependency],
        rewardID: RecordID,
        selectedTask: TaskItem,
        now: Date = Date()
    ) {
        let dependencyID = RecordID("\(rewardID):\(selectedTask.id)")
        let existingDependency = dependencies.first { $0.id == dependencyID }
        let updatedAt = nextDependencyUpdateTimestamp(after: existingDependency?.updatedAt, now: now)
        let dependency = RewardTaskDependency(
            rewardId: rewardID,
            dependsOnTaskId: selectedTask.id,
            createdAt: existingDependency?.createdAt ?? updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            serverRevision: existingDependency?.serverRevision
        )
        dependencies = OwnerScopedRecordSupport.mergeRecords(local: dependencies, remote: [dependency])
    }

    static func saveRecurringTaskDependency(
        to dependencies: inout [TaskRecurringTaskDependency],
        taskID: RecordID,
        recurringTask: RecurringTask,
        existingDependency: TaskRecurringTaskDependency?,
        requiredCompletions: Int,
        baselineCompletionCount: Int,
        now: Date = Date()
    ) {
        let dependencyID = RecordID("\(taskID):\(recurringTask.id)")
        let existingDependency = existingDependency ?? dependencies.first { $0.id == dependencyID }
        let updatedAt = nextDependencyUpdateTimestamp(after: existingDependency?.updatedAt, now: now)
        let dependency = TaskRecurringTaskDependency(
            taskId: taskID,
            recurringTaskId: recurringTask.id,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: baselineCompletionCount,
            createdAt: existingDependency?.createdAt ?? updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            serverRevision: existingDependency?.serverRevision
        )
        dependencies = OwnerScopedRecordSupport.mergeRecords(local: dependencies, remote: [dependency])
    }

    static func saveRecurringTaskDependency(
        to dependencies: inout [RewardRecurringTaskDependency],
        rewardID: RecordID,
        recurringTask: RecurringTask,
        existingDependency: RewardRecurringTaskDependency?,
        requiredCompletions: Int,
        baselineCompletionCount: Int,
        now: Date = Date()
    ) {
        let dependencyID = RecordID("\(rewardID):\(recurringTask.id)")
        let existingDependency = existingDependency ?? dependencies.first { $0.id == dependencyID }
        let updatedAt = nextDependencyUpdateTimestamp(after: existingDependency?.updatedAt, now: now)
        let dependency = RewardRecurringTaskDependency(
            rewardId: rewardID,
            recurringTaskId: recurringTask.id,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: baselineCompletionCount,
            createdAt: existingDependency?.createdAt ?? updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            serverRevision: existingDependency?.serverRevision
        )
        dependencies = OwnerScopedRecordSupport.mergeRecords(local: dependencies, remote: [dependency])
    }

    static func recurringTaskDependencyCountBinding<Dependency>(
        dependency: Dependency,
        recurringTask: RecurringTask,
        requiredCompletions: KeyPath<Dependency, Int>,
        save: @escaping (RecurringTask, Dependency, Int) -> Void
    ) -> Binding<Int> {
        Binding(
            get: { dependency[keyPath: requiredCompletions] },
            set: { save(recurringTask, dependency, $0) }
        )
    }

    static func remove<Dependency: Identifiable>(
        _ dependency: Dependency,
        from dependencies: inout [Dependency]
    ) where Dependency.ID: Equatable {
        dependencies.removeAll { $0.id == dependency.id }
    }

    private static func nextDependencyUpdateTimestamp(after existingUpdatedAt: Date?, now: Date) -> Date {
        guard let existingUpdatedAt else { return now }
        return now > existingUpdatedAt ? now : existingUpdatedAt.addingTimeInterval(0.001)
    }
}
