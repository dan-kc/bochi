import SwiftUI

private struct TaskFormRoute: Identifiable {
    let id = UUID()
    let mode: TaskFormMode
    let initialFocus: TaskFormFocus?
    let prefill: TaskFormSnapshot?
}

struct TasksView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: TaskFormRoute? = nil
    @State private var historyTask: TaskItem? = nil
    @State private var taskToDelete: TaskItem? = nil
    @State private var toastManager = ToastManager()
    @State private var showingBlockedTaskAlert = false
    @State private var pendingScrollTargetID: RecordID? = nil
    @State private var highlightedTaskID: RecordID? = nil

    private var visibleTasks: [TaskItem] {
        EntityListQuery.apply(
            items: taskStore.tasks.filter { $0.deletedAt == nil },
            preferences: listPreferencesStore.taskPreferences,
            validTagIDs: tagStore.activeTagIDs,
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: priceSortValue(for:),
            tags: { tagStore.tagsForTask(taskId: $0.id) },
            isDeprioritized: { task in
                task.canTrade && taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore)
            }
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
                rowIDs: visibleTasks.map(\.id),
                pendingScrollTargetID: $pendingScrollTargetID,
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setTaskSort(option)
                    }
                },
                onClearFilters: listPreferencesStore.clearTaskFilters,
                onPendingScrollCompleted: { taskID in
                    scheduleNewTaskHighlightFade(for: taskID)
                }
            ) {
                ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                    EntityListRowSurface(
                        showsDivider: index < visibleTasks.count - 1,
                        isHighlighted: highlightedTaskID == task.id
                    ) {
                        taskRow(task)
                    }
                        .id(task.id)
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
                        .contextMenu {
                            taskRowMenu(task)
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
                    onCreated: { task in
                        queueScrollToTaskIfVisible(task.id)
                    },
                    onDiscard: route.mode.isNew ? { snapshot in
                        showDiscardToast(snapshot: snapshot)
                    } : nil,
                    onDelete: { task in
                        taskToDelete = task
                    }
                )
            }
            .sheet(item: $historyTask) { task in
                TradeHistorySheetView(
                    filter: .task(task.id),
                    detents: [.large]
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
            .alert("Task Blocked", isPresented: $showingBlockedTaskAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This task cannot be completed until its dependencies are finished.")
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
        let taskActionState = TaskTradeActionSupport.state(
            isNewMode: false,
            isCompleted: task.completedAt != nil,
            claimed: false,
            taskTrade: tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: true),
            rewardPreview: reward
        )
        let canComplete = canCompleteTask(task)
        let isBlocked = canComplete && taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore)

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
                    TagPillsRow(
                        tags: tags,
                        leadingInset: 16,
                        showsTrailingFade: true,
                        trailingFadeInset: 36
                    )
                    .padding(.leading, -16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                openChangeForm(task, focus: nil)
            }

            if canComplete {
                TofuActionButton(amount: reward, polarity: .earning, layout: .compact) {
                    completeTask(task, reward: reward)
                }
                .accessibilityIdentifier("task.claim")
            } else if case .undoRefund = taskActionState {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44, alignment: .center)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isBlocked ? 0.55 : 1)
    }

    private func priceSortValue(for task: TaskItem) -> Int? {
        EntityActionSupport.sortableAmount(isActionable: canCompleteTask(task)) {
            TaskRewardCalculation.calculateReward(task: task)
        }
    }

    private func completeTask(_ task: TaskItem, reward: Int) {
        guard canCompleteTask(task) else { return }
        guard !taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore) else {
            showingBlockedTaskAlert = true
            return
        }
        _ = TaskCompletionSupport.completeTask(
            taskID: task.id,
            sourceName: task.name,
            reward: reward,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
    }

    private func canCompleteTask(_ task: TaskItem) -> Bool {
        task.canTrade && tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: true) == nil
    }

    @ViewBuilder
    private func taskRowMenu(_ task: TaskItem) -> some View {
        let reward = TaskRewardCalculation.calculateReward(task: task)
        let taskActionState = TaskTradeActionSupport.state(
            isNewMode: false,
            isCompleted: task.completedAt != nil,
            claimed: false,
            taskTrade: tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: true),
            rewardPreview: reward
        )

        switch taskActionState {
        case .complete:
            Button {
                completeTask(task, reward: reward)
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        case .refund:
            Button {
                setRefunded(true, forTask: task)
            } label: {
                Label("Refund", systemImage: "arrow.uturn.backward")
            }
        case .undoRefund:
            Button {
                setRefunded(false, forTask: task)
            } label: {
                Label("Undo Refund", systemImage: "arrow.uturn.forward")
            }
        case .none:
            EmptyView()
        }

        Button {
            openChangeForm(task, focus: nil)
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            historyTask = task
        } label: {
            Label("View History", systemImage: "clock.arrow.circlepath")
        }

        Button(role: .destructive) {
            taskToDelete = task
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func queueScrollToTaskIfVisible(_ taskID: RecordID) {
        guard visibleTasks.contains(where: { $0.id == taskID }) else { return }
        highlightedTaskID = taskID
        pendingScrollTargetID = taskID
    }

    private func scheduleNewTaskHighlightFade(for taskID: RecordID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard highlightedTaskID == taskID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                highlightedTaskID = nil
            }
        }
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

    private func setRefunded(_ refunded: Bool, forTask task: TaskItem) {
        guard let trade = tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: true) else { return }

        TradeRefundService.setRefunded(
            refunded,
            for: trade,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
    }
}

#Preview {
    let taskStore = TaskStore()
    let habitStore = HabitStore()
    TasksView()
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
        .environment(AppNavigationStore())
        .environment(ListPreferencesStore())
}
