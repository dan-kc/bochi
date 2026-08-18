import Foundation

enum TaskFormPersistenceSupport {
    @MainActor
    static func persistTask(
        task: TaskItem?,
        taskID: RecordID,
        name: String,
        description: String,
        basePrice: Int,
        dueDate: Date?,
        timerSelection: EntityTimerSelection = .none,
        reminderDrafts: [ReminderDraft],
        taskDependencies: [TaskTaskDependency],
        recurringTaskDependencies: [TaskRecurringTaskDependency],
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
                basePrice: basePrice,
                dueDate: dueDate,
                timerSelection: timerSelection
            ) else {
                return nil
            }
            persistedTask = createdTask
        } else {
            taskStore.updateTask(
                id: taskID,
                name: name,
                description: description,
                basePrice: basePrice,
                dueDate: .some(dueDate),
                timerSelection: timerSelection
            )
            guard let updatedTask = taskStore.tasks.first(where: { $0.id == taskID }) else {
                return nil
            }
            persistedTask = updatedTask
        }

        taskDependencyStore.replaceDependencies(
            for: taskID,
            taskDependencies: taskDependencies,
            recurringTaskDependencies: recurringTaskDependencies
        )
        reminderStore.replaceReminders(for: .task(taskID), with: reminderDrafts)
        return persistedTask
    }
}
