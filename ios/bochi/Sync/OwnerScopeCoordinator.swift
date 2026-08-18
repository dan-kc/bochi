import Foundation

// Sync flow: switches every owner-scoped store between the signed-out local
// namespace and the signed-in account after auth, migration, or response apply.
@MainActor
struct OwnerScopeCoordinator {
    private let timerStore: TimerStore
    private let taskStore: TaskStore
    private let taskDependencyStore: TaskDependencyStore
    private let rewardDependencyStore: RewardDependencyStore
    private let recurringTaskStore: RecurringTaskStore
    private let rewardStore: RewardStore
    private let tradeStore: TradeStore
    private let tagStore: TagStore
    private let balanceStore: BalanceStore
    private let userSettingsStore: UserSettingsStore
    private let reminderStore: ReminderStore
    private let listPreferencesStore: ListPreferencesStore

    init(
        timerStore: TimerStore,
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        rewardDependencyStore: RewardDependencyStore,
        recurringTaskStore: RecurringTaskStore,
        rewardStore: RewardStore,
        tradeStore: TradeStore,
        tagStore: TagStore,
        balanceStore: BalanceStore,
        userSettingsStore: UserSettingsStore,
        reminderStore: ReminderStore,
        listPreferencesStore: ListPreferencesStore
    ) {
        self.timerStore = timerStore
        self.taskStore = taskStore
        self.taskDependencyStore = taskDependencyStore
        self.rewardDependencyStore = rewardDependencyStore
        self.recurringTaskStore = recurringTaskStore
        self.rewardStore = rewardStore
        self.tradeStore = tradeStore
        self.tagStore = tagStore
        self.balanceStore = balanceStore
        self.userSettingsStore = userSettingsStore
        self.reminderStore = reminderStore
        self.listPreferencesStore = listPreferencesStore
    }

    func setCurrentOwner(_ ownerID: String) {
        timerStore.setCurrentOwner(ownerID)
        taskStore.setCurrentOwner(ownerID)
        taskDependencyStore.setCurrentOwner(ownerID)
        rewardDependencyStore.setCurrentOwner(ownerID)
        recurringTaskStore.setCurrentOwner(ownerID)
        rewardStore.setCurrentOwner(ownerID)
        tradeStore.setCurrentOwner(ownerID)
        tagStore.setCurrentOwner(ownerID)
        balanceStore.setCurrentOwner(ownerID)
        userSettingsStore.setCurrentOwner(ownerID)
        reminderStore.setCurrentOwner(ownerID)
        listPreferencesStore.setCurrentOwner(ownerID)
        sanitizeListPreferencesForCurrentOwner()
    }

    func sanitizeListPreferencesForCurrentOwner() {
        // User behaviour: when account switching, sync, or local migration changes
        // which tags exist for the current owner, saved filter chips for deleted
        // tags should disappear instead of silently hiding all rows.
        listPreferencesStore.sanitizeSelectedTags(
            validTaskTagIDs: tagStore.activeTagIDs,
            validRecurringTaskTagIDs: tagStore.activeTagIDs,
            validRewardTagIDs: tagStore.activeTagIDs
        )
    }
}
