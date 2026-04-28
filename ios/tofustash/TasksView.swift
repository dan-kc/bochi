import SwiftUI

private struct TaskFormRoute: Identifiable {
    let id = UUID()
    let task: TaskItem?
}

struct TasksView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: TaskFormRoute? = nil
    @State private var taskToDelete: TaskItem? = nil

    private var visibleTasks: [TaskItem] {
        EntityListQuery.apply(
            items: taskStore.tasks.filter { $0.deletedAt == nil },
            preferences: listPreferencesStore.taskPreferences,
            validTagIDs: tagStore.activeTagIDs,
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: priceSortValue(for:),
            tags: { tagStore.tagsForTask(taskId: $0.id) }
        )
    }

    var body: some View {
        NavigationStack {
            EntityListScreen(
                hasAnyItems: !taskStore.tasks.filter({ $0.deletedAt == nil }).isEmpty,
                visibleItemCount: visibleTasks.count,
                emptyTitle: "No Tasks Yet",
                emptySystemImage: "checkmark.square",
                emptyDescription: "Tap + to create your first task.",
                filteredEmptyTitle: "No Matching Tasks",
                filteredEmptyDescription: "Try changing the selected tags or clear them to see more tasks.",
                preferences: listPreferencesStore.taskPreferences,
                tagScope: .tasks,
                onSelectSort: listPreferencesStore.setTaskSort,
                onClearFilters: listPreferencesStore.clearTaskFilters
            ) {
                ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                    EntityListRowSurface(showsDivider: index < visibleTasks.count - 1) {
                        taskRow(task)
                    }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                // Behaviour: align task deletion with the existing
                                // habits/rewards confirmation flow.
                                taskToDelete = task
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
            .navigationTitle("Tasks")
            .overlay(alignment: .bottomTrailing) {
                EntityFloatingAddButton {
                    formRoute = TaskFormRoute(task: nil)
                }
            }
            .sheet(item: $formRoute) { route in
                TaskFormView(task: route.task)
            }
            .alert(
                "Delete Task?",
                isPresented: Binding(
                    get: { taskToDelete != nil },
                    set: { if !$0 { taskToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let task = taskToDelete {
                        taskStore.deleteTask(id: task.id)
                    }
                    taskToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    taskToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        let tags = tagStore.tagsForTask(taskId: task.id)
        let reward = TaskRewardCalculation.calculateReward(task: task)

        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    EntityListMetaPill(
                        text: task.difficultyTier?.displayName ?? "Difficulty",
                        isSet: task.difficultyTier != nil
                    )

                    EntityListMetaPill(
                        text: durationSummary(for: task.durationSeconds),
                        isSet: task.durationSeconds != nil
                    )

                    if let dueDate = task.dueDate {
                        EntityListMetaPill(
                            text: dueDate.formatted(.dateTime.month(.abbreviated).day()),
                            isSet: true
                        )
                    }
                }

                if !tags.isEmpty {
                    TagPillsRow(tags: tags)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                formRoute = TaskFormRoute(task: task)
            }

            if task.canTrade {
                TofuActionButton(amount: reward, polarity: .earning, layout: .compact) {
                    completeTask(task, reward: reward)
                }
                .accessibilityIdentifier("task.claim")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func priceSortValue(for task: TaskItem) -> Int? {
        EntityActionSupport.sortableAmount(isActionable: task.canTrade) {
            TaskRewardCalculation.calculateReward(task: task)
        }
    }

    private func completeTask(_ task: TaskItem, reward: Int) {
        guard task.canTrade else { return }
        let claimDate = Date()
        tradeStore.addTaskTrade(taskId: task.id, amount: reward, createdAt: claimDate)
        taskStore.completeTask(id: task.id, completedAt: claimDate)
        balanceStore.refresh()
    }

    private func durationSummary(for durationSeconds: Int?) -> String {
        guard let durationSeconds, durationSeconds > 0 else { return "Duration" }
        let minutes = durationSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if minutes % 60 == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes % 60)m"
    }
}

#Preview {
    TasksView()
        .environment(TaskStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(ListPreferencesStore())
}
