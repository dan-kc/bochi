import Foundation

enum EntityDuplicateSupport {
    static func snapshot(
        duplicating task: TaskItem,
        tagIDs: [RecordID],
        reminderDrafts: [ReminderDraft],
        taskDependencies: [TaskTaskDependency],
        recurringTaskDependencies: [TaskRecurringTaskDependency],
        newID: RecordID = RecordID()
    ) -> NewEntityFormSnapshot {
        let activeTaskDependencies = taskDependencies
            .filter { $0.deletedAt == nil }
            .map {
                TaskTaskDependency(
                    taskId: newID,
                    dependsOnTaskId: $0.dependsOnTaskId,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    deletedAt: nil
                )
            }
        let activeRecurringTaskDependencies = recurringTaskDependencies
            .filter { $0.deletedAt == nil }
            .map {
                TaskRecurringTaskDependency(
                    taskId: newID,
                    recurringTaskId: $0.recurringTaskId,
                    requiredCompletions: $0.requiredCompletions,
                    baselineCompletionCount: $0.baselineCompletionCount,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    deletedAt: nil
                )
            }

        var snapshot = EntityFormSwitcherSupport.makeInitialSnapshot(selectedEntity: .task)
        snapshot = NewEntityFormSnapshot(
            selectedEntity: .task,
            shared: NewEntitySharedDraft(name: task.name, description: task.description, tagIDs: tagIDs),
            task: NewTaskDraft(
                basePrice: task.basePrice,
                dueDate: task.dueDate,
                timerSelection: task.timerSelection,
                reminderDrafts: reminderDrafts,
                taskId: newID,
                taskDependencies: activeTaskDependencies,
                recurringTaskDependencies: activeRecurringTaskDependencies
            ),
            recurringTask: snapshot.recurringTask,
            reward: snapshot.reward
        )
        return snapshot
    }

    static func snapshot(
        duplicating recurringTask: RecurringTask,
        tagIDs: [RecordID],
        reminderDrafts: [ReminderDraft],
        newID: RecordID = RecordID()
    ) -> NewEntityFormSnapshot {
        let snapshot = EntityFormSwitcherSupport.makeInitialSnapshot(selectedEntity: .recurringTask)
        return NewEntityFormSnapshot(
            selectedEntity: .recurringTask,
            shared: NewEntitySharedDraft(name: recurringTask.name, description: recurringTask.description, tagIDs: tagIDs),
            task: snapshot.task,
            recurringTask: NewRecurringTaskDraft(
                frequency: recurringTask.frequency,
                lockoutDurationSeconds: recurringTask.lockoutDurationSeconds,
                basePrice: recurringTask.basePrice,
                timerSelection: recurringTask.timerSelection,
                reminderDrafts: reminderDrafts,
                recurringTaskId: newID
            ),
            reward: snapshot.reward
        )
    }

    static func snapshot(
        duplicating reward: Reward,
        tagIDs: [RecordID],
        newID: RecordID = RecordID()
    ) -> NewEntityFormSnapshot {
        let snapshot = EntityFormSwitcherSupport.makeInitialSnapshot(selectedEntity: .reward)
        return NewEntityFormSnapshot(
            selectedEntity: .reward,
            shared: NewEntitySharedDraft(name: reward.name, description: reward.description, tagIDs: tagIDs),
            task: snapshot.task,
            recurringTask: snapshot.recurringTask,
            reward: NewRewardDraft(
                recurring: reward.recurring,
                maxFrequency: reward.maxFrequency,
                lockoutDurationSeconds: reward.lockoutDurationSeconds,
                basePrice: reward.basePrice,
                timerSelection: reward.timerSelection,
                rewardId: newID,
                taskDependencies: [],
                recurringTaskDependencies: []
            )
        )
    }
}
