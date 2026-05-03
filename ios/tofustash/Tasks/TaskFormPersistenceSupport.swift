import Foundation

enum TaskFormPersistenceSupport {
    @MainActor
    static func persistTask(
        task: TaskItem?,
        taskID: RecordID,
        name: String,
        description: String,
        difficultyTier: HabitDifficultyTier?,
        durationSeconds: Int?,
        commitment: Int?,
        dueDate: Date?,
        completedAt: Date?,
        reminderDrafts: [ReminderDraft],
        taskDependencies: [TaskTaskDependency],
        habitDependencies: [TaskHabitDependency],
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        reminderStore: ReminderStore
    ) -> TaskItem? {
        let persistedTask: TaskItem

        if task == nil {
            guard let createdTask = taskStore.addTask(
                id: taskID,
                name: name,
                description: description,
                difficultyTier: difficultyTier,
                durationSeconds: durationSeconds,
                commitment: commitment,
                dueDate: dueDate,
                completedAt: completedAt
            ) else {
                return nil
            }
            persistedTask = createdTask
        } else {
            taskStore.updateTask(
                id: taskID,
                name: name,
                description: description,
                difficultyTier: .some(difficultyTier),
                durationSeconds: .some(durationSeconds),
                commitment: .some(commitment),
                dueDate: .some(dueDate),
                completedAt: .some(completedAt)
            )
            guard let updatedTask = taskStore.tasks.first(where: { $0.id == taskID }) else {
                return nil
            }
            persistedTask = updatedTask
        }

        taskDependencyStore.replaceDependencies(
            for: taskID,
            taskDependencies: taskDependencies,
            habitDependencies: habitDependencies
        )
        reminderStore.replaceReminders(for: .task(taskID), with: reminderDrafts)
        return persistedTask
    }
}
