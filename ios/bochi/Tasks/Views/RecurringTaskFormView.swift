import SwiftUI

// RecurringTaskFormMode is like a discriminated union in TypeScript:
//   { type: "new" } | { type: "change", recurringTask: RecurringTask }
//
// Swift enums can carry data directly, so `.change` includes the recurringTask being edited.
enum RecurringTaskFormMode: Equatable {
    case new
    case change(RecurringTask)

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }

    var recurringTask: RecurringTask? {
        if case .change(let recurringTask) = self { return recurringTask }
        return nil
    }
}

// Which secondary editor should open automatically when the form appears.
// This is used when the user taps a specific affordance from the recurringTask list.
enum RecurringTaskFormFocus: Equatable {
    case frequency
    case price
    case lockout
    case reminders
    case tags
}

// Captures the draft values from a dismissed new-recurringTask form so callers can
// decide how to handle user-authored content before it is discarded.
struct RecurringTaskFormSnapshot {
    let name: String
    let description: String
    let frequency: Double?
    let lockoutDurationSeconds: Int?
    let basePrice: Int
    var timerSelection: EntityTimerSelection = .none
    let reminderDrafts: [ReminderDraft]
    let recurringTaskId: RecordID
    let tagIDs: [RecordID]
}

struct RecurringTaskFormView: View {
    let mode: RecurringTaskFormMode
    let initialFocus: RecurringTaskFormFocus?
    let prefill: RecurringTaskFormSnapshot?
    let onCreated: ((RecurringTask) -> Void)?
    let onDiscard: ((RecurringTaskFormSnapshot) -> Void)?
    let onDelete: ((RecurringTask) -> Void)?
    let onDuplicate: ((RecurringTask) -> Void)?

    @Environment(\.bochiTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerStore.self) private var timerStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @State private var draft = RecurringTaskFormDraft()

    @State private var showingFrequency = false
    @State private var showingPrice = false
    @State private var showingLockout = false
    @State private var showingReminders = false
    @State private var showingTags = false
    @State private var showingTimer = false
    @State private var tradingRecurringTaskRoute: RecurringTaskTradeRoute? = nil
    @State private var showingHistory = false
    @State private var showingDeleteConfirmation = false
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var actionWarningReason: EntityActionGateReason? = nil

    @State private var hasInitialized = false
    @State private var hasAppliedInitialLoad = false
    @State private var didPersist = false
    @FocusState private var focusedField: FieldFocus?

    enum FieldFocus: Hashable {
        case name
        case description
    }

    private var recurringTaskTags: [Tag] {
        tagStore.tagsForRecurringTask(recurringTaskId: recurringTaskID)
    }

    private var recurringTaskTagIDs: [RecordID] {
        recurringTaskTags
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
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

    private var isNewMode: Bool {
        mode.isNew
    }

    private var showsTradeButton: Bool {
        !isNewMode
    }

    private var draftRecurringTask: RecurringTask {
        draft.recurringTask(existingRecurringTask: currentRecurringTask ?? mode.recurringTask)
    }

    private var isLocked: Bool {
        RecurringTaskLockout.isLocked(recurringTask: draftRecurringTask, tradeStore: tradeStore, hasPremiumAccess: hasPremiumAccess)
    }

    private var lockoutSummary: String? {
        guard let remainingSeconds = RecurringTaskLockout.remainingSeconds(
            recurringTask: draftRecurringTask,
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
            isHidden: currentRecurringTask?.hidden ?? false
        )
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: draft.description,
            frequency: draft.frequency,
            lockoutDurationSeconds: draft.lockoutDurationSeconds,
            basePrice: basePrice,
            reminderCount: activeReminderDrafts.count,
            tagCount: recurringTaskTags.count,
            isFirstRecurringTask: false
        )
    }

    private var currentPrice: Int {
        let completionDates = tradeStore.recurringTaskTradeDates(recurringTaskId: draftRecurringTask.id)
        return RecurringTaskPriceCalculator.calculatePrice(
            recurringTask: draftRecurringTask,
            allRecurringTasks: recurringTaskStore.activeRecurringTasks,
            completionDates: completionDates
        )
    }

    private var lastCompletedAt: Date? {
        guard !isNewMode else { return nil }
        return tradeStore.recurringTaskTradeDates(recurringTaskId: draftRecurringTask.id).max()
    }

    init(
        mode: RecurringTaskFormMode = .new,
        initialFocus: RecurringTaskFormFocus? = nil,
        prefill: RecurringTaskFormSnapshot? = nil,
        onCreated: ((RecurringTask) -> Void)? = nil,
        onDiscard: ((RecurringTaskFormSnapshot) -> Void)? = nil,
        onDelete: ((RecurringTask) -> Void)? = nil,
        onDuplicate: ((RecurringTask) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onCreated = onCreated
        self.onDiscard = onDiscard
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    private var recurringTaskID: RecordID {
        draft.recurringTaskID
    }

    private var frequency: Double? {
        draft.frequency
    }

    private var lockoutDurationSeconds: Int? {
        draft.lockoutDurationSeconds
    }

    private var basePrice: Int {
        draft.basePrice
    }

    private var timerSelection: EntityTimerSelection {
        draft.timerSelection
    }

    private var reminderDrafts: [ReminderDraft] {
        draft.reminderDrafts
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

    var body: some View {
        NavigationStack {
            editorContent
                .entityFormNavigation(
                    title: isNewMode ? "New Recurring Task" : "Edit Recurring Task",
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
            RecurringTaskFrequencyModal(frequency: $draft.frequency)
        }
        .sheet(isPresented: $showingPrice) {
            BasePriceModalView(price: $draft.basePrice, helperSeed: 100.0)
        }
        .sheet(isPresented: $showingLockout) {
            RecurringTaskLockoutDurationModal(durationSeconds: $draft.lockoutDurationSeconds)
        }
        .sheet(isPresented: $showingReminders) {
            ReminderModalView(
                reminders: $draft.reminderDrafts,
                dueDate: nil,
                referenceDate: reminderStore.referenceDate
            )
        }
        .sheet(isPresented: $showingTags) {
            TagsView(assignmentTarget: .recurringTask(recurringTaskID), shouldNotifySync: true)
        }
        .sheet(isPresented: $showingTimer) {
            TimerModalView(
                selection: $draft.timerSelection,
                durationSeconds: nil,
                allowsDurationTimer: false
            )
        }
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
        .sheet(item: $tradingRecurringTaskRoute) { route in
            TradeModalView(
                recurringTask: route.recurringTask,
                quote: route.quote,
                allowsRestrictedClaim: route.allowsRestrictedClaim
            )
        }
        .sheet(item: $actionWarningReason) { reason in
            EntityActionWarningModalView(
                entityName: currentRecurringTask?.name ?? draftRecurringTask.name,
                actionTitle: "Complete Task",
                reason: reason,
                onCancel: { actionWarningReason = nil },
                onConfirm: {
                    actionWarningReason = nil
                    openTradeModal(allowsRestrictedClaim: true)
                }
            )
        }
        .sheet(isPresented: $showingHistory) {
            TradeHistorySheetView(
                filter: .recurringTask(draftRecurringTask.id),
                detents: [.large]
            )
        }
        .entityDeleteConfirmation(
            entityName: "Recurring Task",
            isPresented: $showingDeleteConfirmation,
            item: currentRecurringTask,
            onDelete: deleteRecurringTask
        )
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
            tags: recurringTaskTags,
            activitySummary: lastCompletedAt.map { RecentActivitySummary.text(prefix: "Last completed", date: $0) },
            bottomSpacerHeight: isNewMode || showsTradeButton ? 94 : 16,
            onTagsTapped: { showingTags = true },
            switcher: {
                EntityFormStaticTraitBadges(entity: "task", cadence: "recurring")
            },
            textFields: { textFieldsSection },
            extraContent: { EmptyView() },
            floatingControls: { floatingControls }
        )
    }

    @ViewBuilder
    private var editMenuContent: some View {
        if let recurringTask = currentRecurringTask {
            EntityFormEditMenu(
                entityName: "Recurring Task",
                onDuplicate: { duplicateRecurringTask(recurringTask) },
                onToggleHidden: {
                    recurringTaskStore.setHidden(id: recurringTask.id, hidden: !recurringTask.hidden)
                },
                isHidden: recurringTask.hidden,
                onHistory: { showingHistory = true },
                onDelete: { showingDeleteConfirmation = true }
            )
        }
    }

    private var currentRecurringTask: RecurringTask? {
        guard case .change(let recurringTask) = mode else { return nil }
        return recurringTaskStore.recurringTasks.first(where: { $0.id == recurringTask.id }) ?? recurringTask
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
                    entityName: "Recurring Task",
                    isEnabled: !trimmedName.isEmpty,
                    action: commitForm
                )
            } else if showsTradeButton {
                tradeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tradeButton: some View {
        let gateReason = actionGateReason

        return BochiActionButton(
            amount: currentPrice,
            polarity: .earning,
            layout: .expanded(title: EntityActionGateSupport.actionTitle(defaultTitle: "Complete Task", reason: gateReason)),
            usesMainThemeStyle: gateReason != nil,
            themeRoleOverride: .recurringTask,
            priceDeltaPercent: PriceDeltaSupport.percent(currentPrice: currentPrice, basePrice: basePrice)
        ) {
            if let gateReason {
                actionWarningReason = gateReason
                return
            }

            openTradeModal(allowsRestrictedClaim: false)
        }
    }

    private func openTradeModal(allowsRestrictedClaim: Bool) {
        if !allowsRestrictedClaim {
            guard !RecurringTaskLockout.isLocked(
                recurringTask: draftRecurringTask,
                tradeStore: tradeStore,
                hasPremiumAccess: hasPremiumAccess
            ) else { return }
        }
        guard let persistedRecurringTask = persistRecurringTask() else { return }
        didPersist = true
        tradingRecurringTaskRoute = RecurringTaskTradeRoute(
            recurringTask: persistedRecurringTask,
            allowsRestrictedClaim: allowsRestrictedClaim
        )
    }

    static func hasContent(
        name: String,
        description: String,
        frequency: Double?,
        lockoutDurationSeconds: Int?,
        basePrice: Int,
        reminderCount: Int,
        tagCount: Int,
        isFirstRecurringTask: Bool = false
    ) -> Bool {
        EntityFormSupport.hasRecoverableContent(
            name: name,
            description: description,
            primaryValueIsSet: frequency != nil,
            secondaryValueIsSet: basePrice != 100,
            tagCount: tagCount,
            ignoreSecondaryValue: isFirstRecurringTask
        ) || lockoutDurationSeconds != nil
            || reminderCount > 0
    }

    static func nameForAutoSave(_ name: String) -> String {
        EntityFormSupport.trimmedName(name)
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        basePrice: Int,
        frequency: Double?,
        lockoutDurationSeconds: Int?,
        reminderSummary: String,
        hasReminders: Bool,
        reminderIsPremiumLocked: Bool = false,
        lockoutIsPremiumLocked: Bool = false,
        timerIsPremiumLocked: Bool = false
    ) -> [EntityFormPillConfig] {
        buildPricePillData(
            basePrice: basePrice,
            frequency: frequency
        ) + buildNonPricePillData(
            hasTagsApplied: hasTagsApplied,
            lockoutDurationSeconds: lockoutDurationSeconds,
            reminderSummary: reminderSummary,
            hasReminders: hasReminders,
            reminderIsPremiumLocked: reminderIsPremiumLocked,
            lockoutIsPremiumLocked: lockoutIsPremiumLocked,
            timerIsPremiumLocked: timerIsPremiumLocked
        )
    }

    static func buildPricePillData(
        basePrice: Int?,
        frequency: Double?,
        priceRequiresAttention: Bool = false
    ) -> [EntityFormPillConfig] {
        let frequencyLabel = FrequencyConversion.formatSummary(frequency).map { "Min \($0)" } ?? "Min Frequency"
        return [
            EntityFormPillConfig(
                id: "price",
                label: basePrice.map(String.init) ?? "Base Price",
                icon: "cube",
                isSet: basePrice != nil,
                requiresAttention: priceRequiresAttention
            ),
            EntityFormPillConfig(id: "frequency", label: frequencyLabel, icon: "clock", isSet: frequency != nil)
        ]
    }

    static func buildNonPricePillData(
        hasTagsApplied: Bool,
        timerLabel: String = "Timer",
        hasTimer: Bool = false,
        lockoutDurationSeconds: Int?,
        reminderSummary: String,
        hasReminders: Bool,
        reminderIsPremiumLocked: Bool = false,
        lockoutIsPremiumLocked: Bool = false,
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
                id: "reminders",
                label: reminderSummary,
                icon: "bell",
                isSet: hasReminders,
                isPremiumLocked: reminderIsPremiumLocked
            ),
            EntityFormPillConfig(
                id: "lockout",
                label: lockoutLabel,
                icon: "lock",
                isSet: lockoutDurationSeconds != nil,
                isPremiumLocked: lockoutIsPremiumLocked
            )
        ]
    }

    private func buildPricePills() -> [PillItem] {
        let configs = Self.buildPricePillData(
            basePrice: basePrice,
            frequency: frequency
        )
        return EntityFormSupport.buildPills(
            configs: configs,
            actions: pillActions
        )
    }

    private func buildNonPricePills() -> [PillItem] {
        let configs = Self.buildNonPricePillData(
            hasTagsApplied: !recurringTaskTags.isEmpty,
            timerLabel: timerPillLabel,
            hasTimer: resolvedTimerSelection != .none,
            lockoutDurationSeconds: lockoutDurationSeconds,
            reminderSummary: ReminderDraftSupport.summary(for: reminderDrafts, now: reminderStore.referenceDate),
            hasReminders: !activeReminderDrafts.isEmpty,
            reminderIsPremiumLocked: !hasPremiumAccess,
            lockoutIsPremiumLocked: !hasPremiumAccess,
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
            "frequency": { showingFrequency = true },
            "reminders": { openRemindersOrPremiumUpsell() },
            "timer": { openTimerOrPremiumUpsell() },
            "lockout": { openLockoutOrPremiumUpsell() }
        ]
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, mode.isNew {
            draft = RecurringTaskFormDraft(prefill: prefill)
        } else if case .change(let recurringTask) = mode {
            draft = RecurringTaskFormDraft(
                recurringTask: recurringTask,
                reminderDrafts: reminderStore.reminderDrafts(for: .recurringTask(recurringTask.id))
            )
        }

        hasAppliedInitialLoad = true

        guard let initialFocus else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch initialFocus {
            case .frequency:
                showingFrequency = true
            case .price:
                showingPrice = true
            case .lockout:
                openLockoutOrPremiumUpsell()
            case .reminders:
                openRemindersOrPremiumUpsell()
            case .tags:
                showingTags = true
            }
        }
    }

    private func autoSaveIfNeeded() {
        guard !isNewMode, hasAppliedInitialLoad else { return }
        _ = persistRecurringTask()
    }

    private func commitForm() {
        if isNewMode {
            guard !trimmedName.isEmpty else { return }
            guard let recurringTask = persistRecurringTask() else { return }
            didPersist = true
            onCreated?(recurringTask)
        } else {
            didPersist = true
            _ = persistRecurringTask()
        }
        dismiss()
    }

    private func duplicateRecurringTask(_ recurringTask: RecurringTask) {
        dismiss()
        onDuplicate?(recurringTask)
    }

    private func deleteRecurringTask(_ recurringTask: RecurringTask) {
        dismiss()
        if let onDelete {
            onDelete(recurringTask)
            return
        }

        EntityDeletionService.deleteRecurringTask(
            recurringTask,
            reminderStore: reminderStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore
        )
    }

    private func discardDraft() {
        onDiscard?(draft.snapshot(tagIDs: recurringTaskTagIDs))
    }

    @discardableResult
    private func persistRecurringTask() -> RecurringTask? {
        if case .new = mode {
            let recurringTask = recurringTaskStore.addRecurringTask(
                id: draft.recurringTaskID,
                name: draft.name,
                description: draft.description,
                frequency: draft.frequency,
                lockoutDurationSeconds: draft.lockoutDurationSeconds,
                basePrice: draft.basePrice,
                timerSelection: draft.timerSelection
            )
            if recurringTask != nil {
                reminderStore.replaceReminders(for: .recurringTask(draft.recurringTaskID), with: draft.reminderDrafts)
            }
            return recurringTask
        }

        recurringTaskStore.updateRecurringTask(
            id: draft.recurringTaskID,
            name: Self.nameForAutoSave(draft.name),
            description: draft.description,
            frequency: .some(draft.frequency),
            lockoutDurationSeconds: .some(draft.lockoutDurationSeconds),
            basePrice: draft.basePrice,
            timerSelection: draft.timerSelection
        )
        reminderStore.replaceReminders(for: .recurringTask(draft.recurringTaskID), with: draft.reminderDrafts)

        return draftRecurringTask
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    private func openRemindersOrPremiumUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .reminders
            return
        }

        showingReminders = true
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

#Preview("New Recurring Task") {
    RecurringTaskFormView(mode: .new)
        .environment(RecurringTaskStore())
        .environment(TaskDependencyStore())
        .environment(RewardDependencyStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
}
