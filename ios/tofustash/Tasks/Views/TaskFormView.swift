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

    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(TagStore.self) private var tagStore

    @State private var draftTaskID: RecordID
    @State private var name: String
    @State private var description: String
    @State private var difficultyTier: HabitDifficultyTier?
    @State private var durationSeconds: Int?
    @State private var skipConsequence: Int?
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var completedAt: Date?
    @State private var showingTags = false
    @State private var showingDeleteConfirmation = false

    init(task: TaskItem?) {
        self.task = task
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

    var body: some View {
        NavigationStack {
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
            .navigationTitle(isNewMode ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .sheet(isPresented: $showingTags) {
                TagsView(selectionMode: .assignment(.task(taskID)))
            }
            .alert("Delete Task?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    taskStore.deleteTask(id: taskID)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func persistTask() {
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

        dismiss()
    }
}

#Preview {
    TaskFormView(task: nil)
        .environment(TaskStore())
        .environment(TagStore())
}
