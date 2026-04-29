import SwiftUI

struct TaskFormView: View {
    private static let durationOptions: [(label: String, value: Int?)] = [
        ("Not set", nil),
        ("5 min", 300),
        ("15 min", 900),
        ("30 min", 1_800),
        ("1 hour", 3_600),
        ("2 hours", 7_200)
    ]

    let task: TaskItem?
    let onTaskCompleted: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore

    @State private var draftTaskID: RecordID
    @State private var name: String
    @State private var description: String
    @State private var difficultyTier: HabitDifficultyTier?
    @State private var durationSeconds: Int?
    @State private var skipConsequence: Int?
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var completedAt: Date?
    @State private var reminderDrafts: [ReminderDraft] = []
    @State private var showingTags = false
    @State private var showingReminders = false
    @State private var showingDeleteConfirmation = false
    @State private var claimed = false
    @State private var claimedAmount = 0
    @State private var clearedReminderCountAfterClaim = 0

    init(task: TaskItem?, onTaskCompleted: ((Int) -> Void)? = nil) {
        self.task = task
        self.onTaskCompleted = onTaskCompleted
        _draftTaskID = State(initialValue: task?.id ?? RecordID())
        _name = State(initialValue: task?.name ?? "")
        _description = State(initialValue: task?.description ?? "")
        _difficultyTier = State(initialValue: task?.difficultyTier)
        _durationSeconds = State(initialValue: task?.durationSeconds)
        _skipConsequence = State(initialValue: task?.skipConsequence)
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? Date())
        _completedAt = State(initialValue: task?.completedAt)
    }

    private var isNewMode: Bool { task == nil }

    private var taskID: RecordID {
        task?.id ?? draftTaskID
    }

    private var rewardPreview: Int {
        TaskRewardCalculation.calculateReward(
            task: TaskItem(
                id: taskID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Task" : name,
                description: description,
                createdAt: task?.createdAt ?? Date(),
                updatedAt: Date(),
                deletedAt: task?.deletedAt,
                completedAt: completedAt,
                difficultyTier: difficultyTier,
                durationSeconds: durationSeconds,
                skipConsequence: skipConsequence,
                dueDate: hasDueDate ? dueDate : nil
            )
        )
    }

    private var existingTags: [Tag] {
        guard !isNewMode else { return [] }
        return tagStore.tagsForTask(taskId: taskID)
    }

    private var activeReminderDrafts: [ReminderDraft] {
        ReminderDraftSupport.active(reminderDrafts, now: reminderStore.referenceDate)
    }

    private var isCompleted: Bool {
        completedAt != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if !claimed {
                    formContent
                        .transition(.opacity)
                }

                if claimed {
                    ClaimCelebrationView(amount: claimedAmount) {
                        dismiss()
                        onTaskCompleted?(clearedReminderCountAfterClaim)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: claimed)
            .navigationTitle(claimed ? "" : (isNewMode ? "New Task" : "Edit Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !claimed {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            persistTask()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingTags) {
                TagsView(selectionMode: .assignment(.task(taskID)))
            }
            .sheet(isPresented: $showingReminders) {
                ReminderModalView(
                    reminders: $reminderDrafts,
                    dueDate: hasDueDate ? dueDate : nil,
                    referenceDate: reminderStore.referenceDate
                )
            }
            .alert("Delete Task?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    reminderStore.deleteAllReminders(for: .task(taskID))
                    taskStore.deleteTask(id: taskID)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .task {
                initializeReminders()
            }
        }
    }

    private var formContent: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Reward") {
                Picker("Difficulty", selection: $difficultyTier) {
                    Text("Not set").tag(HabitDifficultyTier?.none)
                    ForEach(HabitDifficultyTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(HabitDifficultyTier?.some(tier))
                    }
                }

                Picker("Duration", selection: $durationSeconds) {
                    ForEach(Self.durationOptions, id: \.label) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                Picker("Skip Consequence", selection: $skipConsequence) {
                    Text("Not set").tag(Int?.none)
                    ForEach(Array(SkipConsequenceTier.allCases), id: \.self) { tier in
                        Text(tier.displayName).tag(Int?.some(tier.rawValue))
                    }
                }

                HStack {
                    Text("Reward")
                    Spacer()
                    Label("+\(rewardPreview)", systemImage: "cube.fill")
                        .fontWeight(.semibold)
                }
            }

            Section("Schedule") {
                Toggle("Due Date", isOn: $hasDueDate.animation())

                if hasDueDate {
                    DatePicker(
                        "Due",
                        selection: $dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            Section("Reminders") {
                if isCompleted {
                    Text("Reminders are void for completed tasks.")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        showingReminders = true
                    } label: {
                        HStack {
                            Text("Manage Reminders")
                            Spacer()
                            Text(ReminderDraftSupport.summary(for: reminderDrafts, now: reminderStore.referenceDate))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !activeReminderDrafts.isEmpty {
                        ForEach(activeReminderDrafts) { reminder in
                            Text(reminder.scheduledAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Tags") {
                if isNewMode {
                    Text("Save the task before assigning tags.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Manage Tags") {
                        showingTags = true
                    }

                    if !existingTags.isEmpty {
                        TagPillsRow(tags: existingTags, size: .form)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }

            if !isNewMode && !isCompleted {
                Section {
                    TofuActionButton(
                        amount: rewardPreview,
                        polarity: .earning,
                        layout: .expanded(title: "Complete Task")
                    ) {
                        completeTaskFromForm()
                    }
                    .accessibilityIdentifier("task.complete")
                }
            }

            if let completedAt {
                Section("Status") {
                    LabeledContent("Completed", value: completedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                }

                Section {
                    Button("Delete Task", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
    }

    private func persistTask() {
        let didPersist = TaskFormPersistenceSupport.persistTask(
            task: task,
            taskID: taskID,
            name: name,
            description: description,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            skipConsequence: skipConsequence,
            dueDate: hasDueDate ? dueDate : nil,
            completedAt: completedAt,
            reminderDrafts: reminderDrafts,
            taskStore: taskStore,
            reminderStore: reminderStore
        )
        guard didPersist else {
            return
        }
        dismiss()
    }

    private func persistDraftFields() {
        if isNewMode {
            _ = taskStore.addTask(
                id: taskID,
                name: name,
                description: description,
                difficultyTier: difficultyTier,
                durationSeconds: durationSeconds,
                skipConsequence: skipConsequence,
                dueDate: hasDueDate ? dueDate : nil,
                completedAt: completedAt
            )
        } else {
            taskStore.updateTask(
                id: taskID,
                name: name,
                description: description,
                difficultyTier: .some(difficultyTier),
                durationSeconds: .some(durationSeconds),
                skipConsequence: .some(skipConsequence),
                dueDate: .some(hasDueDate ? dueDate : nil),
                completedAt: .some(completedAt)
            )
        }
    }

    private func completeTaskFromForm() {
        guard !isNewMode, !isCompleted else { return }
        let claimDate = Date()

        persistDraftFields()

        let clearedReminderCount = reminderStore.cancelFutureReminders(forTaskID: taskID)
        tradeStore.addTaskTrade(taskId: taskID, amount: rewardPreview, createdAt: claimDate)
        taskStore.completeTask(id: taskID, completedAt: claimDate)
        balanceStore.refresh()

        completedAt = claimDate
        claimedAmount = rewardPreview
        clearedReminderCountAfterClaim = clearedReminderCount
        claimed = true
    }

    private func initializeReminders() {
        reminderDrafts = reminderStore.reminderDrafts(for: .task(taskID))
    }
}

#Preview {
    TaskFormView(task: nil)
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
