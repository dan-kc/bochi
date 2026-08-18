import SwiftUI
import UIKit

struct NewEntityFormRoute: Identifiable {
    let id = UUID()
    let snapshot: NewEntityFormSnapshot
    let originTab: AppTab
}

private enum NewTaskDependencyEditorRoute: Identifiable {
    case task(TaskItem)
    case recurringTask(RecurringTask)

    var id: String {
        switch self {
        case .task(let task):
            "task:\(task.id.rawValue)"
        case .recurringTask(let recurringTask):
            "recurringTask:\(recurringTask.id.rawValue)"
        }
    }
}

private enum NewEntityCadenceKind: String, CaseIterable, Identifiable {
    case oneOff
    case recurring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneOff:
            "One-time"
        case .recurring:
            "Recurring"
        }
    }
}

struct NewEntityFormView: View {
    @Environment(\.bochiTheme) private var theme
    let onTaskCreated: ((TaskItem) -> Void)?
    let onRecurringTaskCreated: ((RecurringTask) -> Void)?
    let onRewardCreated: ((Reward) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TimerStore.self) private var timerStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @State private var selectedEntity: EntityFormKind
    @State private var selectedCadence: NewEntityCadenceKind
    @State private var name: String
    @State private var description: String
    @State private var sharedTagIDs: [RecordID]

    @State private var taskBasePrice: Int?
    @State private var taskDueDate: Date?
    @State private var taskTimerSelection: EntityTimerSelection
    @State private var taskReminderDrafts: [ReminderDraft]
    @State private var taskID: RecordID
    @State private var taskDependencies: [TaskTaskDependency]
    @State private var recurringTaskDependencies: [TaskRecurringTaskDependency]

    @State private var recurringTaskFrequency: Double?
    @State private var recurringTaskLockoutDurationSeconds: Int?
    @State private var recurringTaskBasePrice: Int?
    @State private var recurringTaskTimerSelection: EntityTimerSelection
    @State private var recurringTaskReminderDrafts: [ReminderDraft]
    @State private var recurringTaskID: RecordID

    @State private var rewardMaxFrequency: Double?
    @State private var rewardLockoutDurationSeconds: Int?
    @State private var rewardBasePrice: Int?
    @State private var rewardTimerSelection: EntityTimerSelection
    @State private var rewardID: RecordID
    @State private var rewardTaskDependencies: [RewardTaskDependency]
    @State private var rewardRecurringTaskDependencies: [RewardRecurringTaskDependency]

    @State private var showingTags = false
    @State private var showingReminders = false
    @State private var showingPrice = false
    @State private var showingDueDate = false
    @State private var showingFrequency = false
    @State private var showingLockout = false
    @State private var showingTimer = false
    @State private var showingDependencyPicker = false
    @State private var dependencyEditorRoute: NewTaskDependencyEditorRoute? = nil
    @State private var dependencyTradeRecurringTaskRoute: RecurringTaskTradeRoute? = nil
    @State private var showingBlockedTaskAlert = false
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var showingDiscardAlert = false
    @State private var didPersist = false
    @State private var shouldShowRequiredFields = false

    @FocusState private var focusedField: FieldFocus?

    enum FieldFocus: Hashable {
        case name
        case description
    }

    init(
        initialSnapshot: NewEntityFormSnapshot,
        onTaskCreated: ((TaskItem) -> Void)? = nil,
        onRecurringTaskCreated: ((RecurringTask) -> Void)? = nil,
        onRewardCreated: ((Reward) -> Void)? = nil
    ) {
        self.onTaskCreated = onTaskCreated
        self.onRecurringTaskCreated = onRecurringTaskCreated
        self.onRewardCreated = onRewardCreated
        _selectedEntity = State(initialValue: initialSnapshot.selectedEntity == .reward ? .reward : .task)
        _selectedCadence = State(initialValue: Self.initialCadence(for: initialSnapshot))
        _name = State(initialValue: initialSnapshot.shared.name)
        _description = State(initialValue: initialSnapshot.shared.description)
        _sharedTagIDs = State(initialValue: initialSnapshot.shared.tagIDs)
        _taskBasePrice = State(initialValue: initialSnapshot.task.basePrice)
        _taskDueDate = State(initialValue: initialSnapshot.task.dueDate)
        _taskTimerSelection = State(initialValue: initialSnapshot.task.timerSelection)
        _taskReminderDrafts = State(initialValue: initialSnapshot.task.reminderDrafts)
        _taskID = State(initialValue: initialSnapshot.task.taskId)
        _taskDependencies = State(initialValue: initialSnapshot.task.taskDependencies)
        _recurringTaskDependencies = State(initialValue: initialSnapshot.task.recurringTaskDependencies)
        _recurringTaskFrequency = State(initialValue: initialSnapshot.recurringTask.frequency)
        _recurringTaskLockoutDurationSeconds = State(initialValue: initialSnapshot.recurringTask.lockoutDurationSeconds)
        _recurringTaskBasePrice = State(initialValue: initialSnapshot.recurringTask.basePrice)
        _recurringTaskTimerSelection = State(initialValue: initialSnapshot.recurringTask.timerSelection)
        _recurringTaskReminderDrafts = State(initialValue: initialSnapshot.recurringTask.reminderDrafts)
        _recurringTaskID = State(initialValue: initialSnapshot.recurringTask.recurringTaskId)
        _rewardMaxFrequency = State(initialValue: initialSnapshot.reward.maxFrequency)
        _rewardLockoutDurationSeconds = State(initialValue: initialSnapshot.reward.lockoutDurationSeconds)
        _rewardBasePrice = State(initialValue: initialSnapshot.reward.basePrice)
        _rewardTimerSelection = State(initialValue: initialSnapshot.reward.timerSelection)
        _rewardID = State(initialValue: initialSnapshot.reward.rewardId)
        _rewardTaskDependencies = State(initialValue: initialSnapshot.reward.taskDependencies)
        _rewardRecurringTaskDependencies = State(initialValue: initialSnapshot.reward.recurringTaskDependencies)
    }

    var body: some View {
        NavigationStack {
            EntityFormEditorShell(
                isEditingText: isEditingText,
                valuePills: currentValuePills,
                detailPills: currentDetailPills,
                tags: sharedTags,
                bottomSpacerHeight: 94,
                pillTransitionStyle: .entitySwitcher,
                onTagsTapped: { showingTags = true },
                switcher: { switchers },
                textFields: { textFieldsSection },
                extraContent: { dependenciesSection },
                floatingControls: { addButton }
            )
            .entityFormNavigation(
                title: "New \(selectedEntity.title)",
                isNewMode: true,
                isEditingText: isEditingText,
                canCommitNewEntity: canPersistCurrentEntity,
                onCancel: { requestDismiss() },
                onFinishTextEditing: { focusedField = nil },
                onCommit: persistCurrentEntity,
                menuContent: { EmptyView() }
            )
        }
        .entityFormPresentation(theme: theme, isEditingText: isEditingText)
        .handleInteractiveDismiss(isDisabled: shouldConfirmDiscard, onAttempt: requestDismiss)
        .animation(.easeInOut(duration: 0.22), value: activeEntity)
        .sheet(isPresented: $showingPrice) {
            BasePriceModalView(price: activeBasePriceBinding, helperSeed: activePriceHelperSeed)
        }
        .sheet(isPresented: $showingDueDate) {
            TaskDueDateModal(dueDate: $taskDueDate)
        }
        .sheet(isPresented: $showingReminders) {
            ReminderModalView(
                reminders: activeReminderDraftsBinding,
                dueDate: activeEntity == .task ? taskDueDate : nil,
                referenceDate: reminderStore.referenceDate
            )
        }
        .sheet(isPresented: $showingTags, onDismiss: refreshSharedTagsFromCurrentTarget) {
            TagsView(assignmentTarget: currentTagTarget, shouldNotifySync: false)
        }
        .sheet(isPresented: $showingTimer) {
            TimerModalView(
                selection: activeTimerSelectionBinding,
                durationSeconds: nil,
                allowsDurationTimer: false
            )
        }
        .sheet(isPresented: $showingFrequency) {
            frequencySheet
        }
        .sheet(isPresented: $showingLockout) {
            lockoutSheet
        }
        .sheet(isPresented: $showingDependencyPicker) {
            dependencyPicker
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
                quote: route.quote,
                allowsRestrictedClaim: route.allowsRestrictedClaim
            )
        }
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
        .blockedTaskDependencyAlert(isPresented: $showingBlockedTaskAlert)
        .alert("Discard New \(selectedEntity.title)?", isPresented: $showingDiscardAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        .task {
            synchronizeDraftTagAssignments()
        }
        .onChange(of: sharedTagIDs) { _, _ in
            synchronizeDraftTagAssignments()
        }
        .onChange(of: appNavigationStore.newEntityFormDismissAttemptID) { _, attemptID in
            guard attemptID != nil else { return }
            requestDismiss()
        }
        .onDisappear {
            guard !didPersist else { return }
            cleanupAllDraftTags()
        }
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    private var trimmedName: String {
        EntityFormSupport.trimmedName(name)
    }

    private var activeBasePrice: Int? {
        switch activeEntity {
        case .task:
            taskBasePrice
        case .recurringTask:
            recurringTaskBasePrice
        case .reward:
            rewardBasePrice
        }
    }

    private var canPersistCurrentEntity: Bool {
        !trimmedName.isEmpty && activeBasePrice != nil
    }

    private var nameRequiresAttention: Bool {
        shouldShowRequiredFields && trimmedName.isEmpty
    }

    private var priceRequiresAttention: Bool {
        shouldShowRequiredFields && activeBasePrice == nil
    }

    private var activeEntity: EntityFormKind {
        if selectedEntity == .task, selectedCadence == .recurring {
            return .recurringTask
        }
        return selectedEntity
    }

    private var sharedTags: [Tag] {
        tagStore.activeTags.filter { sharedTagIDs.contains($0.id) }
    }

    private var currentTagTarget: TagAssignmentTarget {
        switch activeEntity {
        case .task:
            .task(taskID)
        case .recurringTask:
            .recurringTask(recurringTaskID)
        case .reward:
            .reward(rewardID)
        }
    }

    private var shouldConfirmDiscard: Bool {
        !didPersist && EntityFormSwitcherSupport.hasRecoverableContent(currentSnapshot)
    }

    private var activeReminderDrafts: [ReminderDraft] {
        switch activeEntity {
        case .task:
            ReminderDraftSupport.active(taskReminderDrafts, now: reminderStore.referenceDate)
        case .recurringTask:
            ReminderDraftSupport.active(recurringTaskReminderDrafts, now: reminderStore.referenceDate)
        case .reward:
            []
        }
    }

    private var switchers: some View {
        VStack(alignment: .leading, spacing: 12) {
            EntityFormSwitcher(
                selectedEntity: selectedEntity,
                onSelect: { entity in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedEntity = entity
                    }
                }
            )

            cadenceSwitcher
        }
    }

    private var cadenceSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(NewEntityCadenceKind.allCases) { cadence in
                Button {
                    guard cadence != selectedCadence else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedCadence = cadence
                    }
                } label: {
                    Text(cadence.title)
                        .font(cadence == selectedCadence ? .callout : .subheadline)
                        .fontWeight(cadence == selectedCadence ? .regular : .semibold)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(cadence == selectedCadence ? theme.primaryText() : theme.secondaryText())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            cadence == selectedCadence ? theme.selectedBackground(for: .neutral) : theme.componentBackground(),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            if cadence == selectedCadence {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(theme.strongBorder(for: .neutral), lineWidth: 1)
                            }
                        }
                        .opacity(cadence == selectedCadence ? 1 : 0.55)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var textFieldsSection: some View {
        EntityFormTextFieldsSection(
            name: $name,
            description: $description,
            focusedField: $focusedField,
            nameFocus: .name,
            descriptionFocus: .description,
            nameRequiresAttention: nameRequiresAttention
        )
    }

    private var addButton: some View {
        EntityFormAddActionButton(
            entityName: selectedEntity.title,
            isEnabled: canPersistCurrentEntity
        ) {
            persistCurrentEntity()
        } disabledAction: {
            showRequiredFields()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentValuePills: [PillItem] {
        switch activeEntity {
        case .task:
            return EntityFormSupport.buildPills(
                configs: TaskFormView.buildPricePillData(
                    basePrice: taskBasePrice,
                    priceRequiresAttention: priceRequiresAttention
                ),
                actions: pillActions
            )
        case .recurringTask:
            return EntityFormSupport.buildPills(
                configs: RecurringTaskFormView.buildPricePillData(
                    basePrice: recurringTaskBasePrice,
                    frequency: recurringTaskFrequency,
                    priceRequiresAttention: priceRequiresAttention
                ),
                actions: pillActions
            )
        case .reward:
            let configs = RewardFormView.buildPricePillData(
                basePrice: rewardBasePrice,
                maxFrequency: selectedCadence == .recurring ? rewardMaxFrequency : nil,
                priceRequiresAttention: priceRequiresAttention
            )
            .filter { selectedCadence == .recurring || $0.id != "frequency" }
            return EntityFormSupport.buildPills(configs: configs, actions: pillActions)
        }
    }

    private var currentDetailPills: [PillItem] {
        switch activeEntity {
        case .task:
            let configs = TaskFormView.buildNonPricePillData(
                hasTagsApplied: !sharedTagIDs.isEmpty,
                timerLabel: timerPillLabel(for: taskTimerSelection),
                hasTimer: taskTimerSelection != .none,
                dueDate: taskDueDate,
                reminderSummary: ReminderDraftSupport.summary(for: taskReminderDrafts, now: reminderStore.referenceDate),
                hasReminders: !activeReminderDrafts.isEmpty,
                dependencyCount: activeTaskDependencies.count + activeRecurringTaskDependencies.count,
                reminderIsPremiumLocked: !hasPremiumAccess,
                dependencyIsPremiumLocked: !hasPremiumAccess,
                timerIsPremiumLocked: !hasPremiumAccess
            )
            return EntityFormSupport.buildPills(configs: configs, actions: pillActions)
        case .recurringTask:
            let configs = RecurringTaskFormView.buildNonPricePillData(
                hasTagsApplied: !sharedTagIDs.isEmpty,
                timerLabel: timerPillLabel(for: recurringTaskTimerSelection),
                hasTimer: recurringTaskTimerSelection != .none,
                lockoutDurationSeconds: recurringTaskLockoutDurationSeconds,
                reminderSummary: ReminderDraftSupport.summary(for: recurringTaskReminderDrafts, now: reminderStore.referenceDate),
                hasReminders: !activeReminderDrafts.isEmpty,
                reminderIsPremiumLocked: !hasPremiumAccess,
                lockoutIsPremiumLocked: !hasPremiumAccess,
                timerIsPremiumLocked: !hasPremiumAccess
            )
            return EntityFormSupport.buildPills(configs: configs, actions: pillActions)
        case .reward:
            let configs = RewardFormView.buildNonPricePillData(
                hasTagsApplied: !sharedTagIDs.isEmpty,
                timerLabel: timerPillLabel(for: rewardTimerSelection),
                hasTimer: rewardTimerSelection != .none && rewardTimerSelection != .duration,
                lockoutDurationSeconds: rewardLockoutDurationSeconds,
                dependencyCount: activeRewardTaskDependencies.count + activeRewardRecurringTaskDependencies.count,
                lockoutIsPremiumLocked: !hasPremiumAccess,
                dependencyIsPremiumLocked: !hasPremiumAccess,
                timerIsPremiumLocked: !hasPremiumAccess
            )
            return EntityFormSupport.buildPills(configs: configs, actions: pillActions)
        }
    }

    private var pillActions: [String: () -> Void] {
        [
            "tags": { showingTags = true },
            "price": { showingPrice = true },
            "timer": { openTimerOrPremiumUpsell() },
            "dueDate": { showingDueDate = true },
            "reminders": { openRemindersOrPremiumUpsell() },
            "dependencies": { openDependencyPickerOrPremiumUpsell() },
            "frequency": { showingFrequency = true },
            "lockout": { openLockoutOrPremiumUpsell() }
        ]
    }

    @ViewBuilder
    private var dependenciesSection: some View {
        if currentDependencyCount > 0, hasPremiumAccess {
            switch activeEntity {
            case .task:
                taskDependenciesSection
            case .recurringTask:
                EmptyView()
            case .reward:
                rewardDependenciesSection
            }
        }
    }

    private var taskDependenciesSection: some View {
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

    private var rewardDependenciesSection: some View {
        DependencySectionView(
            taskDependencies: activeRewardTaskDependencies,
            recurringTaskDependencies: activeRewardRecurringTaskDependencies,
            onAdd: { showingDependencyPicker = true },
            task: { dependency in
                taskStore.tasks.first(where: { $0.id == dependency.dependsOnTaskId && $0.deletedAt == nil })
            },
            taskIsComplete: { task in
                tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) != nil
            },
            onOpenTask: { dependencyEditorRoute = .task($0) },
            onCompleteTask: completeDependencyTask,
            onRemoveTaskDependency: removeRewardTaskDependency,
            recurringTask: { dependency in
                recurringTaskStore.recurringTasks.first(where: { $0.id == dependency.recurringTaskId && $0.deletedAt == nil })
            },
            recurringTaskProgress: { dependency in
                rewardDependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore)
            },
            recurringTaskRequiredCompletions: \.requiredCompletions,
            recurringTaskRequiredCompletionsBinding: rewardRecurringTaskDependencyCountBinding,
            onOpenRecurringTask: { dependencyEditorRoute = .recurringTask($0) },
            onClaimRecurringTask: openDependencyRecurringTaskClaim,
            onRemoveRecurringTaskDependency: removeRewardRecurringTaskDependency
        )
    }

    @ViewBuilder
    private var frequencySheet: some View {
        switch activeEntity {
        case .recurringTask:
            RecurringTaskFrequencyModal(frequency: $recurringTaskFrequency)
        case .reward:
            RewardFrequencyModal(maxFrequency: $rewardMaxFrequency)
        case .task:
            EmptyView()
        }
    }

    @ViewBuilder
    private var lockoutSheet: some View {
        switch activeEntity {
        case .recurringTask:
            RecurringTaskLockoutDurationModal(durationSeconds: $recurringTaskLockoutDurationSeconds)
        case .reward:
            RewardLockoutDurationModal(durationSeconds: $rewardLockoutDurationSeconds)
        case .task:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dependencyPicker: some View {
        switch activeEntity {
        case .task:
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
        case .reward:
            DependencyPickerView(
                selectedTaskDependencyIDs: Set(activeRewardTaskDependencies.map(\.dependsOnTaskId)),
                selectedRecurringTaskDependencyIDs: Set(activeRewardRecurringTaskDependencies.map(\.recurringTaskId)),
                onSave: { selectedTasks, selectedRecurringTasks in
                    selectedTasks.forEach(addRewardTaskDependency)
                    selectedRecurringTasks.forEach { selection in
                        saveRewardRecurringTaskDependency(
                            recurringTask: selection.0,
                            existingDependency: activeRewardRecurringTaskDependencies.first(where: { $0.recurringTaskId == selection.0.id }),
                            requiredCompletions: selection.1
                        )
                    }
                }
            )
        case .recurringTask:
            EmptyView()
        }
    }

    private var activeBasePriceBinding: Binding<Int?> {
        Binding(
            get: {
                switch activeEntity {
                case .task: taskBasePrice
                case .recurringTask: recurringTaskBasePrice
                case .reward: rewardBasePrice
                }
            },
            set: { newValue in
                switch activeEntity {
                case .task: taskBasePrice = newValue
                case .recurringTask: recurringTaskBasePrice = newValue
                case .reward: rewardBasePrice = newValue
                }
            }
        )
    }

    private var activeTimerSelectionBinding: Binding<EntityTimerSelection> {
        Binding(
            get: {
                switch activeEntity {
                case .task: taskTimerSelection
                case .recurringTask: recurringTaskTimerSelection
                case .reward: rewardTimerSelection
                }
            },
            set: { newValue in
                switch activeEntity {
                case .task: taskTimerSelection = newValue
                case .recurringTask: recurringTaskTimerSelection = newValue
                case .reward: rewardTimerSelection = newValue
                }
            }
        )
    }

    private var activeReminderDraftsBinding: Binding<[ReminderDraft]> {
        Binding(
            get: {
                switch activeEntity {
                case .task: taskReminderDrafts
                case .recurringTask: recurringTaskReminderDrafts
                case .reward: []
                }
            },
            set: { newValue in
                switch activeEntity {
                case .task: taskReminderDrafts = newValue
                case .recurringTask: recurringTaskReminderDrafts = newValue
                case .reward: break
                }
            }
        )
    }

    private var activePriceHelperSeed: Double {
        switch activeEntity {
        case .task:
            200.0
        case .recurringTask:
            100.0
        case .reward:
            500.0
        }
    }

    private var activeTaskDependencies: [TaskTaskDependency] {
        taskDependencies.filter { $0.deletedAt == nil }
    }

    private var activeRecurringTaskDependencies: [TaskRecurringTaskDependency] {
        recurringTaskDependencies.filter { $0.deletedAt == nil }
    }

    private var activeRewardTaskDependencies: [RewardTaskDependency] {
        rewardTaskDependencies.filter { $0.deletedAt == nil }
    }

    private var activeRewardRecurringTaskDependencies: [RewardRecurringTaskDependency] {
        rewardRecurringTaskDependencies.filter { $0.deletedAt == nil }
    }

    private var currentDependencyCount: Int {
        switch activeEntity {
        case .task:
            activeTaskDependencies.count + activeRecurringTaskDependencies.count
        case .recurringTask:
            0
        case .reward:
            activeRewardTaskDependencies.count + activeRewardRecurringTaskDependencies.count
        }
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    private var currentSnapshot: NewEntityFormSnapshot {
        NewEntityFormSnapshot(
            selectedEntity: activeEntity,
            shared: NewEntitySharedDraft(name: name, description: description, tagIDs: sharedTagIDs),
            task: NewTaskDraft(
                basePrice: taskBasePrice,
                dueDate: taskDueDate,
                timerSelection: taskTimerSelection,
                reminderDrafts: taskReminderDrafts,
                taskId: taskID,
                taskDependencies: taskDependencies,
                recurringTaskDependencies: recurringTaskDependencies
            ),
            recurringTask: NewRecurringTaskDraft(
                frequency: recurringTaskFrequency,
                lockoutDurationSeconds: recurringTaskLockoutDurationSeconds,
                basePrice: recurringTaskBasePrice,
                timerSelection: recurringTaskTimerSelection,
                reminderDrafts: recurringTaskReminderDrafts,
                recurringTaskId: recurringTaskID
            ),
            reward: NewRewardDraft(
                recurring: selectedCadence == .recurring,
                maxFrequency: rewardMaxFrequency,
                lockoutDurationSeconds: rewardLockoutDurationSeconds,
                basePrice: rewardBasePrice,
                timerSelection: rewardTimerSelection,
                rewardId: rewardID,
                taskDependencies: rewardTaskDependencies,
                recurringTaskDependencies: rewardRecurringTaskDependencies
            )
        )
    }

    private func timerPillLabel(for selection: EntityTimerSelection) -> String {
        switch selection {
        case .none:
            "Timer"
        case .duration:
            "Duration"
        case .named(let timerID):
            timerStore.timer(id: timerID)?.name ?? "Timer"
        }
    }

    private func persistCurrentEntity() {
        guard canPersistCurrentEntity else {
            showRequiredFields()
            return
        }

        switch activeEntity {
        case .task:
            guard let taskBasePrice else { return }
            guard let task = TaskFormPersistenceSupport.persistTask(
                task: nil,
                taskID: taskID,
                name: name,
                description: description,
                basePrice: taskBasePrice,
                dueDate: taskDueDate,
                timerSelection: taskTimerSelection,
                reminderDrafts: taskReminderDrafts,
                taskDependencies: taskDependencies,
                recurringTaskDependencies: recurringTaskDependencies,
                taskStore: taskStore,
                taskDependencyStore: taskDependencyStore,
                reminderStore: reminderStore
            ) else { return }

            finishPersisting(target: .task)
            onTaskCreated?(task)
        case .recurringTask:
            guard let recurringTaskBasePrice else { return }
            guard let recurringTask = recurringTaskStore.addRecurringTask(
                id: recurringTaskID,
                name: name,
                description: description,
                frequency: recurringTaskFrequency,
                lockoutDurationSeconds: recurringTaskLockoutDurationSeconds,
                basePrice: recurringTaskBasePrice,
                timerSelection: recurringTaskTimerSelection
            ) else { return }

            reminderStore.replaceReminders(for: .recurringTask(recurringTaskID), with: recurringTaskReminderDrafts)
            finishPersisting(target: .recurringTask)
            onRecurringTaskCreated?(recurringTask)
        case .reward:
            guard let rewardBasePrice else { return }
            guard let reward = rewardStore.addReward(
                id: rewardID,
                recurring: selectedCadence == .recurring,
                name: name,
                description: description,
                maxFrequency: selectedCadence == .recurring ? rewardMaxFrequency : nil,
                lockoutDurationSeconds: rewardLockoutDurationSeconds,
                basePrice: rewardBasePrice,
                timerSelection: rewardTimerSelection == .duration ? .none : rewardTimerSelection
            ) else { return }

            rewardDependencyStore.replaceDependencies(
                for: rewardID,
                taskDependencies: rewardTaskDependencies,
                recurringTaskDependencies: rewardRecurringTaskDependencies
            )
            finishPersisting(target: .reward)
            onRewardCreated?(reward)
        }

        dismiss()
    }

    private func finishPersisting(target: EntityFormKind) {
        markCurrentTagAssignmentsForSync(target: target)
        cleanupUnselectedDraftTags(preserving: target)
        didPersist = true
    }

    private func showRequiredFields() {
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            shouldShowRequiredFields = true
        }
    }

    private func requestDismiss() {
        guard shouldConfirmDiscard else {
            dismiss()
            return
        }

        focusedField = nil
        showingDiscardAlert = true
    }

    private static func initialCadence(for snapshot: NewEntityFormSnapshot) -> NewEntityCadenceKind {
        switch snapshot.selectedEntity {
        case .recurringTask:
            .recurring
        case .reward:
            snapshot.reward.recurring ? .recurring : .oneOff
        case .task:
            .oneOff
        }
    }

    private func refreshSharedTagsFromCurrentTarget() {
        let refreshedIDs = tagStore.tags(for: currentTagTarget)
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
        guard refreshedIDs != sharedTagIDs else { return }
        sharedTagIDs = refreshedIDs
    }

    private func synchronizeDraftTagAssignments() {
        NewEntityFormTagAssignmentSupport.synchronizeSharedTags(
            sharedTagIDs,
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            tagStore: tagStore,
            shouldNotifySync: false
        )
    }

    private func markCurrentTagAssignmentsForSync(target: EntityFormKind) {
        let assignmentTarget: TagAssignmentTarget = switch target {
        case .task:
            .task(taskID)
        case .recurringTask:
            .recurringTask(recurringTaskID)
        case .reward:
            .reward(rewardID)
        }

        // Draft tag rows are local-only while the user flips entity type; once
        // they commit, only the saved entity's tag links should enter sync.
        for tagID in sharedTagIDs {
            tagStore.addTag(tagId: tagID, to: assignmentTarget)
        }
    }

    private func cleanupUnselectedDraftTags(preserving target: EntityFormKind?) {
        NewEntityFormTagAssignmentSupport.cleanupDraftTags(
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            preserving: target,
            tagStore: tagStore,
            shouldNotifySync: false
        )
    }

    private func cleanupAllDraftTags() {
        cleanupUnselectedDraftTags(preserving: nil)
    }

    private func openRemindersOrPremiumUpsell() {
        guard activeEntity != .reward else { return }
        guard hasPremiumAccess else {
            premiumUpsellFeature = .reminders
            return
        }

        showingReminders = true
    }

    private func openLockoutOrPremiumUpsell() {
        guard activeEntity == .recurringTask || activeEntity == .reward else { return }
        guard hasPremiumAccess else {
            premiumUpsellFeature = .lockouts
            return
        }

        showingLockout = true
    }

    private func openDependencyPickerOrPremiumUpsell() {
        guard activeEntity == .task || activeEntity == .reward else { return }
        guard hasPremiumAccess else {
            premiumUpsellFeature = .dependencies
            return
        }

        showingDependencyPicker = true
    }

    private func openTimerOrPremiumUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .timers
            return
        }

        showingTimer = true
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
            to: &taskDependencies,
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
            to: &recurringTaskDependencies,
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
        DependencyDraftSupport.remove(dependency, from: &taskDependencies)
    }

    private func removeRecurringTaskDependency(_ dependency: TaskRecurringTaskDependency) {
        DependencyDraftSupport.remove(dependency, from: &recurringTaskDependencies)
    }

    private func addRewardTaskDependency(_ selectedTask: TaskItem) {
        DependencyDraftSupport.addTaskDependency(
            to: &rewardTaskDependencies,
            rewardID: rewardID,
            selectedTask: selectedTask
        )
    }

    private func saveRewardRecurringTaskDependency(
        recurringTask: RecurringTask,
        existingDependency: RewardRecurringTaskDependency?,
        requiredCompletions: Int
    ) {
        DependencyDraftSupport.saveRecurringTaskDependency(
            to: &rewardRecurringTaskDependencies,
            rewardID: rewardID,
            recurringTask: recurringTask,
            existingDependency: existingDependency,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: tradeStore.recurringTaskCompletionCount(recurringTaskId: recurringTask.id)
        )
    }

    private func rewardRecurringTaskDependencyCountBinding(_ dependency: RewardRecurringTaskDependency, recurringTask: RecurringTask) -> Binding<Int> {
        DependencyDraftSupport.recurringTaskDependencyCountBinding(
            dependency: dependency,
            recurringTask: recurringTask,
            requiredCompletions: \.requiredCompletions,
            save: { recurringTask, dependency, requiredCompletions in
                saveRewardRecurringTaskDependency(
                    recurringTask: recurringTask,
                    existingDependency: dependency,
                    requiredCompletions: requiredCompletions
                )
            }
        )
    }

    private func removeRewardTaskDependency(_ dependency: RewardTaskDependency) {
        DependencyDraftSupport.remove(dependency, from: &rewardTaskDependencies)
    }

    private func removeRewardRecurringTaskDependency(_ dependency: RewardRecurringTaskDependency) {
        DependencyDraftSupport.remove(dependency, from: &rewardRecurringTaskDependencies)
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

private struct InteractiveDismissHandler: UIViewControllerRepresentable {
    let isDisabled: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.isDisabled = isDisabled
        context.coordinator.onAttempt = onAttempt

        DispatchQueue.main.async {
            let presentationController = uiViewController.parent?.presentationController
                ?? uiViewController.presentationController
            context.coordinator.install(on: presentationController)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isDisabled: isDisabled, onAttempt: onAttempt)
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDisabled: Bool
        var onAttempt: () -> Void
        private weak var presentationController: UIPresentationController?

        init(isDisabled: Bool, onAttempt: @escaping () -> Void) {
            self.isDisabled = isDisabled
            self.onAttempt = onAttempt
        }

        func install(on presentationController: UIPresentationController?) {
            presentationController?.delegate = self
            self.presentationController = presentationController
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !isDisabled
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
        }
    }
}

private extension View {
    func handleInteractiveDismiss(isDisabled: Bool, onAttempt: @escaping () -> Void) -> some View {
        background {
            // Behaviour: drag dismissals share the same discard confirmation as
            // the visible Cancel button.
            InteractiveDismissHandler(isDisabled: isDisabled, onAttempt: onAttempt)
        }
    }
}
