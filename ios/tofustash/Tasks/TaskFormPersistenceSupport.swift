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
        skipConsequence: Int?,
        dueDate: Date?,
        completedAt: Date?,
        reminderDrafts: [ReminderDraft],
        taskStore: TaskStore,
        reminderStore: ReminderStore
    ) -> Bool {
        if task == nil {
            guard taskStore.addTask(
                id: taskID,
                name: name,
                description: description,
                difficultyTier: difficultyTier,
                durationSeconds: durationSeconds,
                skipConsequence: skipConsequence,
                dueDate: dueDate,
                completedAt: completedAt
            ) != nil else {
                return false
            }
        } else {
            taskStore.updateTask(
                id: taskID,
                name: name,
                description: description,
                difficultyTier: .some(difficultyTier),
                durationSeconds: .some(durationSeconds),
                skipConsequence: .some(skipConsequence),
                dueDate: .some(dueDate),
                completedAt: .some(completedAt)
            )
        }

        if completedAt != nil {
            reminderStore.deleteAllReminders(for: .task(taskID))
        } else {
            reminderStore.replaceReminders(for: .task(taskID), with: reminderDrafts)
        }
        return true
    }
}
