import SwiftUI

enum RewardFormMode: Equatable {
    case new
    case change(Reward)

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }

    var reward: Reward? {
        if case .change(let reward) = self { return reward }
        return nil
    }
}

enum RewardFormFocus: Equatable {
    case maxFrequency
    case price
    case lockout
    case tags
}

private enum RewardDependencyEditorRoute: Identifiable {
    case task(TaskItem)
    case recurringTask(RecurringTask)

    var id: String {
        switch self {
        case .task(let task):
            return "task:\(task.id.rawValue)"
        case .recurringTask(let recurringTask):
            return "recurringTask:\(recurringTask.id.rawValue)"
        }
    }
}

private enum RewardFormActionState: Equatable {
    case buy(amount: Int)
    case refund(amount: Int)
    case locked
}

struct RewardFormSnapshot {
    let name: String
    let description: String
    var recurring: Bool = true
    let maxFrequency: Double?
    let lockoutDurationSeconds: Int?
    let basePrice: Int
    var timerSelection: EntityTimerSelection = .none
    let rewardId: RecordID
    let tagIDs: [RecordID]
    var taskDependencies: [RewardTaskDependency] = []
    var recurringTaskDependencies: [RewardRecurringTaskDependency] = []
}

struct RewardFormView: View {
    let mode: RewardFormMode
    let initialFocus: RewardFormFocus?
    let prefill: RewardFormSnapshot?
    let onCreated: ((Reward) -> Void)?
    let onDiscard: ((RewardFormSnapshot) -> Void)?
    let onDelete: ((Reward) -> Void)?
    let onDuplicate: ((Reward) -> Void)?

    @Environment(\.bochiTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(RewardStore.self) private var rewardStore
    @Environment(TimerStore.self) private var timerStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @State private var draft = RewardFormDraft()

    @State private var showingFrequency = false
    @State private var showingPrice = false
    @State private var showingLockout = false
    @State private var showingTags = false
    @State private var showingTimer = false
    @State private var showingDependencyPicker = false
    @State private var purchasingRewardRoute: RewardPurchaseRoute? = nil
    @State private var showingHistory = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBlockedTaskAlert = false
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var refunded = false
    @State private var actionWarningReason: EntityActionGateReason? = nil
    @State private var dependencyEditorRoute: RewardDependencyEditorRoute? = nil
    @State private var dependencyTradeRecurringTaskRoute: RecurringTaskTradeRoute? = nil

    @State private var hasInitialized = false
    @State private var hasAppliedInitialLoad = false
    @State private var didPersist = false
    @FocusState private var focusedField: FieldFocus?

    enum FieldFocus: Hashable {
        case name
        case description
    }

    init(
        mode: RewardFormMode = .new,
        initialFocus: RewardFormFocus? = nil,
        prefill: RewardFormSnapshot? = nil,
        onCreated: ((Reward) -> Void)? = nil,
        onDiscard: ((RewardFormSnapshot) -> Void)? = nil,
        onDelete: ((Reward) -> Void)? = nil,
        onDuplicate: ((Reward) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onCreated = onCreated
        self.onDiscard = onDiscard
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
    }

    private var rewardTags: [Tag] {
        tagStore.tagsForReward(rewardId: rewardID)
    }

    private var rewardTagIDs: [RecordID] {
        rewardTags
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
    }

    private var timerPillLabel: String {
        switch timerSelection {
        case .none, .duration:
            return "Timer"
        case .named(let timerID):
            return timerStore.timer(id: timerID)?.name ?? "Timer"
        }
    }

    private var trimmedName: String {
        draft.trimmedName
    }

    private var isNewMode: Bool {
        mode.isNew
    }

    private var rewardID: RecordID {
        draft.rewardID
    }

    private var recurring: Bool {
        draft.recurring
    }

    private var basePrice: Int {
        draft.basePrice
    }

    private var lockoutDurationSeconds: Int? {
        draft.lockoutDurationSeconds
    }

    private var timerSelection: EntityTimerSelection {
        draft.timerSelection
    }

    private var effectiveMaxFrequency: Double? {
        draft.effectiveMaxFrequency
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: draft.description,
            maxFrequency: effectiveMaxFrequency,
            lockoutDurationSeconds: draft.lockoutDurationSeconds,
            basePrice: basePrice,
            tagCount: rewardTags.count,
            dependencyCount: activeDependencyCount,
            isFirstReward: false
        )
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    // The price preview follows the currently visible draft so the user sees
    // how changing max frequency or damage affects the cost before leaving.
    private var draftRewardForPurchase: Reward? {
        draft.rewardForPurchase(existingReward: currentReward ?? mode.reward)
    }

    private var isLocked: Bool {
        guard let reward = draftRewardForPurchase else { return false }
        return RewardLockout.isLocked(reward: reward, tradeStore: tradeStore, hasPremiumAccess: hasPremiumAccess)
            || rewardDependencyStore.isRewardBlocked(
                reward,
                taskStore: taskStore,
                tradeStore: tradeStore,
                hasPremiumAccess: hasPremiumAccess
            )
    }

    private var lockoutSummary: String? {
        guard let reward = draftRewardForPurchase else { return nil }
        guard let remainingSeconds = RewardLockout.remainingSeconds(
            reward: reward,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            return nil
        }
        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
    }

    private var actionGateReason: EntityActionGateReason? {
        EntityActionGateSupport.reason(
            isLocked: isLocked,
            lockoutSummary: lockoutSummary,
            isHidden: currentReward?.hidden ?? false
        )
    }

    private var currentPrice: Int {
        guard let reward = draftRewardForPurchase else { return 0 }
        let purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
        let allRewards = rewardStore.activeRewards.map { existing in
            existing.id == reward.id ? reward : existing
        }
        return RewardPriceCalculator.calculatePrice(
            reward: reward,
            allRewards: allRewards,
            purchaseDates: purchaseDates
        )
    }

    private var latestRewardPurchase: Trade? {
        tradeStore.latestRewardPurchase(rewardId: rewardID, includeRefunded: false)
    }

    private var rewardActionState: RewardFormActionState {
        if !isNewMode, !recurring, let latestRewardPurchase {
            return .refund(amount: abs(latestRewardPurchase.amount))
        }

        if isLocked {
            return .locked
        }

        return .buy(amount: currentPrice)
    }

    private var lastPurchasedAt: Date? {
        guard let reward = draftRewardForPurchase else { return nil }
        return tradeStore.rewardPurchaseDates(rewardId: reward.id).max()
    }

    private var activeDependencyCount: Int {
        activeTaskDependencies.count + activeRecurringTaskDependencies.count
    }

    private var activeTaskDependencies: [RewardTaskDependency] {
        draft.activeTaskDependencies
    }

    private var activeRecurringTaskDependencies: [RewardRecurringTaskDependency] {
        draft.activeRecurringTaskDependencies
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if refunded {
                    RefundFeedbackView {
                        refunded = false
                    }
                    .transition(.opacity)
                } else {
                    editorContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: refunded)
            .entityFormNavigation(
                title: refunded ? "" : (isNewMode ? "New Reward" : "Edit Reward"),
                isToolbarVisible: !refunded,
                isNewMode: isNewMode,
                isEditingText: isEditingText,
                canCommitNewEntity: !trimmedName.isEmpty,
                onCancel: { dismiss() },
                onFinishTextEditing: { focusedField = nil },
                onCommit: commitForm,
                menuContent: { editMenuContent }
            )
        }
        .entityFormPresentation(theme: theme, isEditingText: isEditingText)
        .sheet(isPresented: $showingFrequency) {
            RewardFrequencyModal(maxFrequency: $draft.maxFrequency)
        }
        .sheet(isPresented: $showingPrice) {
            BasePriceModalView(price: $draft.basePrice, helperSeed: 500.0)
        }
        .sheet(isPresented: $showingLockout) {
            RewardLockoutDurationModal(durationSeconds: $draft.lockoutDurationSeconds)
        }
        .sheet(isPresented: $showingTags) {
            TagsView(assignmentTarget: .reward(rewardID), shouldNotifySync: true)
        }
        .sheet(isPresented: $showingTimer) {
            TimerModalView(
                selection: $draft.timerSelection,
                durationSeconds: nil,
                allowsDurationTimer: false
            )
        }
        .sheet(isPresented: $showingDependencyPicker) {
            DependencyPickerView(
                selectedTaskDependencyIDs: Set(activeTaskDependencies.map(\.dependsOnTaskId)),
                selectedRecurringTaskDependencyIDs: Set(activeRecurringTaskDependencies.map(\.recurringTaskId)),
                onSave: { selectedTasks, selectedRecurringTasks in
                    selectedTasks.forEach(addTaskDependency)
                    selectedRecurringTasks.forEach { selection in
                        saveRecurringTaskDependency(
                            recurringTask: selection.0,
                            existingDependency: activeRecurringTaskDependencies.first(where: { $0.recurringTaskId == selection.0.id }),
                            requiredCompletions: selection.1
                        )
                    }
                }
            )
        }
        .sheet(item: $dependencyEditorRoute) { route in
            switch route {
            case .task(let task):
                TaskFormView(mode: .change(task))
            case .recurringTask(let recurringTask):
                RecurringTaskFormView(mode: .change(recurringTask))
            }
        }
        .sheet(item: $dependencyTradeRecurringTaskRoute) { route in
            TradeModalView(
                recurringTask: route.recurringTask,
                quote: route.quote
            )
        }
        .sheet(item: $purchasingRewardRoute) { route in
            RewardPurchaseModalView(
                reward: route.reward,
                quote: route.quote,
                allowsRestrictedPurchase: route.allowsRestrictedPurchase
            )
        }
        .sheet(item: $actionWarningReason) { reason in
            EntityActionWarningModalView(
                entityName: currentReward?.name ?? draftRewardForPurchase?.name ?? "Reward",
                actionTitle: "Buy Reward",
                reason: reason,
                onCancel: { actionWarningReason = nil },
                onConfirm: {
                    actionWarningReason = nil
                    openPurchaseModal(allowsRestrictedPurchase: true)
                }
            )
        }
        .sheet(isPresented: $showingHistory) {
            TradeHistorySheetView(
                filter: .reward(rewardID),
                detents: [.large]
            )
        }
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
        .entityDeleteConfirmation(
            entityName: "Reward",
            isPresented: $showingDeleteConfirmation,
            item: currentReward,
            onDelete: deleteReward
        )
        .blockedTaskDependencyAlert(isPresented: $showingBlockedTaskAlert)
        .entityFormLifecycle(
            changeToken: draft,
            initialize: initializeIfNeeded,
            autoSave: autoSaveIfNeeded,
            shouldDiscard: { isNewMode && !didPersist && hasContent },
            discard: discardDraft
        )
    }

    private var editorContent: some View {
        EntityFormEditorShell(
            isEditingText: isEditingText,
            valuePills: buildPricePills(),
            detailPills: buildNonPricePills(),
            tags: rewardTags,
            activitySummary: lastPurchasedAt.map { RecentActivitySummary.text(prefix: "Last purchased", date: $0) },
            bottomSpacerHeight: 94,
            onTagsTapped: { showingTags = true },
            switcher: {
                EntityFormStaticTraitBadges(
                    entity: "reward",
                    cadence: recurring ? "recurring" : "one-time"
                )
            },
            textFields: { textFieldsSection },
            extraContent: {
                if activeDependencyCount > 0 {
                    if hasPremiumAccess {
                        dependenciesSection
                    }
                }
            },
            floatingControls: { floatingControls }
        )
    }

    @ViewBuilder
    private var editMenuContent: some View {
        if let reward = currentReward {
            EntityFormEditMenu(
                entityName: "Reward",
                onDuplicate: { duplicateReward(reward) },
                onToggleHidden: {
                    rewardStore.setHidden(id: reward.id, hidden: !reward.hidden)
                },
                isHidden: reward.hidden,
                onHistory: { showingHistory = true },
                onDelete: { showingDeleteConfirmation = true }
            )
        }
    }

    private var currentReward: Reward? {
        guard case .change(let reward) = mode else { return nil }
        return rewardStore.rewards.first(where: { $0.id == reward.id }) ?? reward
    }

    private var textFieldsSection: some View {
        EntityFormTextFieldsSection(
            name: $draft.name,
            description: $draft.description,
            focusedField: $focusedField,
            nameFocus: .name,
            descriptionFocus: .description
        )
    }

    private var floatingControls: some View {
        VStack(spacing: 10) {
            if isNewMode {
                EntityFormAddActionButton(
                    entityName: "Reward",
                    isEnabled: !trimmedName.isEmpty,
                    action: commitForm
                )
            } else {
                switch rewardActionState {
                case .buy, .locked:
                    purchaseButton
                case .refund(let amount):
                    rewardRefundButton(amount: amount)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var purchaseButton: some View {
        let gateReason = actionGateReason

        return BochiActionButton(
            amount: currentPrice,
            polarity: .spending,
            layout: .expanded(title: EntityActionGateSupport.actionTitle(defaultTitle: "Buy Reward", reason: gateReason)),
            usesMainThemeStyle: gateReason != nil,
            themeRoleOverride: .reward,
            priceDeltaPercent: PriceDeltaSupport.percent(currentPrice: currentPrice, basePrice: basePrice)
        ) {
            if let gateReason {
                actionWarningReason = gateReason
                return
            }

            openPurchaseModal(allowsRestrictedPurchase: false)
        }
    }

    private func openPurchaseModal(allowsRestrictedPurchase: Bool) {
        guard let persistedReward = persistReward() else { return }
        didPersist = true
        purchasingRewardRoute = RewardPurchaseRoute(
            reward: persistedReward,
            allowsRestrictedPurchase: allowsRestrictedPurchase
        )
    }

    private func rewardRefundButton(amount: Int) -> some View {
        BochiActionButton(
            amount: amount,
            polarity: .earning,
            layout: .expanded(title: "Refund"),
            showsPremiumBadge: !hasPremiumAccess,
            usesPremiumStyle: !hasPremiumAccess
        ) {
            refundPurchasedRewardFromForm()
        }
    }

    private func refundPurchasedRewardFromForm() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .refunds
            return
        }

        guard let trade = latestRewardPurchase else { return }

        let refundTrade = TradeRefundService.refund(
            for: trade,
            tradeStore: tradeStore,
            balanceStore: balanceStore
        )
        guard refundTrade != nil else { return }
        refunded = true
    }

    private var dependenciesSection: some View {
        DependencySectionView(
            taskDependencies: activeTaskDependencies,
            recurringTaskDependencies: activeRecurringTaskDependencies,
            onAdd: { showingDependencyPicker = true },
            task: { dependency in
                taskStore.tasks.first(where: { $0.id == dependency.dependsOnTaskId && $0.deletedAt == nil })
            },
            taskIsComplete: { task in
                tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) != nil
            },
            onOpenTask: { dependencyEditorRoute = .task($0) },
            onCompleteTask: completeDependencyTask,
            onRemoveTaskDependency: removeTaskDependency,
            recurringTask: { dependency in
                recurringTaskStore.recurringTasks.first(where: { $0.id == dependency.recurringTaskId && $0.deletedAt == nil })
            },
            recurringTaskProgress: { dependency in
                rewardDependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore)
            },
            recurringTaskRequiredCompletions: \.requiredCompletions,
            recurringTaskRequiredCompletionsBinding: recurringTaskDependencyCountBinding,
            onOpenRecurringTask: { dependencyEditorRoute = .recurringTask($0) },
            onClaimRecurringTask: openDependencyRecurringTaskClaim,
            onRemoveRecurringTaskDependency: removeRecurringTaskDependency
        )
    }

    static func hasContent(
        name: String,
        description: String,
        maxFrequency: Double?,
        lockoutDurationSeconds: Int?,
        basePrice: Int,
        tagCount: Int,
        dependencyCount: Int = 0,
        isFirstReward: Bool = false
    ) -> Bool {
        EntityFormSupport.hasRecoverableContent(
            name: name,
            description: description,
            primaryValueIsSet: maxFrequency != nil,
            secondaryValueIsSet: basePrice != 500 || lockoutDurationSeconds != nil,
            tagCount: tagCount + dependencyCount,
            ignoreSecondaryValue: isFirstReward
        )
    }

    static func nameForAutoSave(_ name: String) -> String {
        EntityFormSupport.trimmedName(name)
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        basePrice: Int,
        maxFrequency: Double?,
        lockoutDurationSeconds: Int?,
        dependencyCount: Int = 0,
        lockoutIsPremiumLocked: Bool = false
    ) -> [EntityFormPillConfig] {
        buildPricePillData(
            basePrice: basePrice,
            maxFrequency: maxFrequency
        ) + buildNonPricePillData(
            hasTagsApplied: hasTagsApplied,
            lockoutDurationSeconds: lockoutDurationSeconds,
            dependencyCount: dependencyCount,
            lockoutIsPremiumLocked: lockoutIsPremiumLocked
        )
    }

    static func buildPricePillData(
        basePrice: Int?,
        maxFrequency: Double?,
        priceRequiresAttention: Bool = false
    ) -> [EntityFormPillConfig] {
        let frequencyLabel = FrequencyConversion.formatSummary(maxFrequency).map { "Max \($0)" } ?? "Max Frequency"
        return [
            EntityFormPillConfig(
                id: "price",
                label: basePrice.map(String.init) ?? "Base Price",
                icon: "cube",
                isSet: basePrice != nil,
                requiresAttention: priceRequiresAttention
            ),
            EntityFormPillConfig(id: "frequency", label: frequencyLabel, icon: "clock", isSet: maxFrequency != nil)
        ]
    }

    static func buildNonPricePillData(
        hasTagsApplied: Bool,
        timerLabel: String = "Timer",
        hasTimer: Bool = false,
        lockoutDurationSeconds: Int?,
        dependencyCount: Int = 0,
        lockoutIsPremiumLocked: Bool = false,
        dependencyIsPremiumLocked: Bool = false,
        timerIsPremiumLocked: Bool = false
    ) -> [EntityFormPillConfig] {
        let lockoutLabel = DurationFormatting.summary(seconds: lockoutDurationSeconds) ?? "Lockout"
        return [
            EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            EntityFormPillConfig(
                id: "timer",
                label: timerLabel,
                icon: "stopwatch",
                isSet: hasTimer,
                isPremiumLocked: timerIsPremiumLocked
            ),
            EntityFormPillConfig(
                id: "lockout",
                label: lockoutLabel,
                icon: "lock",
                isSet: lockoutDurationSeconds != nil,
                isPremiumLocked: lockoutIsPremiumLocked
            ),
            EntityFormPillConfig(
                id: "dependencies",
                label: "Dependencies",
                icon: "lock.doc",
                isSet: dependencyCount > 0,
                isPremiumLocked: dependencyIsPremiumLocked
            )
        ]
    }

    private func buildPricePills() -> [PillItem] {
        let configs = Self.buildPricePillData(
            basePrice: basePrice,
            maxFrequency: effectiveMaxFrequency
        ).filter { recurring || $0.id != "frequency" }
        return EntityFormSupport.buildPills(
            configs: configs,
            actions: pillActions
        )
    }

    private func buildNonPricePills() -> [PillItem] {
        let configs = Self.buildNonPricePillData(
            hasTagsApplied: !rewardTags.isEmpty,
            timerLabel: timerPillLabel,
            hasTimer: timerSelection != .none && timerSelection != .duration,
            lockoutDurationSeconds: lockoutDurationSeconds,
            dependencyCount: activeDependencyCount,
            lockoutIsPremiumLocked: !hasPremiumAccess,
            dependencyIsPremiumLocked: !hasPremiumAccess,
            timerIsPremiumLocked: !hasPremiumAccess
        )
        return EntityFormSupport.buildPills(
            configs: configs,
            actions: pillActions
        )
    }

    private var pillActions: [String: () -> Void] {
        [
            "tags": { showingTags = true },
            "price": { showingPrice = true },
            "frequency": {
                guard recurring else { return }
                showingFrequency = true
            },
            "timer": { openTimerOrPremiumUpsell() },
            "lockout": { openLockoutOrPremiumUpsell() },
            "dependencies": { openDependencyPickerOrPremiumUpsell() },
        ]
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, mode.isNew {
            draft = RewardFormDraft(prefill: prefill)
        } else if case .change(let reward) = mode {
            draft = RewardFormDraft(
                reward: reward,
                taskDependencies: rewardDependencyStore.activeTaskDependencies(for: reward.id),
                recurringTaskDependencies: rewardDependencyStore.activeRecurringTaskDependencies(for: reward.id)
            )
        }

        hasAppliedInitialLoad = true

        guard let initialFocus else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch initialFocus {
            case .maxFrequency:
                showingFrequency = recurring
            case .price:
                showingPrice = true
            case .lockout:
                openLockoutOrPremiumUpsell()
            case .tags:
                showingTags = true
            }
        }
    }

    private func autoSaveIfNeeded() {
        guard !isNewMode, hasAppliedInitialLoad else { return }
        _ = persistReward()
    }

    private func commitForm() {
        if isNewMode {
            guard !trimmedName.isEmpty else { return }
            guard let reward = persistReward() else { return }
            didPersist = true
            onCreated?(reward)
        } else {
            didPersist = true
            _ = persistReward()
        }
        dismiss()
    }

    private func duplicateReward(_ reward: Reward) {
        dismiss()
        onDuplicate?(reward)
    }

    private func deleteReward(_ reward: Reward) {
        dismiss()
        if let onDelete {
            onDelete(reward)
            return
        }

        EntityDeletionService.deleteReward(
            reward,
            rewardDependencyStore: rewardDependencyStore,
            rewardStore: rewardStore
        )
    }

    private func discardDraft() {
        onDiscard?(draft.snapshot(tagIDs: rewardTagIDs))
    }

    @discardableResult
    private func persistReward() -> Reward? {
        if case .new = mode {
            let reward = rewardStore.addReward(
                id: draft.rewardID,
                recurring: draft.recurring,
                name: draft.name,
                description: draft.description,
                maxFrequency: draft.effectiveMaxFrequency,
                lockoutDurationSeconds: draft.lockoutDurationSeconds,
                basePrice: draft.basePrice,
                timerSelection: draft.persistedTimerSelection
            )
            persistDependenciesIfPossible()
            return reward
        }

        rewardStore.updateReward(
            id: draft.rewardID,
            name: Self.nameForAutoSave(draft.name),
            description: draft.description,
            maxFrequency: .some(draft.effectiveMaxFrequency),
            lockoutDurationSeconds: .some(draft.lockoutDurationSeconds),
            basePrice: draft.basePrice,
            timerSelection: draft.persistedTimerSelection
        )
        persistDependenciesIfPossible()

        return draftRewardForPurchase
    }

    private func persistDependenciesIfPossible() {
        guard hasAppliedInitialLoad || isNewMode else { return }
        rewardDependencyStore.replaceDependencies(
            for: draft.rewardID,
            taskDependencies: draft.taskDependencies,
            recurringTaskDependencies: draft.recurringTaskDependencies
        )
    }

    private func completeDependencyTask(_ task: TaskItem) {
        let didComplete = DependencyActionSupport.completeTaskDependency(
            task,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            hasPremiumAccess: hasPremiumAccess
        )
        guard didComplete else {
            showingBlockedTaskAlert = true
            return
        }
    }

    private func openDependencyRecurringTaskClaim(_ recurringTask: RecurringTask) {
        dependencyTradeRecurringTaskRoute = DependencyActionSupport.recurringTaskClaimRoute(
            for: recurringTask,
            tradeStore: tradeStore
        )
    }

    private func addTaskDependency(_ selectedTask: TaskItem) {
        DependencyDraftSupport.addTaskDependency(
            to: &draft.taskDependencies,
            rewardID: rewardID,
            selectedTask: selectedTask
        )
    }

    private func saveRecurringTaskDependency(
        recurringTask: RecurringTask,
        existingDependency: RewardRecurringTaskDependency?,
        requiredCompletions: Int
    ) {
        DependencyDraftSupport.saveRecurringTaskDependency(
            to: &draft.recurringTaskDependencies,
            rewardID: rewardID,
            recurringTask: recurringTask,
            existingDependency: existingDependency,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: tradeStore.recurringTaskCompletionCount(recurringTaskId: recurringTask.id)
        )
    }

    private func recurringTaskDependencyCountBinding(_ dependency: RewardRecurringTaskDependency, recurringTask: RecurringTask) -> Binding<Int> {
        DependencyDraftSupport.recurringTaskDependencyCountBinding(
            dependency: dependency,
            recurringTask: recurringTask,
            requiredCompletions: \.requiredCompletions,
            save: { recurringTask, dependency, requiredCompletions in
                saveRecurringTaskDependency(
                    recurringTask: recurringTask,
                    existingDependency: dependency,
                    requiredCompletions: requiredCompletions
                )
            }
        )
    }

    private func removeTaskDependency(_ dependency: RewardTaskDependency) {
        DependencyDraftSupport.remove(dependency, from: &draft.taskDependencies)
    }

    private func removeRecurringTaskDependency(_ dependency: RewardRecurringTaskDependency) {
        DependencyDraftSupport.remove(dependency, from: &draft.recurringTaskDependencies)
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    private func openDependencyPickerOrPremiumUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .dependencies
            return
        }

        showingDependencyPicker = true
    }

    private func openLockoutOrPremiumUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .lockouts
            return
        }

        showingLockout = true
    }

    private func openTimerOrPremiumUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .timers
            return
        }

        showingTimer = true
    }
}
