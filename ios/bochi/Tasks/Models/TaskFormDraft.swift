import Foundation

struct TaskFormDraft: Equatable {
    var taskID = RecordID()
    var name = ""
    var description = ""
    var basePrice = 200
    var dueDate: Date? = nil
    var timerSelection: EntityTimerSelection = .none
    var reminderDrafts: [ReminderDraft] = []
    var taskDependencies: [TaskTaskDependency] = []
    var recurringTaskDependencies: [TaskRecurringTaskDependency] = []

    var trimmedName: String {
        EntityFormSupport.trimmedName(name)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var activeTaskDependencies: [TaskTaskDependency] {
        taskDependencies.filter { $0.deletedAt == nil }
    }

    var activeRecurringTaskDependencies: [TaskRecurringTaskDependency] {
        recurringTaskDependencies.filter { $0.deletedAt == nil }
    }

    init() {}

    init(prefill: TaskFormSnapshot) {
        taskID = prefill.taskId
        name = prefill.name
        description = prefill.description
        basePrice = prefill.basePrice
        dueDate = prefill.dueDate
        timerSelection = prefill.timerSelection
        reminderDrafts = prefill.reminderDrafts
        taskDependencies = prefill.taskDependencies
        recurringTaskDependencies = prefill.recurringTaskDependencies
    }

    init(
        task: TaskItem,
        reminderDrafts: [ReminderDraft],
        taskDependencies: [TaskTaskDependency],
        recurringTaskDependencies: [TaskRecurringTaskDependency]
    ) {
        taskID = task.id
        name = task.name
        description = task.description
        basePrice = task.basePrice
        dueDate = task.dueDate
        timerSelection = task.timerSelection
        self.reminderDrafts = reminderDrafts
        self.taskDependencies = taskDependencies
        self.recurringTaskDependencies = recurringTaskDependencies
    }

    func activeReminderDrafts(now: Date) -> [ReminderDraft] {
        ReminderDraftSupport.active(reminderDrafts, now: now)
    }

    func task(existingTask: TaskItem?, now: Date = Date()) -> TaskItem {
        let persistedName = trimmedName.isEmpty ? (existingTask?.name ?? "Task") : trimmedName

        return TaskItem(
            id: taskID,
            name: persistedName,
            description: description,
            createdAt: existingTask?.createdAt ?? now,
            updatedAt: now,
            deletedAt: existingTask?.deletedAt,
            basePrice: basePrice,
            dueDate: dueDate,
            pinned: existingTask?.pinned ?? false,
            hidden: existingTask?.hidden ?? false,
            timerSelection: timerSelection,
            serverRevision: existingTask?.serverRevision
        )
    }

    func snapshot(tagIDs: [RecordID]) -> TaskFormSnapshot {
        TaskFormSnapshot(
            name: name,
            description: description,
            basePrice: basePrice,
            dueDate: dueDate,
            timerSelection: timerSelection,
            reminderDrafts: reminderDrafts,
            taskId: taskID,
            tagIDs: tagIDs,
            taskDependencies: taskDependencies,
            recurringTaskDependencies: recurringTaskDependencies
        )
    }
}
