import SwiftUI

enum TaskFormMode: Equatable {
    case new
    case change(TaskItem)

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }

    var task: TaskItem? {
        if case .change(let task) = self { return task }
        return nil
    }
}

enum TaskFormFocus: Equatable {
    case price
    case dueDate
    case reminders
    case tags
}

struct TaskFormSnapshot {
    let name: String
    let description: String
    let basePrice: Int
    let dueDate: Date?
    var timerSelection: EntityTimerSelection = .none
    let reminderDrafts: [ReminderDraft]
    let taskId: RecordID
    let tagIDs: [RecordID]
    let taskDependencies: [TaskTaskDependency]
    let recurringTaskDependencies: [TaskRecurringTaskDependency]
}

private enum TaskDependencyEditorRoute: Identifiable {
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

struct TaskFormView: View {
    let mode: TaskFormMode
    let initialFocus: TaskFormFocus?
    let prefill: TaskFormSnapshot?
    let onCreated: ((TaskItem) -> Void)?
    let onDiscard: ((TaskFormSnapshot) -> Void)?
    let onDelete: ((TaskItem) -> Void)?
    let onDuplicate: ((TaskItem) -> Void)?

    @Environment(\.bochiTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(TimerStore.self) private var timerStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @State private var draft = TaskFormDraft()

    @State private var showingTags = false
    @State private var showingReminders = false
    @State private var showingPrice = false
    @State private var showingDueDate = false
    @State private var showingTimer = false
    @State private var showingDependencyPicker = false
    @State private var showingHistory = false
    @State private var showingDeleteConfirmation = false
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var showingBlockedTaskAlert = false
    @State private var actionWarningReason: EntityActionGateReason? = nil
    @State private var claimRoute: TaskClaimRoute? = nil
    @State private var refunded = false
    @State private var dependencyEditorRoute: TaskDependencyEditorRoute? = nil
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
        mode: TaskFormMode = .new,
        initialFocus: TaskFormFocus? = nil,
        prefill: TaskFormSnapshot? = nil,
        onCreated: ((TaskItem) -> Void)? = nil,
        onDiscard: ((TaskFormSnapshot) -> Void)? = nil,
        onDelete: ((TaskItem) -> Void)? = nil,
        onDuplicate: ((TaskItem) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onCreated = onCreated
        self.onDiscard = onDiscard
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
    }

    private var isNewMode: Bool {
        mode.isNew
    }

    private var isCompleted: Bool {
        completionDate != nil
    }

    private var completionDate: Date? {
        latestTaskTrade?.createdAt
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    private var taskID: RecordID {
        draft.taskID
    }

    private var basePrice: Int {
        draft.basePrice
    }

    private var dueDate: Date? {
        draft.dueDate
    }

    private var timerSelection: EntityTimerSelection {
        draft.timerSelection
    }

    private var reminderDrafts: [ReminderDraft] {
        draft.reminderDrafts
    }

    private var taskTags: [Tag] {
        tagStore.tagsForTask(taskId: taskID)
    }

    private var taskTagIDs: [RecordID] {
        taskTags
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
    }

    private var resolvedTimerSelection: EntityTimerSelection { timerSelection }

    private var timerPillLabel: String {
        switch resolvedTimerSelection {
        case .none:
            return "Timer"
        case .duration:
            return "Duration"
        case .named(let timerID):
            return timerStore.timer(id: timerID)?.name ?? "Timer"
        }
    }

    private var activeReminderDrafts: [ReminderDraft] {
        draft.activeReminderDrafts(now: reminderStore.referenceDate)
    }

    private var trimmedName: String {
        draft.trimmedName
    }

    private var trimmedDescription: String {
        draft.trimmedDescription
    }

    private var draftTask: TaskItem {
        draft.task(existingTask: mode.task)
    }

    private var pricePreview: Int {
        TaskPriceCalculator.calculatePrice(
            task: draftTask
        )
    }

    private var activeTaskDependencies: [TaskTaskDependency] {
        draft.activeTaskDependencies
    }

    private var activeRecurringTaskDependencies: [TaskRecurringTaskDependency] {
        draft.activeRecurringTaskDependencies
    }

    private var isBlocked: Bool {
        taskDependencyStore.isTaskBlocked(
            draftTask,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    private var actionGateReason: EntityActionGateReason? {
        EntityActionGateSupport.reason(
            isLocked: isBlocked,
            isHidden: currentTask?.hidden ?? false
        )
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: trimmedDescription,
            basePrice: basePrice,
            dueDate: dueDate,
            reminderCount: activeReminderDrafts.count,
            tagCount: taskTags.count,
            dependencyCount: activeTaskDependencies.count + activeRecurringTaskDependencies.count
        )
    }

    private var showsCompleteButton: Bool {
        if case .complete = taskTradeActionState {
            return true
        }
        return false
    }

    private var showsRefundButton: Bool {
        switch taskTradeActionState {
        case .refund:
            return true
        case .none, .complete:
            return false
        }
    }

    private var latestTaskTrade: Trade? {
        tradeStore.latestTaskTrade(taskId: taskID, includeRefunded: false)
    }

    private var taskTradeActionState: TaskTradeActionState {
        TaskTradeActionSupport.state(
            isNewMode: isNewMode,
            isCompleted: isCompleted,
            claimed: false,
            taskTrade: latestTaskTrade,
            pricePreview: pricePreview
        )
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
                title: refunded ? "" : (isNewMode ? "New Task" : "Edit Task"),
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
        .sheet(isPresented: $showingPrice) {
            BasePriceModalView(price: $draft.basePrice, helperSeed: 200.0)
        }
        .sheet(isPresented: $showingDueDate) {
            TaskDueDateModal(dueDate: $draft.dueDate)
        }
        .sheet(isPresented: $showingReminders) {
            ReminderModalView(
                reminders: $draft.reminderDrafts,
                dueDate: draft.dueDate,
                referenceDate: reminderStore.referenceDate
            )
        }
        .sheet(isPresented: $showingTags) {
            TagsView(assignmentTarget: .task(taskID), shouldNotifySync: true)
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
                excludedTaskID: taskID,
                selectedTaskDependencyIDs: Set(activeTaskDependencies.map(\.dependsOnTaskId)),
                selectedRecurringTaskDependencyIDs: Set(activeRecurringTaskDependencies.map(\.recurringTaskId)),
                canSelectTask: { candidateTask in
                    !wouldCreateTaskDependencyCycle(dependsOnTaskID: candidateTask.id)
                },
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
        .sheet(item: $claimRoute) { route in
            TaskClaimModalView(
                task: route.task,
                price: route.price,
                hasPremiumAccess: hasPremiumAccess,
                onClaim: { adjustedPrice, adjustmentBaseAmount, oneTimeAdjustmentMultiplier in
                    completeTaskFromClaimModal(
                        route.task,
                        price: adjustedPrice,
                        adjustmentBaseAmount: adjustmentBaseAmount,
                        oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                        allowsRestrictedClaim: route.allowsRestrictedClaim
                    )
                }
            )
        }
        .sheet(item: $actionWarningReason) { reason in
            EntityActionWarningModalView(
                entityName: currentTask?.name ?? draftTask.name,
                actionTitle: "Complete Task",
                reason: reason,
                onCancel: { actionWarningReason = nil },
                onConfirm: {
                    actionWarningReason = nil
                    presentTaskClaimFromForm(allowsRestrictedClaim: true)
                }
            )
        }
        .sheet(isPresented: $showingHistory) {
            if let task = mode.task {
                TradeHistorySheetView(
                    filter: .task(task.id),
                    detents: [.large]
                )
            }
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
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
        .entityDeleteConfirmation(
            entityName: "Task",
            isPresented: $showingDeleteConfirmation,
            item: currentTask,
            onDelete: deleteTask
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
            tags: taskTags,
            activitySummary: completedActivitySummary,
            bottomSpacerHeight: isNewMode || showsCompleteButton || showsRefundButton ? 94 : 16,
            onTagsTapped: { showingTags = true },
            switcher: {
                EntityFormStaticTraitBadges(entity: "task", cadence: "one-time")
            },
            textFields: { textFieldsSection },
            extraContent: {
                if activeTaskDependencies.count + activeRecurringTaskDependencies.count > 0 {
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
        if let task = currentTask {
            EntityFormEditMenu(
                entityName: "Task",
                onDuplicate: { duplicateTask(task) },
                onToggleHidden: {
                    taskStore.setHidden(id: task.id, hidden: !task.hidden)
                },
                isHidden: task.hidden,
                onHistory: { showingHistory = true },
                onDelete: { showingDeleteConfirmation = true }
            )
        }
    }

    private var currentTask: TaskItem? {
        guard let task = mode.task else { return nil }
        return taskStore.tasks.first(where: { $0.id == task.id }) ?? task
    }

    private var completedActivitySummary: String? {
        guard let completionDate, isCompleted else { return nil }
        return "Completed \(completionDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
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
                    entityName: "Task",
                    isEnabled: !trimmedName.isEmpty,
                    action: commitForm
                )
            } else {
                switch taskTradeActionState {
                case .complete(let amount):
                    let gateReason = actionGateReason
                    BochiActionButton(
                        amount: amount,
                        polarity: .earning,
                        layout: .expanded(title: EntityActionGateSupport.actionTitle(defaultTitle: "Complete Task", reason: gateReason)),
                        usesMainThemeStyle: gateReason != nil,
                        themeRoleOverride: .task
                    ) {
                        if let gateReason {
                            actionWarningReason = gateReason
                            return
                        }

                        presentTaskClaimFromForm(allowsRestrictedClaim: false)
                    }
                case .refund(let amount):
                    BochiActionButton(
                        amount: amount,
                        polarity: .spending,
                        layout: .expanded(title: "Refund Task"),
                        showsPremiumBadge: !hasPremiumAccess,
                        usesPremiumStyle: !hasPremiumAccess,
                        themeRoleOverride: .task
                    ) {
                        refundCompletedTaskFromForm()
                    }
                case .none:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                taskDependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore)
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
        basePrice: Int,
        dueDate: Date?,
        reminderCount: Int,
        tagCount: Int,
        dependencyCount: Int
    ) -> Bool {
        !name.isEmpty
            || !description.isEmpty
            || basePrice != 200
            || dueDate != nil
            || reminderCount > 0
            || tagCount > 0
            || dependencyCount > 0
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        basePrice: Int,
        dueDate: Date?,
        reminderSummary: String,
        hasReminders: Bool,
        dependencyCount: Int = 0,
        reminderIsPremiumLocked: Bool = false,
        dependencyIsPremiumLocked: Bool = false,
        timerIsPremiumLocked: Bool = false
    ) -> [EntityFormPillConfig] {
        buildPricePillData(
            basePrice: basePrice
        ) + buildNonPricePillData(
            hasTagsApplied: hasTagsApplied,
            dueDate: dueDate,
            reminderSummary: reminderSummary,
            hasReminders: hasReminders,
            dependencyCount: dependencyCount,
            reminderIsPremiumLocked: reminderIsPremiumLocked,
            dependencyIsPremiumLocked: dependencyIsPremiumLocked,
            timerIsPremiumLocked: timerIsPremiumLocked
        )
    }

    static func buildPricePillData(
        basePrice: Int?,
        priceRequiresAttention: Bool = false
    ) -> [EntityFormPillConfig] {
        [
            EntityFormPillConfig(
                id: "price",
                label: basePrice.map(String.init) ?? "Price",
                icon: "cube",
                isSet: basePrice != nil,
                requiresAttention: priceRequiresAttention
            )
        ]
    }

    static func buildNonPricePillData(
        hasTagsApplied: Bool,
        timerLabel: String = "Timer",
        hasTimer: Bool = false,
        dueDate: Date?,
        reminderSummary: String,
        hasReminders: Bool,
        dependencyCount: Int = 0,
        reminderIsPremiumLocked: Bool = false,
        dependencyIsPremiumLocked: Bool = false,
        timerIsPremiumLocked: Bool = false
    ) -> [EntityFormPillConfig] {
        [
            EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            EntityFormPillConfig(
                id: "timer",
                label: timerLabel,
                icon: "stopwatch",
                isSet: hasTimer,
                isPremiumLocked: timerIsPremiumLocked
            ),
            EntityFormPillConfig(id: "dueDate", label: dueDate.map(Self.dueDateSummary) ?? "Due Date", icon: "calendar", isSet: dueDate != nil),
            EntityFormPillConfig(
                id: "reminders",
                label: reminderSummary,
                icon: "bell",
                isSet: hasReminders,
                isPremiumLocked: reminderIsPremiumLocked
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
            basePrice: basePrice
        )
        return EntityFormSupport.buildPills(configs: configs, actions: pillActions)
    }

    private func buildNonPricePills() -> [PillItem] {
        let configs = Self.buildNonPricePillData(
            hasTagsApplied: !taskTags.isEmpty,
            timerLabel: timerPillLabel,
            hasTimer: resolvedTimerSelection != .none,
            dueDate: dueDate,
            reminderSummary: ReminderDraftSupport.summary(for: reminderDrafts, now: reminderStore.referenceDate),
            hasReminders: !activeReminderDrafts.isEmpty,
            dependencyCount: activeTaskDependencies.count + activeRecurringTaskDependencies.count,
            reminderIsPremiumLocked: !hasPremiumAccess,
            dependencyIsPremiumLocked: !hasPremiumAccess,
            timerIsPremiumLocked: !hasPremiumAccess
        )
        return EntityFormSupport.buildPills(configs: configs, actions: pillActions)
    }

    private var pillActions: [String: () -> Void] {
        [
            "tags": { showingTags = true },
            "price": { showingPrice = true },
            "timer": { openTimerOrPremiumUpsell() },
            "dueDate": { showingDueDate = true },
            "reminders": { openRemindersOrPremiumUpsell() },
            "dependencies": { openDependencyPickerOrPremiumUpsell() }
        ]
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, isNewMode {
            draft = TaskFormDraft(prefill: prefill)
        } else if let task = mode.task {
            draft = TaskFormDraft(
                task: task,
                reminderDrafts: reminderStore.reminderDrafts(for: .task(task.id)),
                taskDependencies: taskDependencyStore.activeTaskDependencies(for: task.id),
                recurringTaskDependencies: taskDependencyStore.activeRecurringTaskDependencies(for: task.id)
            )
        }

        hasAppliedInitialLoad = true

        guard let initialFocus else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch initialFocus {
            case .price:
                showingPrice = true
            case .dueDate:
                showingDueDate = true
            case .reminders:
                openRemindersOrPremiumUpsell()
            case .tags:
                showingTags = true
            }
        }
    }

    private func autoSaveIfNeeded() {
        guard !isNewMode, hasAppliedInitialLoad else { return }
        _ = persistTask()
    }

    private func commitForm() {
        if isNewMode {
            guard !trimmedName.isEmpty else { return }
            guard let task = persistTask() else { return }
            didPersist = true
            onCreated?(task)
        }

        dismiss()
    }

    private func duplicateTask(_ task: TaskItem) {
        dismiss()
        onDuplicate?(task)
    }

    private func deleteTask(_ task: TaskItem) {
        dismiss()
        if let onDelete {
            onDelete(task)
            return
        }

        EntityDeletionService.deleteTask(
            task,
            reminderStore: reminderStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore
        )
    }

    private func discardDraft() {
        onDiscard?(draft.snapshot(tagIDs: taskTagIDs))
    }

    @discardableResult
    private func persistTask() -> TaskItem? {
        TaskFormPersistenceSupport.persistTask(
            task: mode.task,
            taskID: draft.taskID,
            name: draft.name,
            description: draft.description,
            basePrice: draft.basePrice,
            dueDate: draft.dueDate,
            timerSelection: draft.timerSelection,
            reminderDrafts: draft.reminderDrafts,
            taskDependencies: draft.taskDependencies,
            recurringTaskDependencies: draft.recurringTaskDependencies,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            reminderStore: reminderStore
        )
    }

    private func presentTaskClaimFromForm(allowsRestrictedClaim: Bool = false) {
        guard !isNewMode, !isCompleted else { return }
        guard let persistedTask = persistTask() else { return }
        guard allowsRestrictedClaim || !taskDependencyStore.isTaskBlocked(
            draftTask,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            showingBlockedTaskAlert = true
            return
        }

        claimRoute = TaskClaimRoute(
            task: persistedTask,
            price: pricePreview,
            allowsRestrictedClaim: allowsRestrictedClaim
        )
    }

    private func completeTaskFromClaimModal(
        _ task: TaskItem,
        price: Int,
        adjustmentBaseAmount: Int?,
        oneTimeAdjustmentMultiplier: Double?,
        allowsRestrictedClaim: Bool = false
    ) {
        guard allowsRestrictedClaim || !taskDependencyStore.isTaskBlocked(
            task,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            showingBlockedTaskAlert = true
            return
        }

        let completionDate = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: price,
            adjustmentBaseAmount: adjustmentBaseAmount,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
        guard completionDate != nil else { return }
        didPersist = true
    }

    private func refundCompletedTaskFromForm() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .refunds
            return
        }

        guard let trade = latestTaskTrade else { return }

        let refundTrade = TradeRefundService.refund(
            for: trade,
            tradeStore: tradeStore,
            balanceStore: balanceStore
        )
        guard refundTrade != nil else { return }
        refunded = true
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

    private func openRemindersOrPremiumUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .reminders
            return
        }

        showingReminders = true
    }

    private func openTimerOrPremiumUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .timers
            return
        }

        showingTimer = true
    }

    nonisolated static func dueDateSummary(_ dueDate: Date) -> String {
        if Calendar.current.isDateInToday(dueDate) {
            return "Today \(dueDate.formatted(.dateTime.hour().minute()))"
        }
        if Calendar.current.isDateInTomorrow(dueDate) {
            return "Tomorrow \(dueDate.formatted(.dateTime.hour().minute()))"
        }
        return dueDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
            taskID: taskID,
            selectedTask: selectedTask
        )
    }

    private func saveRecurringTaskDependency(
        recurringTask: RecurringTask,
        existingDependency: TaskRecurringTaskDependency?,
        requiredCompletions: Int
    ) {
        DependencyDraftSupport.saveRecurringTaskDependency(
            to: &draft.recurringTaskDependencies,
            taskID: taskID,
            recurringTask: recurringTask,
            existingDependency: existingDependency,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: tradeStore.recurringTaskCompletionCount(recurringTaskId: recurringTask.id)
        )
    }

    private func recurringTaskDependencyCountBinding(_ dependency: TaskRecurringTaskDependency, recurringTask: RecurringTask) -> Binding<Int> {
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

    private func removeTaskDependency(_ dependency: TaskTaskDependency) {
        DependencyDraftSupport.remove(dependency, from: &draft.taskDependencies)
    }

    private func removeRecurringTaskDependency(_ dependency: TaskRecurringTaskDependency) {
        DependencyDraftSupport.remove(dependency, from: &draft.recurringTaskDependencies)
    }

    private func wouldCreateTaskDependencyCycle(dependsOnTaskID: RecordID) -> Bool {
        guard dependsOnTaskID != taskID else { return true }

        let otherDependencies = taskDependencyStore.taskTaskDependencies.filter {
            $0.deletedAt == nil && $0.taskId != taskID
        }
        let adjacency = Dictionary(grouping: otherDependencies + activeTaskDependencies, by: \.taskId)
            .mapValues { $0.map(\.dependsOnTaskId) }

        var visited: Set<RecordID> = []
        var stack: [RecordID] = [dependsOnTaskID]

        while let current = stack.popLast() {
            if current == taskID {
                return true
            }

            guard visited.insert(current).inserted else { continue }
            stack.append(contentsOf: adjacency[current] ?? [])
        }

        return false
    }
}

#Preview("New Task") {
    let taskStore = TaskStore()
    let recurringTaskStore = RecurringTaskStore()
    let tradeStore = TradeStore()
    let authManager = AuthManager(
        apiClient: AppConfiguration.makeAuthAPIClient(),
        tokenStorage: KeychainTokenStorage(),
        appleEntitlementClient: StoreKitAppleEntitlementClient()
    )

    TaskFormView(mode: .new)
        .environment(authManager)
        .environment(taskStore)
        .environment(TaskDependencyStore())
        .environment(RewardDependencyStore())
        .environment(recurringTaskStore)
        .environment(TagStore())
        .environment(tradeStore)
        .environment(BalanceStore())
        .environment(ReminderStore())
        .environment(PremiumAccessStore())
}
