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

struct TaskFormView: View {
    let mode: TaskFormMode
    let initialFocus: TaskFormFocus?
    let prefill: TaskFormSnapshot?
    let onDiscard: ((TaskFormSnapshot) -> Void)?
    let onDelete: ((TaskItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
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

    @State private var showingTags = false
    @State private var showingReminders = false
    @State private var showingDifficulty = false
    @State private var showingDuration = false
    @State private var showingSkipConsequence = false
    @State private var showingDueDate = false
    @State private var showingDeleteConfirmation = false
    @State private var claimed = false
    @State private var claimedAmount = 0

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

                    if let completedAt, isCompleted {
                        Text("Completed \(completedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .opacity(isEditingText ? 0 : 1)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear.frame(height: showsCompleteButton ? 94 : 16)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            taskStore: taskStore,
            reminderStore: reminderStore
        )
    }

    private func completeTaskFromForm() {
        guard !isNewMode, !isCompleted else { return }
        guard persistTask() else { return }

        completedAt = TaskCompletionSupport.completeTask(
            taskID: taskID,
            reward: rewardPreview,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
        didPersist = true
        claimedAmount = rewardPreview
        claimed = true
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
}

#Preview("New Task") {
    TaskFormView(mode: .new)
        .environment(TaskStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(ReminderStore(
            taskStore: TaskStore(),
            habitStore: HabitStore(),
            notificationScheduler: NoOpReminderNotificationScheduler()
        ))
}
