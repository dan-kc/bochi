import Foundation

enum EntityFormKind: String, CaseIterable, Identifiable, Sendable {
    case task
    case recurringTask
    case reward

    static var allCases: [EntityFormKind] { [.task, .reward] }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: "Task"
        case .recurringTask: "Recurring Task"
        case .reward: "Reward"
        }
    }

    var tab: AppTab {
        switch self {
        case .task, .recurringTask: .earn
        case .reward: .spend
        }
    }
}

enum EntityFormSwitcherLayout: String, Sendable {
    case compactLabel
    case segmentedControl
}

struct NewEntitySharedDraft {
    let name: String
    let description: String
    let tagIDs: [RecordID]
}

struct NewTaskDraft {
    let basePrice: Int?
    let dueDate: Date?
    let timerSelection: EntityTimerSelection
    let reminderDrafts: [ReminderDraft]
    let taskId: RecordID
    let taskDependencies: [TaskTaskDependency]
    let recurringTaskDependencies: [TaskRecurringTaskDependency]
}

struct NewRecurringTaskDraft {
    let frequency: Double?
    let lockoutDurationSeconds: Int?
    let basePrice: Int?
    let timerSelection: EntityTimerSelection
    let reminderDrafts: [ReminderDraft]
    let recurringTaskId: RecordID
}

struct NewRewardDraft {
    let recurring: Bool
    let maxFrequency: Double?
    let lockoutDurationSeconds: Int?
    let basePrice: Int?
    let timerSelection: EntityTimerSelection
    let rewardId: RecordID
    let taskDependencies: [RewardTaskDependency]
    let recurringTaskDependencies: [RewardRecurringTaskDependency]
}

struct NewEntityFormSnapshot {
    let selectedEntity: EntityFormKind
    let shared: NewEntitySharedDraft
    let task: NewTaskDraft
    let recurringTask: NewRecurringTaskDraft
    let reward: NewRewardDraft
}

enum EntityFormSwitcherSupport {
    static func layout(hasEntitySelection: Bool) -> EntityFormSwitcherLayout {
        hasEntitySelection ? .segmentedControl : .compactLabel
    }

    static func makeInitialSnapshot(selectedEntity: EntityFormKind) -> NewEntityFormSnapshot {
        NewEntityFormSnapshot(
            selectedEntity: selectedEntity,
            shared: NewEntitySharedDraft(name: "", description: "", tagIDs: []),
            task: NewTaskDraft(
                basePrice: nil,
                dueDate: nil,
                timerSelection: .none,
                reminderDrafts: [],
                taskId: RecordID(),
                taskDependencies: [],
                recurringTaskDependencies: []
            ),
            recurringTask: NewRecurringTaskDraft(
                frequency: nil,
                lockoutDurationSeconds: nil,
                basePrice: nil,
                timerSelection: .none,
                reminderDrafts: [],
                recurringTaskId: RecordID()
            ),
            reward: NewRewardDraft(
                recurring: true,
                maxFrequency: nil,
                lockoutDurationSeconds: nil,
                basePrice: nil,
                timerSelection: .none,
                rewardId: RecordID(),
                taskDependencies: [],
                recurringTaskDependencies: []
            )
        )
    }

    static func taskSnapshot(from snapshot: NewEntityFormSnapshot) -> TaskFormSnapshot {
        TaskFormSnapshot(
            name: snapshot.shared.name,
            description: snapshot.shared.description,
            basePrice: snapshot.task.basePrice ?? 200,
            dueDate: snapshot.task.dueDate,
            timerSelection: snapshot.task.timerSelection,
            reminderDrafts: snapshot.task.reminderDrafts,
            taskId: snapshot.task.taskId,
            tagIDs: snapshot.shared.tagIDs,
            taskDependencies: snapshot.task.taskDependencies,
            recurringTaskDependencies: snapshot.task.recurringTaskDependencies
        )
    }

    static func recurringTaskSnapshot(from snapshot: NewEntityFormSnapshot) -> RecurringTaskFormSnapshot {
        RecurringTaskFormSnapshot(
            name: snapshot.shared.name,
            description: snapshot.shared.description,
            frequency: snapshot.recurringTask.frequency,
            lockoutDurationSeconds: snapshot.recurringTask.lockoutDurationSeconds,
            basePrice: snapshot.recurringTask.basePrice ?? 100,
            timerSelection: snapshot.recurringTask.timerSelection,
            reminderDrafts: snapshot.recurringTask.reminderDrafts,
            recurringTaskId: snapshot.recurringTask.recurringTaskId,
            tagIDs: snapshot.shared.tagIDs
        )
    }

    static func rewardSnapshot(from snapshot: NewEntityFormSnapshot) -> RewardFormSnapshot {
        RewardFormSnapshot(
            name: snapshot.shared.name,
            description: snapshot.shared.description,
            recurring: snapshot.reward.recurring,
            maxFrequency: snapshot.reward.maxFrequency,
            lockoutDurationSeconds: snapshot.reward.lockoutDurationSeconds,
            basePrice: snapshot.reward.basePrice ?? 500,
            timerSelection: snapshot.reward.timerSelection,
            rewardId: snapshot.reward.rewardId,
            tagIDs: snapshot.shared.tagIDs,
            taskDependencies: snapshot.reward.taskDependencies,
            recurringTaskDependencies: snapshot.reward.recurringTaskDependencies
        )
    }

    static func hasRecoverableContent(_ snapshot: NewEntityFormSnapshot) -> Bool {
        !EntityFormSupport.trimmedName(snapshot.shared.name).isEmpty
            || !snapshot.shared.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !snapshot.shared.tagIDs.isEmpty
            || snapshot.task.basePrice != nil
            || snapshot.recurringTask.basePrice != nil
            || snapshot.reward.basePrice != nil
            || snapshot.task.dueDate != nil
            || snapshot.task.timerSelection != .none
            || !snapshot.task.reminderDrafts.isEmpty
            || !snapshot.task.taskDependencies.isEmpty
            || !snapshot.task.recurringTaskDependencies.isEmpty
            || snapshot.recurringTask.frequency != nil
            || snapshot.recurringTask.lockoutDurationSeconds != nil
            || snapshot.recurringTask.timerSelection != .none
            || !snapshot.recurringTask.reminderDrafts.isEmpty
            || snapshot.reward.maxFrequency != nil
            || snapshot.reward.lockoutDurationSeconds != nil
            || snapshot.reward.timerSelection != .none
            || !snapshot.reward.taskDependencies.isEmpty
            || !snapshot.reward.recurringTaskDependencies.isEmpty
    }
}
