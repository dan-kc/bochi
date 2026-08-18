import Foundation

struct RewardFormDraft: Equatable {
    var rewardID = RecordID()
    var name = ""
    var description = ""
    var recurring = true
    var maxFrequency: Double? = nil
    var lockoutDurationSeconds: Int? = nil
    var basePrice = 500
    var timerSelection: EntityTimerSelection = .none
    var taskDependencies: [RewardTaskDependency] = []
    var recurringTaskDependencies: [RewardRecurringTaskDependency] = []

    var trimmedName: String {
        EntityFormSupport.trimmedName(name)
    }

    var effectiveMaxFrequency: Double? {
        recurring ? maxFrequency : nil
    }

    var persistedTimerSelection: EntityTimerSelection {
        timerSelection == .duration ? .none : timerSelection
    }

    var activeTaskDependencies: [RewardTaskDependency] {
        taskDependencies.filter { $0.deletedAt == nil }
    }

    var activeRecurringTaskDependencies: [RewardRecurringTaskDependency] {
        recurringTaskDependencies.filter { $0.deletedAt == nil }
    }

    init() {}

    init(prefill: RewardFormSnapshot) {
        rewardID = prefill.rewardId
        name = prefill.name
        description = prefill.description
        recurring = prefill.recurring
        maxFrequency = prefill.recurring ? prefill.maxFrequency : nil
        lockoutDurationSeconds = prefill.lockoutDurationSeconds
        basePrice = prefill.basePrice
        timerSelection = prefill.timerSelection
        taskDependencies = prefill.taskDependencies
        recurringTaskDependencies = prefill.recurringTaskDependencies
    }

    init(
        reward: Reward,
        taskDependencies: [RewardTaskDependency],
        recurringTaskDependencies: [RewardRecurringTaskDependency]
    ) {
        rewardID = reward.id
        name = reward.name
        description = reward.description
        recurring = reward.recurring
        maxFrequency = reward.recurring ? reward.maxFrequency : nil
        lockoutDurationSeconds = reward.lockoutDurationSeconds
        basePrice = reward.basePrice
        timerSelection = reward.timerSelection
        self.taskDependencies = taskDependencies
        self.recurringTaskDependencies = recurringTaskDependencies
    }

    func rewardForPurchase(existingReward: Reward?) -> Reward? {
        guard let existingReward else { return nil }

        let autoSavedName = EntityFormSupport.trimmedName(name)
        return Reward(
            id: existingReward.id,
            recurring: recurring,
            name: autoSavedName.isEmpty ? existingReward.name : autoSavedName,
            description: description,
            createdAt: existingReward.createdAt,
            updatedAt: Date(),
            deletedAt: existingReward.deletedAt,
            maxFrequency: effectiveMaxFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: existingReward.pinned,
            hidden: existingReward.hidden,
            timerSelection: persistedTimerSelection,
            serverRevision: existingReward.serverRevision
        )
    }

    func snapshot(tagIDs: [RecordID]) -> RewardFormSnapshot {
        RewardFormSnapshot(
            name: name,
            description: description,
            recurring: recurring,
            maxFrequency: effectiveMaxFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            timerSelection: timerSelection,
            rewardId: rewardID,
            tagIDs: tagIDs,
            taskDependencies: taskDependencies,
            recurringTaskDependencies: recurringTaskDependencies
        )
    }
}
