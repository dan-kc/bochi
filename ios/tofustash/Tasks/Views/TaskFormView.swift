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
    case difficulty
    case duration
    case dueDate
    case reminders
    case skipConsequence
    case tags
}

struct TaskFormSnapshot {
    let name: String
    let description: String
    let difficultyTier: HabitDifficultyTier?
    let durationSeconds: Int?
    let skipConsequence: Int?
    let dueDate: Date?
    let reminderDrafts: [ReminderDraft]
    let taskId: RecordID
}

private enum TaskDependencyEditorRoute: Identifiable {
    case task(TaskItem)
    case habit(Habit)

    var id: String {
        switch self {
        case .task(let task):
            return "task:\(task.id.rawValue)"
        case .habit(let habit):
            return "habit:\(habit.id.rawValue)"
        }
    }
}

private struct HabitDependencyCountEditorRoute: Identifiable {
    let habit: Habit
    let existingDependency: TaskHabitDependency?

    var id: RecordID { habit.id }
}

struct TaskFormView: View {
    let mode: TaskFormMode
    let initialFocus: TaskFormFocus?
    let prefill: TaskFormSnapshot?
    let onDiscard: ((TaskFormSnapshot) -> Void)?
    let onDelete: ((TaskItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore

    @State private var taskID = RecordID()
    @State private var name = ""
    @State private var description = ""
    @State private var difficultyTier: HabitDifficultyTier? = nil
    @State private var durationSeconds: Int? = nil
    @State private var skipConsequence: Int? = nil
    @State private var dueDate: Date? = nil
    @State private var completedAt: Date? = nil
    @State private var reminderDrafts: [ReminderDraft] = []
    @State private var taskDependencies: [TaskTaskDependency] = []
    @State private var habitDependencies: [TaskHabitDependency] = []

    @State private var showingTags = false
    @State private var showingReminders = false
    @State private var showingDifficulty = false
    @State private var showingDuration = false
    @State private var showingSkipConsequence = false
    @State private var showingDueDate = false
    @State private var showingDependencyPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBlockedTaskAlert = false
    @State private var claimed = false
    @State private var claimedAmount = 0
    @State private var dependencyEditorRoute: TaskDependencyEditorRoute? = nil
    @State private var habitDependencyCountRoute: HabitDependencyCountEditorRoute? = nil
    @State private var dependencyTradeHabit: Habit? = nil

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
        onDiscard: ((TaskFormSnapshot) -> Void)? = nil,
        onDelete: ((TaskItem) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onDiscard = onDiscard
        self.onDelete = onDelete
    }

    private var isNewMode: Bool {
        mode.isNew
    }

    private var isCompleted: Bool {
        completedAt != nil
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    private var taskTags: [Tag] {
        tagStore.tagsForTask(taskId: taskID)
    }

    private var activeReminderDrafts: [ReminderDraft] {
        ReminderDraftSupport.active(reminderDrafts, now: reminderStore.referenceDate)
    }

    private var trimmedName: String {
        EntityFormSupport.trimmedName(name)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftTask: TaskItem {
        let existingTask = mode.task
        let persistedName = trimmedName.isEmpty ? (existingTask?.name ?? "Task") : trimmedName

        return TaskItem(
            id: taskID,
            name: persistedName,
            description: description,
            createdAt: existingTask?.createdAt ?? Date(),
            updatedAt: Date(),
            deletedAt: existingTask?.deletedAt,
            completedAt: completedAt,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            skipConsequence: skipConsequence,
            dueDate: dueDate
        )
    }

    private var rewardPreview: Int {
        TaskRewardCalculation.calculateReward(task: draftTask)
    }

    private var activeTaskDependencies: [TaskTaskDependency] {
        taskDependencies.filter { $0.deletedAt == nil }
    }

    private var activeHabitDependencies: [TaskHabitDependency] {
        habitDependencies.filter { $0.deletedAt == nil }
    }

    private var isBlocked: Bool {
        taskDependencyStore.isTaskBlocked(draftTask, taskStore: taskStore, tradeStore: tradeStore)
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: trimmedDescription,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            skipConsequence: skipConsequence,
            dueDate: dueDate,
            reminderCount: activeReminderDrafts.count,
            tagCount: taskTags.count
        )
    }

    private var showsCompleteButton: Bool {
        !isNewMode && !isCompleted && !claimed
    }

    private var refundableTaskTrade: Trade? {
        tradeStore.latestTaskTrade(taskId: taskID, includeRefunded: false)
    }

    private var refundPreviewAmount: Int {
        refundableTaskTrade.map { abs($0.amount) } ?? rewardPreview
    }

    private var showsRefundButton: Bool {
        !isNewMode && isCompleted && !claimed && refundableTaskTrade != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if claimed {
                    ClaimCelebrationView(amount: claimedAmount) {
                        dismiss()
                    }
                    .transition(.opacity)
                } else {
                    editorContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: claimed)
            .navigationTitle(claimed ? "" : (isNewMode ? "New Task" : "Edit Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !claimed {
                    ToolbarItem(placement: .cancellationAction) {
                        if isNewMode {
                            Button("Cancel") {
                                dismiss()
                            }
                        } else if mode.task != nil {
                            Menu {
                                Button("Delete Task", role: .destructive) {
                                    showingDeleteConfirmation = true
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityIdentifier("task.form.menu")
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(isEditingText ? "Done" : (isNewMode ? "Add" : "Done")) {
                            if isEditingText {
                                focusedField = nil
                                return
                            }

                            if isNewMode {
                                guard !trimmedName.isEmpty else { return }
                                guard persistTask() else { return }
                                didPersist = true
                            }

                            dismiss()
                        }
                        .disabled(!isEditingText && isNewMode && trimmedName.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.18), value: isEditingText)
        .sheet(isPresented: $showingDifficulty) {
            TierSelectionSheet(
                title: "Set Difficulty",
                currentSelection: difficultyTier,
                onSave: { difficultyTier = $0 },
                onUnset: difficultyTier != nil ? { difficultyTier = nil } : nil
            )
        }
        .sheet(isPresented: $showingDuration) {
            HabitDurationModal(durationSeconds: $durationSeconds)
        }
        .sheet(isPresented: $showingSkipConsequence) {
            TierSelectionSheet(
                title: "Set Skip Consequence",
                currentSelection: SkipConsequenceTier.from(skipConsequence),
                onSave: { skipConsequence = $0?.rawValue },
                onUnset: skipConsequence != nil ? { skipConsequence = nil } : nil
            )
        }
        .sheet(isPresented: $showingDueDate) {
            TaskDueDateModal(dueDate: $dueDate)
        }
        .sheet(isPresented: $showingReminders) {
            ReminderModalView(
                reminders: $reminderDrafts,
                dueDate: dueDate,
                referenceDate: reminderStore.referenceDate
            )
        }
        .sheet(isPresented: $showingTags) {
            TagsView(selectionMode: .assignment(.task(taskID)))
        }
        .sheet(isPresented: $showingDependencyPicker) {
            TaskDependencyPickerView(
                taskID: taskID,
                selectedTaskDependencyIDs: Set(activeTaskDependencies.map(\.dependsOnTaskId)),
                selectedHabitDependencyIDs: Set(activeHabitDependencies.map(\.habitId)),
                canSelectTask: { candidateTask in
                    !wouldCreateTaskDependencyCycle(dependsOnTaskID: candidateTask.id)
                },
                onSelectTask: { selectedTask in
                    addTaskDependency(selectedTask)
                },
                onSelectHabit: { selectedHabit in
                    habitDependencyCountRoute = HabitDependencyCountEditorRoute(
                        habit: selectedHabit,
                        existingDependency: activeHabitDependencies.first(where: { $0.habitId == selectedHabit.id })
                    )
                }
            )
        }
        .sheet(item: $dependencyEditorRoute) { route in
            switch route {
            case .task(let task):
                TaskFormView(mode: .change(task))
            case .habit(let habit):
                HabitFormView(mode: .change(habit))
            }
        }
        .sheet(item: $habitDependencyCountRoute) { route in
            HabitDependencyCountEditorView(
                habitName: route.habit.name,
                initialRequiredCompletions: route.existingDependency?.requiredCompletions ?? 1,
                onSave: { requiredCompletions in
                    saveHabitDependency(route: route, requiredCompletions: requiredCompletions)
                }
            )
        }
        .sheet(item: $dependencyTradeHabit) { habit in
            TradeModalView(habit: habit)
        }
        .alert("Delete Task?", isPresented: $showingDeleteConfirmation) {
            if let task = mode.task {
                Button("Delete", role: .destructive) {
                    dismiss()
                    onDelete?(task)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Task Blocked", isPresented: $showingBlockedTaskAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This task cannot be completed until its dependencies are finished.")
        }
        .task {
            initializeIfNeeded()
        }
        .onChange(of: name) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: description) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: difficultyTier) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: durationSeconds) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: skipConsequence) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: dueDate) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: reminderDrafts) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: taskDependencies) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: habitDependencies) { _, _ in
            autoSaveIfNeeded()
        }
        .onDisappear {
            if isNewMode && !didPersist && hasContent {
                onDiscard?(TaskFormSnapshot(
                    name: name,
                    description: description,
                    difficultyTier: difficultyTier,
                    durationSeconds: durationSeconds,
                    skipConsequence: skipConsequence,
                    dueDate: dueDate,
                    reminderDrafts: reminderDrafts,
                    taskId: taskID
                ))
            }
        }
    }

    private var editorContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    textFieldsSection
                        .padding(.horizontal, 16)

                    if !taskTags.isEmpty {
                        TagPillsRow(tags: taskTags, size: .form, leadingInset: 16)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showingTags = true
                            }
                            .opacity(isEditingText ? 0 : 1)
                            .allowsHitTesting(!isEditingText)
                    }

                    PillRow(pills: buildPills(), leadingInset: 16, trailingInset: 16)
                        .opacity(isEditingText ? 0 : 1)
                        .allowsHitTesting(!isEditingText)

                    if !isNewMode {
                        dependenciesSection
                            .padding(.horizontal, 16)
                            .opacity(isEditingText ? 0 : 1)
                            .allowsHitTesting(!isEditingText)
                    }

                    if let completedAt, isCompleted {
                        Text("Completed \(completedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .opacity(isEditingText ? 0 : 1)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear.frame(height: (showsCompleteButton || showsRefundButton) ? 94 : 16)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            floatingControls
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .opacity(isEditingText ? 0 : 1)
                .allowsHitTesting(!isEditingText)
        }
    }

    private var textFieldsSection: some View {
        EntityFormTextFieldsSection(
            name: $name,
            description: $description,
            focusedField: $focusedField,
            nameFocus: .name,
            descriptionFocus: .description
        )
    }

    private var floatingControls: some View {
        VStack(spacing: 10) {
            if showsCompleteButton {
                TofuActionButton(amount: rewardPreview, polarity: .earning, layout: .expanded(title: "Complete Task")) {
                    completeTaskFromForm()
                }
                .accessibilityIdentifier("task.complete")
            } else if showsRefundButton {
                TofuActionButton(amount: refundPreviewAmount, polarity: .spending, layout: .expanded(title: "Refund Task")) {
                    refundCompletedTaskFromForm()
                }
                .accessibilityIdentifier("task.refund")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dependencies")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    showingDependencyPicker = true
                }
                .accessibilityIdentifier("task-dependencies.add")
            }

            if activeTaskDependencies.isEmpty && activeHabitDependencies.isEmpty {
                Text("Add tasks or habits that must be completed first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(activeTaskDependencies) { dependency in
                        taskDependencyRow(dependency)
                    }

                    ForEach(activeHabitDependencies) { dependency in
                        habitDependencyRow(dependency)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskDependencyRow(_ dependency: TaskTaskDependency) -> some View {
        if let prerequisiteTask = taskStore.tasks.first(where: { $0.id == dependency.dependsOnTaskId && $0.deletedAt == nil }) {
            let isComplete = prerequisiteTask.completedAt != nil

            HStack(spacing: 12) {
                Button {
                    dependencyEditorRoute = .task(prerequisiteTask)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prerequisiteTask.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .strikethrough(isComplete)

                        Text(isComplete ? "Completed task" : "Complete this task first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if !isComplete {
                    Button("Complete") {
                        completeDependencyTask(prerequisiteTask)
                    }
                    .buttonStyle(.bordered)
                }

                dependencyMenu(
                    canEditCount: false,
                    onEditCount: nil,
                    onRemove: { removeTaskDependency(dependency) }
                )

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? .secondary : .tertiary)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isComplete ? 0.6 : 1)
        }
    }

    @ViewBuilder
    private func habitDependencyRow(_ dependency: TaskHabitDependency) -> some View {
        if let habit = habitStore.habits.first(where: { $0.id == dependency.habitId && $0.deletedAt == nil }) {
            let progress = taskDependencyStore.habitDependencyProgress(for: dependency, tradeStore: tradeStore)
            let isComplete = progress >= dependency.requiredCompletions

            HStack(spacing: 12) {
                Button {
                    dependencyEditorRoute = .habit(habit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .strikethrough(isComplete)

                        Text(
                            isComplete
                            ? "Completed habit dependency"
                            : "\(min(progress, dependency.requiredCompletions))/\(dependency.requiredCompletions) more completions"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if !isComplete {
                    Button("Claim") {
                        dependencyTradeHabit = habit
                    }
                    .buttonStyle(.bordered)
                }

                dependencyMenu(
                    canEditCount: true,
                    onEditCount: {
                        habitDependencyCountRoute = HabitDependencyCountEditorRoute(
                            habit: habit,
                            existingDependency: dependency
                        )
                    },
                    onRemove: { removeHabitDependency(dependency) }
                )

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? .secondary : .tertiary)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isComplete ? 0.6 : 1)
        }
    }

    private func dependencyMenu(
        canEditCount: Bool,
        onEditCount: (() -> Void)?,
        onRemove: @escaping () -> Void
    ) -> some View {
        Menu {
            if canEditCount, let onEditCount {
                Button("Edit Count") {
                    onEditCount()
                }
            }

            Button("Remove Dependency", role: .destructive) {
                onRemove()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
    }

    static func hasContent(
        name: String,
        description: String,
        difficultyTier: HabitDifficultyTier?,
        durationSeconds: Int?,
        skipConsequence: Int?,
        dueDate: Date?,
        reminderCount: Int,
        tagCount: Int
    ) -> Bool {
        !name.isEmpty
            || !description.isEmpty
            || difficultyTier != nil
            || durationSeconds != nil
            || skipConsequence != nil
            || dueDate != nil
            || reminderCount > 0
            || tagCount > 0
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        difficultyTier: HabitDifficultyTier?,
        durationSeconds: Int?,
        skipConsequence: Int?,
        dueDate: Date?,
        reminderSummary: String,
        hasReminders: Bool
    ) -> [EntityFormPillConfig] {
        [
            EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            EntityFormPillConfig(id: "difficulty", label: difficultyTier?.displayName ?? "Difficulty", icon: "chart.bar", isSet: difficultyTier != nil),
            EntityFormPillConfig(id: "reminders", label: reminderSummary, icon: "bell", isSet: hasReminders),
            EntityFormPillConfig(id: "duration", label: DurationFormatting.summary(seconds: durationSeconds) ?? "Duration", icon: "timer", isSet: durationSeconds != nil),
            EntityFormPillConfig(id: "dueDate", label: dueDate.map(Self.dueDateSummary) ?? "Due Date", icon: "calendar", isSet: dueDate != nil),
            EntityFormPillConfig(id: "skip", label: SkipConsequenceTier.from(skipConsequence)?.displayName ?? "Skip", icon: "exclamationmark.triangle", isSet: skipConsequence != nil)
        ]
    }

    private func buildPills() -> [PillItem] {
        let configs = Self.buildPillData(
            hasTagsApplied: !taskTags.isEmpty,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            skipConsequence: skipConsequence,
            dueDate: dueDate,
            reminderSummary: ReminderDraftSupport.summary(for: reminderDrafts, now: reminderStore.referenceDate),
            hasReminders: !activeReminderDrafts.isEmpty
        )
        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "difficulty": { showingDifficulty = true },
            "duration": { showingDuration = true },
            "dueDate": { showingDueDate = true },
            "skip": { showingSkipConsequence = true },
            "reminders": { showingReminders = true }
        ]

        return EntityFormSupport.buildPills(configs: configs, actions: actions)
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, isNewMode {
            taskID = prefill.taskId
            name = prefill.name
            description = prefill.description
            difficultyTier = prefill.difficultyTier
            durationSeconds = prefill.durationSeconds
            skipConsequence = prefill.skipConsequence
            dueDate = prefill.dueDate
            reminderDrafts = prefill.reminderDrafts
        } else if let task = mode.task {
            taskID = task.id
            name = task.name
            description = task.description
            difficultyTier = task.difficultyTier
            durationSeconds = task.durationSeconds
            skipConsequence = task.skipConsequence
            dueDate = task.dueDate
            completedAt = task.completedAt
            reminderDrafts = reminderStore.reminderDrafts(for: .task(task.id))
            taskDependencies = taskDependencyStore.activeTaskDependencies(for: task.id)
            habitDependencies = taskDependencyStore.activeHabitDependencies(for: task.id)
        }

        hasAppliedInitialLoad = true

        guard let initialFocus else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch initialFocus {
            case .difficulty:
                showingDifficulty = true
            case .duration:
                showingDuration = true
            case .dueDate:
                showingDueDate = true
            case .reminders:
                showingReminders = true
            case .skipConsequence:
                showingSkipConsequence = true
            case .tags:
                showingTags = true
            }
        }
    }

    private func autoSaveIfNeeded() {
        guard !isNewMode, hasAppliedInitialLoad else { return }
        _ = persistTask()
    }

    @discardableResult
    private func persistTask() -> Bool {
        TaskFormPersistenceSupport.persistTask(
            task: mode.task,
            taskID: taskID,
            name: name,
            description: description,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            skipConsequence: skipConsequence,
            dueDate: dueDate,
            completedAt: completedAt,
            reminderDrafts: reminderDrafts,
            taskDependencies: taskDependencies,
            habitDependencies: habitDependencies,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            reminderStore: reminderStore
        )
    }

    private func completeTaskFromForm() {
        guard !isNewMode, !isCompleted else { return }
        guard persistTask() else { return }
        guard !taskDependencyStore.isTaskBlocked(draftTask, taskStore: taskStore, tradeStore: tradeStore) else {
            showingBlockedTaskAlert = true
            return
        }

        completedAt = TaskCompletionSupport.completeTask(
            taskID: taskID,
            sourceName: draftTask.name,
            reward: rewardPreview,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
        didPersist = true
        claimedAmount = rewardPreview
        claimed = true
    }

    private func refundCompletedTaskFromForm() {
        guard let trade = refundableTaskTrade else { return }

        TradeRefundService.setRefunded(
            true,
            for: trade,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
        completedAt = nil
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
        guard !taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore) else {
            showingBlockedTaskAlert = true
            return
        }

        _ = TaskCompletionSupport.completeTask(
            taskID: task.id,
            sourceName: task.name,
            reward: TaskRewardCalculation.calculateReward(task: task),
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
    }

    private func addTaskDependency(_ selectedTask: TaskItem) {
        let now = Date()
        let dependency = TaskTaskDependency(
            taskId: taskID,
            dependsOnTaskId: selectedTask.id,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        taskDependencies = OwnerScopedRecordSupport.mergeRecords(local: taskDependencies, remote: [dependency])
    }

    private func saveHabitDependency(
        route: HabitDependencyCountEditorRoute,
        requiredCompletions: Int
    ) {
        let existing = route.existingDependency
        let updatedAt = nextDependencyUpdateTimestamp(after: existing?.updatedAt)
        let dependency = TaskHabitDependency(
            taskId: taskID,
            habitId: route.habit.id,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: tradeStore.habitCompletionCount(habitId: route.habit.id),
            createdAt: existing?.createdAt ?? updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil
        )
        habitDependencies = OwnerScopedRecordSupport.mergeRecords(local: habitDependencies, remote: [dependency])
        showingDependencyPicker = false
    }

    private func removeTaskDependency(_ dependency: TaskTaskDependency) {
        taskDependencies.removeAll { $0.id == dependency.id }
    }

    private func removeHabitDependency(_ dependency: TaskHabitDependency) {
        habitDependencies.removeAll { $0.id == dependency.id }
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

    private func nextDependencyUpdateTimestamp(after existingUpdatedAt: Date?) -> Date {
        let now = Date()
        guard let existingUpdatedAt else { return now }
        return now > existingUpdatedAt ? now : existingUpdatedAt.addingTimeInterval(0.001)
    }
}

#Preview("New Task") {
    let taskStore = TaskStore()
    let habitStore = HabitStore()
    TaskFormView(mode: .new)
        .environment(taskStore)
        .environment(TaskDependencyStore())
        .environment(habitStore)
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(ReminderStore(
            taskStore: taskStore,
            habitStore: habitStore,
            notificationScheduler: NoOpReminderNotificationScheduler()
        ))
}

private struct TaskDependencyPickerView: View {
    let taskID: RecordID
    let selectedTaskDependencyIDs: Set<RecordID>
    let selectedHabitDependencyIDs: Set<RecordID>
    let canSelectTask: (TaskItem) -> Bool
    let onSelectTask: (TaskItem) -> Void
    let onSelectHabit: (Habit) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(HabitStore.self) private var habitStore

    private var availableTasks: [TaskItem] {
        taskStore.tasks.filter {
            $0.id != taskID
                && $0.deletedAt == nil
                && !selectedTaskDependencyIDs.contains($0.id)
                && canSelectTask($0)
        }
    }

    private var availableHabits: [Habit] {
        habitStore.activeHabits.filter { !selectedHabitDependencyIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Tasks") {
                    if availableTasks.isEmpty {
                        Text("No available task dependencies")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableTasks) { task in
                            Button(task.name) {
                                onSelectTask(task)
                                dismiss()
                            }
                        }
                    }
                }

                Section("Habits") {
                    if availableHabits.isEmpty {
                        Text("No available habit dependencies")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableHabits) { habit in
                            Button(habit.name) {
                                onSelectHabit(habit)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Dependency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HabitDependencyCountEditorView: View {
    let habitName: String
    let initialRequiredCompletions: Int
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var requiredCompletions: Int

    init(
        habitName: String,
        initialRequiredCompletions: Int,
        onSave: @escaping (Int) -> Void
    ) {
        self.habitName = habitName
        self.initialRequiredCompletions = initialRequiredCompletions
        self.onSave = onSave
        _requiredCompletions = State(initialValue: initialRequiredCompletions)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(habitName) {
                    Stepper(value: $requiredCompletions, in: 1...999) {
                        Text("\(requiredCompletions) more completions")
                    }
                }
            }
            .navigationTitle("Required Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(requiredCompletions)
                        dismiss()
                    }
                }
            }
        }
    }
}
