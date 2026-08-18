import Foundation

nonisolated enum EntityDependencyBlockingSupport {
    static func blockedTaskIDs(
        tasks: [TaskItem],
        allTasks: [TaskItem],
        taskTaskDependencies: [TaskTaskDependency],
        taskRecurringTaskDependencies: [TaskRecurringTaskDependency],
        latestTaskTradesByTaskID: [RecordID: Trade],
        recurringTaskCompletionCountsByRecurringTaskID: [RecordID: Int],
        hasPremiumAccess: Bool
    ) -> Set<RecordID> {
        guard hasPremiumAccess else { return [] }

        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        let activeTaskDependenciesByTaskID = Dictionary(
            grouping: taskTaskDependencies.filter { $0.deletedAt == nil },
            by: \.taskId
        )
        let activeRecurringTaskDependenciesByTaskID = Dictionary(
            grouping: taskRecurringTaskDependencies.filter { $0.deletedAt == nil },
            by: \.taskId
        )

        let completedTaskIDs = Set(latestTaskTradesByTaskID.keys)

        return Set(tasks.compactMap { task in
            guard task.deletedAt == nil, !completedTaskIDs.contains(task.id) else { return nil }

            if activeTaskDependenciesByTaskID[task.id, default: []].contains(where: { dependency in
                guard let prerequisiteTask = tasksByID[dependency.dependsOnTaskId] else { return false }
                guard prerequisiteTask.deletedAt == nil else { return false }
                return !completedTaskIDs.contains(prerequisiteTask.id)
            }) {
                return task.id
            }

            if activeRecurringTaskDependenciesByTaskID[task.id, default: []].contains(where: { dependency in
                let progress = max(
                    0,
                    recurringTaskCompletionCountsByRecurringTaskID[dependency.recurringTaskId, default: 0]
                        - dependency.baselineCompletionCount
                )
                return progress < dependency.requiredCompletions
            }) {
                return task.id
            }

            return nil
        })
    }

    static func blockedRewardIDs(
        rewards: [Reward],
        allTasks: [TaskItem],
        rewardTaskDependencies: [RewardTaskDependency],
        rewardRecurringTaskDependencies: [RewardRecurringTaskDependency],
        latestTaskTradesByTaskID: [RecordID: Trade],
        recurringTaskCompletionCountsByRecurringTaskID: [RecordID: Int],
        hasPremiumAccess: Bool
    ) -> Set<RecordID> {
        guard hasPremiumAccess else { return [] }

        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        let activeTaskDependenciesByRewardID = Dictionary(
            grouping: rewardTaskDependencies.filter { $0.deletedAt == nil },
            by: \.rewardId
        )
        let activeRecurringTaskDependenciesByRewardID = Dictionary(
            grouping: rewardRecurringTaskDependencies.filter { $0.deletedAt == nil },
            by: \.rewardId
        )

        let completedTaskIDs = Set(latestTaskTradesByTaskID.keys)

        return Set(rewards.compactMap { reward in
            guard reward.deletedAt == nil else { return nil }

            if activeTaskDependenciesByRewardID[reward.id, default: []].contains(where: { dependency in
                guard let prerequisiteTask = tasksByID[dependency.dependsOnTaskId] else { return false }
                guard prerequisiteTask.deletedAt == nil else { return false }
                return !completedTaskIDs.contains(prerequisiteTask.id)
            }) {
                return reward.id
            }

            if activeRecurringTaskDependenciesByRewardID[reward.id, default: []].contains(where: { dependency in
                let progress = max(
                    0,
                    recurringTaskCompletionCountsByRecurringTaskID[dependency.recurringTaskId, default: 0]
                        - dependency.baselineCompletionCount
                )
                return progress < dependency.requiredCompletions
            }) {
                return reward.id
            }

            return nil
        })
    }
}
