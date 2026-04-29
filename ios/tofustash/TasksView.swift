import SwiftUI

private struct TaskFormRoute: Identifiable {
    let id = UUID()
    let mode: TaskFormMode
    let initialFocus: TaskFormFocus?
    let prefill: TaskFormSnapshot?
}

struct TasksView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: TaskFormRoute? = nil
    @State private var taskToDelete: TaskItem? = nil
    @State private var toastManager = ToastManager()

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
                    formRoute = TaskFormRoute(
                        mode: .new,
                        initialFocus: nil,
                        prefill: nil
                    )
                }
            }
            .sheet(item: $formRoute) { route in
                TaskFormView(
                    mode: route.mode,
                    initialFocus: route.initialFocus,
                    prefill: route.prefill,
                    onDiscard: route.mode.isNew ? { snapshot in
                        showDiscardToast(snapshot: snapshot)
                    } : nil,
                    onDelete: { task in
                        taskToDelete = task
                    },
                    onTaskCompleted: { _ in }
                )
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
                        reminderStore.deleteAllReminders(for: .task(task.id))
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
            .overlay {
                ToastOverlay(toastManager: toastManager)
            }
            .onAppear {
                schedulePendingTaskFormOpenIfNeeded()
            }
            .onChange(of: appNavigationStore.pendingEntityFormRequest) { _, _ in
                schedulePendingTaskFormOpenIfNeeded()
            }
            .onChange(of: appNavigationStore.selectedTab) { _, selectedTab in
                guard selectedTab == .tasks else { return }
                schedulePendingTaskFormOpenIfNeeded()
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
                openChangeForm(task, focus: nil)
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

    private func showDiscardToast(snapshot: TaskFormSnapshot) {
        toastManager.show(
            message: "Task Discarded",
            actionLabel: "Recover"
        ) {
            formRoute = TaskFormRoute(
                mode: .new,
                initialFocus: nil,
                prefill: snapshot
            )
        }
    }

    @MainActor
    private func openPendingTaskFormIfNeeded() {
        guard appNavigationStore.selectedTab == .tasks else { return }
        guard let request = appNavigationStore.pendingEntityFormRequest else { return }
        guard case .task(let taskID) = request.route else { return }
        guard let task = taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil }) else { return }
        guard formRoute == nil else { return }
        openChangeForm(task, focus: nil)
        appNavigationStore.clearPendingEntityFormRequest(id: request.id)
    }

    private func schedulePendingTaskFormOpenIfNeeded() {
        DispatchQueue.main.async {
            self.openPendingTaskFormIfNeeded()
        }
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

    private func openChangeForm(_ task: TaskItem, focus: TaskFormFocus?) {
        formRoute = TaskFormRoute(
            mode: .change(task),
            initialFocus: focus,
            prefill: nil
        )
    }
}

#Preview {
    TasksView()
        .environment(TaskStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(ReminderStore(
            taskStore: TaskStore(),
            habitStore: HabitStore(),
            notificationScheduler: NoOpReminderNotificationScheduler()
        ))
        .environment(AppNavigationStore())
        .environment(ListPreferencesStore())
}
