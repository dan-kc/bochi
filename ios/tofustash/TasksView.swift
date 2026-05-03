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
    @Environment(SpecialOfferStore.self) private var specialOfferStore
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
    @Namespace private var searchChromeNamespace
    @State private var searchState = EntityListSearchState()

    private var activeTasks: [TaskItem] {
        taskStore.tasks.filter { $0.deletedAt == nil }
    }

    private var filterState: EntityListFilterState {
        EntityListFilterState(
            preferences: listPreferencesStore.taskPreferences,
            search: searchState
        )
    }

    private func visibleTasks(offerSnapshot: SpecialOfferSnapshot) -> [TaskItem] {
        EntityListQuery.apply(
            items: activeTasks,
            filterState: filterState,
            validTagIDs: tagStore.activeTagIDs,
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { priceSortValue(for: $0, offerSnapshot: offerSnapshot) },
            tags: { tagStore.tagsForTask(taskId: $0.id) },
            isDeprioritized: { task in
                task.canTrade && taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore)
            }
        )
    }

    var body: some View {
        let offerSnapshot = specialOfferStore.makeSnapshot()
        let visibleTasks = visibleTasks(offerSnapshot: offerSnapshot)
        let taskSections = EntityListSectionSupport.taskSections(
            tasks: visibleTasks,
            taskStore: taskStore,
            tradeStore: tradeStore,
            taskDependencyStore: taskDependencyStore
        )

        NavigationStack {
            EntityListScreen(
                hasAnyItems: !activeTasks.isEmpty,
                visibleItemCount: visibleTasks.count,
                emptyTitle: "No Tasks Yet",
                emptySystemImage: "checkmark.square",
                emptyDescription: "Tap + to create your first task.",
                filteredEmptyTitle: "No Matching Tasks",
                filteredEmptyDescription: "Try changing the search text or selected tags to see more tasks.",
                searchPrompt: "Search tasks",
                searchChromeNamespace: searchChromeNamespace,
                filterState: filterState,
                tagScope: .tasks,
                rowIDs: visibleTasks.map(\.id),
                searchState: $searchState,
                pendingScrollTargetID: $pendingScrollTargetID,
                onAdd: openNewTaskForm,
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
                ForEach(taskSections) { section in
                    Section {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, task in
                            EntityListRowSurface(
                                showsDivider: index < section.items.count - 1,
                                isHighlighted: highlightedTaskID == task.id,
                                isSpecialOffer: offerSnapshot.hasActiveOffer(for: .task, entityID: task.id)
                            ) {
                                taskRow(task, offerSnapshot: offerSnapshot, isDimmed: section.isDimmed)
                            }
                            .id(task.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    // Behaviour: align task deletion with the existing
                                    // habits/rewards confirmation flow.
                                    confirmDelete(task)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                            .contextMenu {
                                taskRowMenu(task, offerSnapshot: offerSnapshot)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        if let title = section.title {
                            EntityListSectionHeader(title: title)
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .overlay(alignment: .bottomTrailing) {
                EntityListFloatingActionOverlay(
                    showsSearchButton: !activeTasks.isEmpty,
                    namespace: searchChromeNamespace,
                    searchState: $searchState,
                    onAdd: openNewTaskForm
                )
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
                        deleteTask(task)
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
                        deleteTask(task)
                    }
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

    private func openNewTaskForm() {
        formRoute = TaskFormRoute(
            mode: .new,
            initialFocus: nil,
            prefill: nil
        )
    }

    private func confirmDelete(_ task: TaskItem) {
        taskToDelete = task
    }

    private func deleteTask(_ task: TaskItem) {
        let deletedAt = Date()
        reminderStore.deleteAllReminders(for: .task(task.id))
        withAnimation(.default) {
            taskDependencyStore.deleteDependenciesReferencingTask(
                task.id,
                deletedAt: deletedAt
            )
            taskStore.deleteTask(id: task.id, deletedAt: deletedAt)
            taskToDelete = nil
        }
    }

    private func taskRow(
        _ task: TaskItem,
        offerSnapshot: SpecialOfferSnapshot,
        isDimmed: Bool
    ) -> some View {
        let tags = tagStore.tagsForTask(taskId: task.id)
        let reward = TaskRewardCalculation.calculateReward(
            task: task,
            specialOfferModifierPercent: offerSnapshot.activeModifierPercent(for: .task, entityID: task.id)
        )
        let canComplete = canCompleteTask(task)
        let offer = offerSnapshot.activeOffer(for: .task, entityID: task.id)

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

                    if let offer {
                        SpecialOfferMetaPill(offer: offer)
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

            if canComplete {
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
        .opacity(isDimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            openChangeForm(task, focus: nil)
        }
    }

    private func priceSortValue(for task: TaskItem, offerSnapshot: SpecialOfferSnapshot) -> Int? {
        EntityActionSupport.sortableAmount(isActionable: canCompleteTask(task)) {
            TaskRewardCalculation.calculateReward(
                task: task,
                specialOfferModifierPercent: offerSnapshot.activeModifierPercent(for: .task, entityID: task.id)
            )
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
        task.canTrade && tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) == nil
    }

    @ViewBuilder
    private func taskRowMenu(_ task: TaskItem, offerSnapshot: SpecialOfferSnapshot) -> some View {
        let reward = TaskRewardCalculation.calculateReward(
            task: task,
            specialOfferModifierPercent: offerSnapshot.activeModifierPercent(for: .task, entityID: task.id)
        )
        let taskActionState = TaskTradeActionSupport.state(
            isNewMode: false,
            isCompleted: task.completedAt != nil,
            claimed: false,
            taskTrade: tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false),
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
                refundTask(task)
            } label: {
                Label("Refund", systemImage: "arrow.uturn.backward")
            }
        case .none:
            EmptyView()
        }

        EntityRowContextMenuActions.editHistoryDelete(
            onEdit: {
                openChangeForm(task, focus: nil)
            },
            onViewHistory: {
                historyTask = task
            },
            onDelete: {
                confirmDelete(task)
            }
        )
    }

    private func queueScrollToTaskIfVisible(_ taskID: RecordID) {
        EntityListViewCoordinator.queueScrollToVisibleItem(
            taskID,
            visibleIDs: visibleTasks(offerSnapshot: specialOfferStore.makeSnapshot()).map(\.id),
            highlightedID: &highlightedTaskID,
            pendingScrollTargetID: &pendingScrollTargetID
        )
    }

    private func scheduleNewTaskHighlightFade(for taskID: RecordID) {
        EntityListViewCoordinator.scheduleHighlightFade(
            for: taskID,
            highlightedID: { highlightedTaskID },
            setHighlightedID: { highlightedTaskID = $0 }
        )
    }

    private func showDiscardToast(snapshot: TaskFormSnapshot) {
        EntityListViewCoordinator.showDiscardToast(
            toastManager: toastManager,
            entityName: "Task",
            snapshot: snapshot,
            makeRoute: {
                TaskFormRoute(mode: .new, initialFocus: nil, prefill: $0)
            },
            setRoute: { formRoute = $0 }
        )
    }

    @MainActor
    private func openPendingTaskFormIfNeeded() {
        EntityListViewCoordinator.openPendingFormIfNeeded(
            expectedTab: .tasks,
            selectedTab: appNavigationStore.selectedTab,
            request: appNavigationStore.pendingEntityFormRequest,
            extractID: { route in
                guard case .task(let taskID) = route else { return nil }
                return taskID
            },
            resolveEntity: { taskID in
                taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil })
            },
            isPresentingForm: formRoute != nil,
            open: { task in
                openChangeForm(task, focus: nil)
            },
            clearRequest: { requestID in
                appNavigationStore.clearPendingEntityFormRequest(id: requestID)
            }
        )
    }

    private func schedulePendingTaskFormOpenIfNeeded() {
        EntityListViewCoordinator.schedulePendingFormOpen(openPendingTaskFormIfNeeded)
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

    private func refundTask(_ task: TaskItem) {
        guard let trade = tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) else { return }

        _ = TradeRefundService.refund(
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
