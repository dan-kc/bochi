import SwiftUI
import FuzzyMatch

struct DependencyPickerView: View {
    @Environment(\.bochiTheme) private var theme
    private enum DependencyFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case tasks = "Tasks"
        case recurringTasks = "Recurring"

        var id: Self { self }
    }

    let excludedTaskID: RecordID?
    let selectedTaskDependencyIDs: Set<RecordID>
    let selectedRecurringTaskDependencyIDs: Set<RecordID>
    let canSelectTask: (TaskItem) -> Bool
    let onSave: ([TaskItem], [(RecurringTask, Int)]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @State private var searchText = ""
    @State private var selectedFilter: DependencyFilter = .all
    @State private var pendingTaskIDs: Set<RecordID> = []
    @State private var pendingRecurringTaskCounts: [RecordID: Int] = [:]

    init(
        excludedTaskID: RecordID? = nil,
        selectedTaskDependencyIDs: Set<RecordID>,
        selectedRecurringTaskDependencyIDs: Set<RecordID>,
        canSelectTask: @escaping (TaskItem) -> Bool = { _ in true },
        onSave: @escaping ([TaskItem], [(RecurringTask, Int)]) -> Void
    ) {
        self.excludedTaskID = excludedTaskID
        self.selectedTaskDependencyIDs = selectedTaskDependencyIDs
        self.selectedRecurringTaskDependencyIDs = selectedRecurringTaskDependencyIDs
        self.canSelectTask = canSelectTask
        self.onSave = onSave
    }

    private var availableTasks: [TaskItem] {
        taskStore.tasks.filter {
            $0.deletedAt == nil
                && $0.id != excludedTaskID
                && !selectedTaskDependencyIDs.contains($0.id)
                && canSelectTask($0)
        }
    }

    private var availableRecurringTasks: [RecurringTask] {
        recurringTaskStore.activeRecurringTasks.filter { !selectedRecurringTaskDependencyIDs.contains($0.id) }
    }

    private var matchingTasks: [TaskItem] {
        guard selectedFilter != .recurringTasks else { return [] }
        return fuzzyMatchedItems(availableTasks, name: \.name)
    }

    private var matchingRecurringTasks: [RecurringTask] {
        guard selectedFilter != .tasks else { return [] }
        return fuzzyMatchedItems(availableRecurringTasks, name: \.name)
    }

    private var pendingSelectionCount: Int {
        pendingTaskIDs.count + pendingRecurringTaskCounts.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField
                }

                Section {
                    Picker("Dependency Type", selection: $selectedFilter) {
                        ForEach(DependencyFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if selectedFilter != .recurringTasks {
                    Section("Tasks") {
                        if matchingTasks.isEmpty {
                            Text(searchText.isEmpty ? "No available task dependencies" : "No matching task dependencies")
                                .foregroundStyle(theme.secondaryText())
                        } else {
                            ForEach(matchingTasks) { task in
                                dependencyToggleRow(
                                    title: task.name,
                                    subtitle: "Task",
                                    isSelected: pendingTaskIDs.contains(task.id)
                                ) {
                                    toggleTask(task)
                                }
                            }
                        }
                    }
                }

                if selectedFilter != .tasks {
                    Section("Recurring") {
                        if matchingRecurringTasks.isEmpty {
                            Text(searchText.isEmpty ? "No available recurring dependencies" : "No matching recurring dependencies")
                                .foregroundStyle(theme.secondaryText())
                        } else {
                            ForEach(matchingRecurringTasks) { recurringTask in
                                recurringTaskDependencyRow(recurringTask)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Dependency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(doneTitle) {
                        onSave(selectedTasks, selectedRecurringTasks)
                        dismiss()
                    }
                    .disabled(pendingSelectionCount == 0)
                }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText())
            TextField("Search tasks and recurring", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var doneTitle: String {
        pendingSelectionCount == 0 ? "Done" : "Add \(pendingSelectionCount)"
    }

    private var selectedTasks: [TaskItem] {
        availableTasks.filter { pendingTaskIDs.contains($0.id) }
    }

    private var selectedRecurringTasks: [(RecurringTask, Int)] {
        availableRecurringTasks.compactMap { recurringTask in
            guard let requiredCompletions = pendingRecurringTaskCounts[recurringTask.id] else { return nil }
            return (recurringTask, requiredCompletions)
        }
    }

    private func fuzzyMatchedItems<Item>(_ items: [Item], name: KeyPath<Item, String>) -> [Item] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return items }

        let matcher = FuzzyMatcher()
        let query = matcher.prepare(trimmedSearch)
        var buffer = matcher.makeBuffer()

        return items.enumerated().compactMap { index, item -> (sourceIndex: Int, item: Item, score: Double)? in
            guard let match = matcher.score(item[keyPath: name], against: query, buffer: &buffer) else {
                return nil
            }

            return (sourceIndex: index, item: item, score: match.score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            return lhs.sourceIndex < rhs.sourceIndex
        }
        .map(\.item)
    }

    private func dependencyToggleRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? theme.solidFill(for: .neutral) : theme.secondaryText())
                VStack(alignment: .leading) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText())
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func recurringTaskDependencyRow(_ recurringTask: RecurringTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            dependencyToggleRow(
                title: recurringTask.name,
                subtitle: "Recurring Task",
                isSelected: pendingRecurringTaskCounts[recurringTask.id] != nil
            ) {
                toggleRecurringTask(recurringTask)
            }

            if let requiredCompletions = bindingForRecurringTaskCount(recurringTask) {
                Stepper(value: requiredCompletions, in: 1...999) {
                    Text("\(pendingRecurringTaskCounts[recurringTask.id] ?? 1) more completions")
                        .font(.subheadline)
                }
                .padding(.leading, 28)
            }
        }
    }

    private func bindingForRecurringTaskCount(_ recurringTask: RecurringTask) -> Binding<Int>? {
        guard pendingRecurringTaskCounts[recurringTask.id] != nil else { return nil }
        return Binding(
            get: { pendingRecurringTaskCounts[recurringTask.id] ?? 1 },
            set: { pendingRecurringTaskCounts[recurringTask.id] = $0 }
        )
    }

    private func toggleTask(_ task: TaskItem) {
        if pendingTaskIDs.contains(task.id) {
            pendingTaskIDs.remove(task.id)
        } else {
            pendingTaskIDs.insert(task.id)
        }
    }

    private func toggleRecurringTask(_ recurringTask: RecurringTask) {
        if pendingRecurringTaskCounts[recurringTask.id] == nil {
            pendingRecurringTaskCounts[recurringTask.id] = 1
        } else {
            pendingRecurringTaskCounts.removeValue(forKey: recurringTask.id)
        }
    }
}

struct DependencySectionView<TaskDependency: Identifiable, RecurringTaskDependency: Identifiable>: View {
    @Environment(\.bochiTheme) private var theme
    let taskDependencies: [TaskDependency]
    let recurringTaskDependencies: [RecurringTaskDependency]
    let onAdd: () -> Void
    let task: (TaskDependency) -> TaskItem?
    let taskIsComplete: (TaskItem) -> Bool
    let onOpenTask: (TaskItem) -> Void
    let onCompleteTask: (TaskItem) -> Void
    let onRemoveTaskDependency: (TaskDependency) -> Void
    let recurringTask: (RecurringTaskDependency) -> RecurringTask?
    let recurringTaskProgress: (RecurringTaskDependency) -> Int
    let recurringTaskRequiredCompletions: (RecurringTaskDependency) -> Int
    let recurringTaskRequiredCompletionsBinding: (RecurringTaskDependency, RecurringTask) -> Binding<Int>
    let onOpenRecurringTask: (RecurringTask) -> Void
    let onClaimRecurringTask: (RecurringTask) -> Void
    let onRemoveRecurringTaskDependency: (RecurringTaskDependency) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dependencies")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    onAdd()
                }
            }

            VStack(spacing: 8) {
                ForEach(taskDependencies) { dependency in
                    taskDependencyRow(dependency)
                }

                ForEach(recurringTaskDependencies) { dependency in
                    recurringTaskDependencyRow(dependency)
                }
            }
        }
    }

    @ViewBuilder
    private func taskDependencyRow(_ dependency: TaskDependency) -> some View {
        if let prerequisiteTask = task(dependency) {
            let isComplete = taskIsComplete(prerequisiteTask)

            HStack(spacing: 12) {
                Button {
                    onOpenTask(prerequisiteTask)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prerequisiteTask.name)
                            .font(.body)
                            .foregroundStyle(theme.primaryText())
                            .strikethrough(isComplete)

                        Text(isComplete ? "Completed task" : "Complete this task first")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if !isComplete {
                    Button("Complete") {
                        onCompleteTask(prerequisiteTask)
                    }
                    .buttonStyle(.bordered)
                }

                dependencyMenu {
                    onRemoveTaskDependency(dependency)
                }

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? theme.secondaryText() : theme.secondaryText().opacity(0.65))
            }
            .padding(12)
            .background(theme.componentBackground(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isComplete ? 0.6 : 1)
        }
    }

    @ViewBuilder
    private func recurringTaskDependencyRow(_ dependency: RecurringTaskDependency) -> some View {
        if let dependencyRecurringTask = recurringTask(dependency) {
            let requiredCompletions = recurringTaskRequiredCompletions(dependency)
            let progress = recurringTaskProgress(dependency)
            let isComplete = progress >= requiredCompletions

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        onOpenRecurringTask(dependencyRecurringTask)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dependencyRecurringTask.name)
                                .font(.body)
                                .foregroundStyle(theme.primaryText())
                                .strikethrough(isComplete)

                            Text(
                                isComplete
                                ? "Completed recurring dependency"
                                : "\(min(progress, requiredCompletions))/\(requiredCompletions) more completions"
                            )
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if !isComplete {
                        Button("Claim") {
                            onClaimRecurringTask(dependencyRecurringTask)
                        }
                        .buttonStyle(.bordered)
                    }

                    dependencyMenu {
                        onRemoveRecurringTaskDependency(dependency)
                    }

                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isComplete ? theme.secondaryText() : theme.secondaryText().opacity(0.65))
                }

                Stepper(value: recurringTaskRequiredCompletionsBinding(dependency, dependencyRecurringTask), in: 1...999) {
                    Text("\(requiredCompletions) required completions")
                        .font(.subheadline)
                }
            }
            .padding(12)
            .background(theme.componentBackground(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isComplete ? 0.6 : 1)
        }
    }

    private func dependencyMenu(onRemove: @escaping () -> Void) -> some View {
        Menu {
            Button("Remove Dependency") {
                onRemove()
            }
            .foregroundStyle(theme.destructiveText())
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(theme.secondaryText())
        }
    }
}
