import SwiftUI

private struct EarnTaskFormRoute: Identifiable {
    let id = UUID()
    let mode: TaskFormMode
    let initialFocus: TaskFormFocus?
    let prefill: TaskFormSnapshot?
}

private struct EarnRecurringTaskFormRoute: Identifiable {
    let id = UUID()
    let mode: RecurringTaskFormMode
    let initialFocus: RecurringTaskFormFocus?
    let prefill: RecurringTaskFormSnapshot?
}

private struct PendingEarnActionWarning: Identifiable {
    let id = UUID()
    let reason: EntityActionGateReason
    let entityName: String
    let actionTitle: String
    let continueAction: () -> Void
}

private struct EarnListProjectionToken: Equatable {
    let tasks: [TaskItem]
    let recurringTasks: [RecurringTask]
    let taskTaskDependencies: [TaskTaskDependency]
    let taskRecurringTaskDependencies: [TaskRecurringTaskDependency]
    let tags: [Tag]
    let taskTags: [TaskTag]
    let recurringTaskTags: [RecurringTaskTag]
    let trades: [Trade]
    let preferences: EntityListPreferences
    let hasPremiumAccess: Bool
}

struct EarnView: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @State private var taskFormRoute: EarnTaskFormRoute? = nil
    @State private var recurringTaskFormRoute: EarnRecurringTaskFormRoute? = nil
    @State private var claimRoute: TaskClaimRoute? = nil
    @State private var tradingRecurringTaskRoute: RecurringTaskTradeRoute? = nil
    @State private var historyTask: TaskItem? = nil
    @State private var historyRecurringTask: RecurringTask? = nil
    @State private var taskToDelete: TaskItem? = nil
    @State private var recurringTaskToDelete: RecurringTask? = nil
    @State private var showingBlockedTaskAlert = false
    @State private var pendingActionWarning: PendingEarnActionWarning? = nil
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var showingRefundFeedback = false
    @State private var pendingScrollTargetID: EarnListRowID? = nil
    @State private var highlightedRowID: EarnListRowID? = nil
    @State private var listProjection: EarnListProjection?

    private var projectionToken: EarnListProjectionToken {
        EarnListProjectionToken(
            tasks: taskStore.tasks,
            recurringTasks: recurringTaskStore.recurringTasks,
            taskTaskDependencies: taskDependencyStore.taskTaskDependencies,
            taskRecurringTaskDependencies: taskDependencyStore.taskRecurringTaskDependencies,
            tags: tagStore.tags,
            taskTags: tagStore.taskTags,
            recurringTaskTags: tagStore.recurringTaskTags,
            trades: tradeStore.trades,
            preferences: listPreferencesStore.earnPreferences,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    var body: some View {
        // User behaviour: Earn is the high-traffic default list, so presenting
        // sheets should reuse the current projection until source data changes.
        let projection = listProjection ?? makeListProjection()

        NavigationStack {
            EntityListScreen(
                hasAnyItems: !projection.activeTasks.isEmpty || !projection.activeRecurringTasks.isEmpty,
                visibleItemCount: projection.visibleRows.count,
                emptyTitle: "Nothing to Earn Yet",
                emptySystemImage: "plus.circle",
                emptyDescription: "Tap + to create your first task.",
                filteredEmptyTitle: "No Matching Earn Items",
                filteredEmptyDescription: "Try turning filters back on to see more earning options.",
                preferences: listPreferencesStore.earnPreferences,
                tagScope: .earn,
                availableTags: tagStore.activeTags,
                statusFilters: [.task, .recurringTask, .hidden, .locked],
                rowIDs: projection.rowIDs,
                pendingScrollTargetID: $pendingScrollTargetID,
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setEarnSort(option)
                    }
                },
                onClearFilters: listPreferencesStore.clearEarnFilters,
                onToggleStatus: { status in
                    listPreferencesStore.toggleEarnStatus(status)
                },
                onToggleTag: { tagID in
                    listPreferencesStore.toggleEarnTag(tagID)
                },
                onControlsVisibilityChange: { isVisible in
                    appNavigationStore.setRootEntityListControlsVisibility(isVisible, for: .earn)
                },
                onPendingScrollCompleted: { rowID in
                    scheduleNewRowHighlightFade(for: rowID)
                }
            ) {
                ForEach(Array(projection.visibleRows.enumerated()), id: \.element.id) { index, row in
                    EntityListRowSurface(
                        showsDivider: index < projection.visibleRows.count - 1,
                        role: row.themeRole,
                        isHighlighted: highlightedRowID == row.id
                    ) {
                        earnRow(row)
                    }
                    .id(row.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            confirmDelete(row)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(theme.destructiveText())
                    }
                    .contextMenu {
                        earnRowMenu(row)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Earn")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                EntityListFloatingActionOverlay(
                    showsSearchButton: !projection.activeTasks.isEmpty || !projection.activeRecurringTasks.isEmpty,
                    onAdd: openNewEarnForm
                )
            }
            .sheet(item: $taskFormRoute) { route in
                TaskFormView(
                    mode: route.mode,
                    initialFocus: route.initialFocus,
                    prefill: route.prefill,
                    onCreated: { task in
                        queueScrollToRowIfVisible(.task(task.id))
                    },
                    onDiscard: nil,
                    onDelete: { task in
                        deleteTask(task)
                    },
                    onDuplicate: { task in
                        duplicateTask(task)
                    }
                )
            }
            .sheet(item: $recurringTaskFormRoute) { route in
                RecurringTaskFormView(
                    mode: route.mode,
                    initialFocus: route.initialFocus,
                    prefill: route.prefill,
                    onCreated: { recurringTask in
                        queueScrollToRowIfVisible(.recurringTask(recurringTask.id))
                    },
                    onDiscard: nil,
                    onDelete: { recurringTask in
                        deleteRecurringTask(recurringTask)
                    },
                    onDuplicate: { recurringTask in
                        duplicateRecurringTask(recurringTask)
                    }
                )
            }
            .sheet(item: $claimRoute) { route in
                TaskClaimModalView(
                    task: route.task,
                    price: route.price,
                hasPremiumAccess: hasPremiumAccess,
                onClaim: { adjustedPrice, adjustmentBaseAmount, oneTimeAdjustmentMultiplier in
                    completeTask(
                        route.task,
                        price: adjustedPrice,
                        adjustmentBaseAmount: adjustmentBaseAmount,
                        oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                        allowsRestrictedClaim: route.allowsRestrictedClaim
                        )
                    }
                )
            }
            .sheet(item: $tradingRecurringTaskRoute) { route in
            TradeModalView(
                recurringTask: route.recurringTask,
                quote: route.quote,
                allowsRestrictedClaim: route.allowsRestrictedClaim
                )
            }
            .sheet(item: $historyTask) { task in
                TradeHistorySheetView(filter: .task(task.id), detents: [.large])
            }
            .sheet(item: $historyRecurringTask) { recurringTask in
                TradeHistorySheetView(filter: .recurringTask(recurringTask.id), detents: [.large])
            }
            .sheet(isPresented: $showingRefundFeedback) {
                TaskRefundFeedbackSheet {
                    showingRefundFeedback = false
                }
            }
            .sheet(item: $pendingActionWarning) { warning in
                EntityActionWarningModalView(
                    entityName: warning.entityName,
                    actionTitle: warning.actionTitle,
                    reason: warning.reason,
                    onCancel: { pendingActionWarning = nil },
                    onConfirm: {
                        let continueAction = warning.continueAction
                        pendingActionWarning = nil
                        continueAction()
                    }
                )
            }
            .fullScreenCover(item: $premiumUpsellFeature) { feature in
                PremiumUpsellView(feature: feature)
            }
            .alert(
                "Delete Task?",
                isPresented: Binding(
                    get: { taskToDelete != nil },
                    set: { if !$0 { taskToDelete = nil } }
                )
            ) {
                Button("Delete") {
                    if let task = taskToDelete {
                        deleteTask(task)
                    }
                }
                Button("Cancel", role: .cancel) {
                    taskToDelete = nil
                }
            } message: {
                Text("Your balance will not be affected.")
            }
            .alert(
                "Delete Recurring Task?",
                isPresented: Binding(
                    get: { recurringTaskToDelete != nil },
                    set: { if !$0 { recurringTaskToDelete = nil } }
                )
            ) {
                Button("Delete") {
                    if let recurringTask = recurringTaskToDelete {
                        deleteRecurringTask(recurringTask)
                    }
                }
                Button("Cancel", role: .cancel) {
                    recurringTaskToDelete = nil
                }
            } message: {
                Text("Your balance will not be affected.")
            }
            .alert("Task Blocked", isPresented: $showingBlockedTaskAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This task cannot be completed until its dependencies are finished.")
            }
            .entityListProjectionLifecycle(
                projectionToken: projectionToken,
                pendingFormToken: appNavigationStore.pendingEntityFormRequest,
                pendingRevealToken: appNavigationStore.pendingEntityRevealRequest,
                selectedTab: appNavigationStore.selectedTab,
                expectedTab: .earn,
                refreshProjection: updateListProjection,
                openPendingForm: openPendingEarnFormIfNeeded,
                revealPendingEntity: revealPendingEarnIfNeeded
            )
        }
    }

    private func updateListProjection() {
        listProjection = makeListProjection()
    }

    private func makeListProjection() -> EarnListProjection {
        EarnListProjectionBuilder.makeProjection(
            inputs: EarnListProjectionInputs(
                tasks: taskStore.tasks,
                recurringTasks: recurringTaskStore.recurringTasks,
                taskTagsByID: tagStore.tagsByTaskID(),
                recurringTaskTagsByID: tagStore.tagsByRecurringTaskID(),
                activeTagIDs: tagStore.activeTagIDs,
                taskTaskDependencies: taskDependencyStore.taskTaskDependencies,
                taskRecurringTaskDependencies: taskDependencyStore.taskRecurringTaskDependencies,
                latestTaskTradesByTaskID: tradeStore.latestUnrefundedTaskTradesByTaskID(),
                recurringTaskCompletionCountsByRecurringTaskID: tradeStore.recurringTaskCompletionCountsByRecurringTaskID(),
                recurringTaskTradeDatesByRecurringTaskID: tradeStore.recurringTaskTradeDatesByRecurringTaskID(),
                preferences: listPreferencesStore.earnPreferences,
                hasPremiumAccess: hasPremiumAccess,
                now: Date()
            )
        )
    }

    private func visibleRowIDs() -> [EarnListRowID] {
        makeListProjection().rowIDs
    }

    @ViewBuilder
    private func earnRow(_ row: EarnListRowModel) -> some View {
        switch row {
        case .task(let taskRow):
            taskRowView(taskRow, isDimmed: taskRow.isCompleted || taskRow.isBlocked || taskRow.task.hidden)
        case .recurringTask(let recurringTaskRow):
            recurringTaskRowView(recurringTaskRow, isDimmed: recurringTaskRow.isLocked || recurringTaskRow.recurringTask.hidden)
        }
    }

    private func taskRowView(_ row: EarnTaskRowModel, isDimmed: Bool) -> some View {
        let task = row.task
        let metadataItems = EntityListRowPillSupport.taskMetadata(task: task)
        let pills = EntityListRowPillSupport.taskPills(task: task, tags: row.tags)
        let rowStatus = row.listStatus
        let gateReason = EntityActionGateSupport.reason(
            isLocked: row.isBlocked,
            isHidden: task.hidden
        )

        return HStack(alignment: rowStatus == nil ? .bottom : .center) {
            EntityListRowText(
                name: task.name,
                description: task.description,
                metadataItems: metadataItems,
                pills: pills,
                role: .task,
                isNameStruckThrough: row.isCompleted,
                showsDetails: userSettingsStore.showsEntityRowDetails
            )
            .contentShape(Rectangle())
            .onTapGesture {
                openTaskChangeForm(task, focus: nil)
            }

            EntityListRowActionColumn {
                if let rowStatus {
                    EntityListRowStatusLabel(status: rowStatus, role: .task)
                } else if row.canComplete {
                    BochiActionButton(
                        amount: row.price,
                        polarity: .earning,
                        layout: .compact,
                        usesMainThemeStyle: gateReason != nil,
                        themeRoleOverride: .task
                    ) {
                        presentTaskClaim(
                            task,
                            price: row.price,
                            warningReason: gateReason
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDimmed ? 0.55 : 1)
    }

    private func recurringTaskRowView(_ row: EarnRecurringTaskRowModel, isDimmed: Bool) -> some View {
        let recurringTask = row.recurringTask
        let metadataItems = EntityListRowPillSupport.recurringTaskMetadata(recurringTask: recurringTask)
        let pills = EntityListRowPillSupport.recurringTaskPills(recurringTask: recurringTask, tags: row.tags)
        let rowStatus = row.listStatus
        let gateReason = EntityActionGateSupport.reason(
            isLocked: row.isLocked,
            lockoutSummary: lockoutSummary(for: recurringTask),
            isHidden: recurringTask.hidden
        )

        return HStack(alignment: rowStatus == nil ? .bottom : .center) {
            EntityListRowText(
                name: recurringTask.name,
                description: recurringTask.description,
                metadataItems: metadataItems,
                pills: pills,
                role: .recurringTask,
                showsDetails: userSettingsStore.showsEntityRowDetails
            )

            EntityListRowActionColumn {
                if let rowStatus {
                    EntityListRowStatusLabel(status: rowStatus, role: .recurringTask)
                } else if recurringTask.canTrade {
                    VStack(alignment: .trailing, spacing: 4) {
                        EntityListRowPriceDeltaLabel(
                            percent: PriceDeltaSupport.percent(currentPrice: row.price, basePrice: recurringTask.basePrice),
                            role: .recurringTask
                        )
                        BochiActionButton(
                            amount: row.price,
                            polarity: .earning,
                            layout: .compact,
                            usesMainThemeStyle: gateReason != nil,
                            themeRoleOverride: .recurringTask
                        ) {
                            openTradeModal(
                                for: recurringTask,
                                quote: row.quote,
                                warningReason: gateReason
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            openRecurringTaskChangeForm(recurringTask, focus: nil)
        }
    }

    @ViewBuilder
    private func earnRowMenu(_ row: EarnListRowModel) -> some View {
        switch row {
        case .task(let taskRow):
            taskRowMenu(taskRow)
        case .recurringTask(let recurringTaskRow):
            recurringTaskRowMenu(recurringTaskRow)
        }
    }

    @ViewBuilder
    private func taskRowMenu(_ row: EarnTaskRowModel) -> some View {
        let task = row.task
        let taskActionState = TaskTradeActionSupport.state(
            isNewMode: false,
            isCompleted: row.isCompleted,
            claimed: false,
            taskTrade: tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false),
            pricePreview: row.price
        )

        switch taskActionState {
        case .complete:
            Button {
                presentTaskClaim(
                    task,
                    price: row.price,
                    warningReason: EntityActionGateSupport.reason(
                        isLocked: row.isBlocked,
                        isHidden: task.hidden
                    )
                )
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        case .refund:
            Button {
                requestTaskRefund(task)
            } label: {
                Label(
                    hasPremiumAccess ? "Refund" : "Refund (Premium)",
                    systemImage: hasPremiumAccess ? "arrow.uturn.backward" : "crown"
                )
            }
        case .none:
            EmptyView()
        }

        EntityRowContextMenuActions.editHistoryDelete(
            theme: theme,
            onEdit: {
                openTaskChangeForm(task, focus: nil)
            },
            onDuplicate: {
                duplicateTask(task)
            },
            onTogglePin: {
                taskStore.setPinned(id: task.id, pinned: !task.pinned)
            },
            isPinned: task.pinned,
            onToggleHidden: {
                taskStore.setHidden(id: task.id, hidden: !task.hidden)
            },
            isHidden: task.hidden,
            onViewHistory: {
                historyTask = task
            },
            onDelete: {
                confirmDelete(.task(row))
            }
        )
    }

    @ViewBuilder
    private func recurringTaskRowMenu(_ row: EarnRecurringTaskRowModel) -> some View {
        let recurringTask = row.recurringTask

        if recurringTask.canTrade {
            Button {
                openTradeModal(
                    for: recurringTask,
                    quote: row.quote,
                    warningReason: EntityActionGateSupport.reason(
                        isLocked: row.isLocked,
                        lockoutSummary: lockoutSummary(for: recurringTask),
                        isHidden: recurringTask.hidden
                    )
                )
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        }

        EntityRowContextMenuActions.editHistoryDelete(
            theme: theme,
            onEdit: {
                openRecurringTaskChangeForm(recurringTask, focus: nil)
            },
            onDuplicate: {
                duplicateRecurringTask(recurringTask)
            },
            onTogglePin: {
                recurringTaskStore.setPinned(id: recurringTask.id, pinned: !recurringTask.pinned)
            },
            isPinned: recurringTask.pinned,
            onToggleHidden: {
                recurringTaskStore.setHidden(id: recurringTask.id, hidden: !recurringTask.hidden)
            },
            isHidden: recurringTask.hidden,
            onViewHistory: {
                historyRecurringTask = recurringTask
            },
            onDelete: {
                confirmDelete(.recurringTask(row))
            }
        )
    }

    private func lockoutSummary(for recurringTask: RecurringTask) -> String? {
        guard let remainingSeconds = RecurringTaskLockout.remainingSeconds(
            recurringTask: recurringTask,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            return nil
        }

        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
    }

    private func openNewEarnForm() {
        appNavigationStore.openNewEntityForm(selectedEntity: .task, originTab: .earn)
    }

    private func openTaskChangeForm(_ task: TaskItem, focus: TaskFormFocus?) {
        taskFormRoute = EarnTaskFormRoute(mode: .change(task), initialFocus: focus, prefill: nil)
    }

    private func openRecurringTaskChangeForm(_ recurringTask: RecurringTask, focus: RecurringTaskFormFocus?) {
        recurringTaskFormRoute = EarnRecurringTaskFormRoute(mode: .change(recurringTask), initialFocus: focus, prefill: nil)
    }

    private func openTradeModal(
        for recurringTask: RecurringTask,
        quote: RecurringTaskTradeQuote,
        warningReason: EntityActionGateReason? = nil
    ) {
        if let warningReason {
            pendingActionWarning = PendingEarnActionWarning(
                reason: warningReason,
                entityName: recurringTask.name,
                actionTitle: "Complete Task",
                continueAction: {
                    openTradeModal(
                        for: recurringTask,
                        quote: quote,
                        allowsRestrictedClaim: true
                    )
                }
            )
            return
        }

        openTradeModal(for: recurringTask, quote: quote, allowsRestrictedClaim: false)
    }

    private func openTradeModal(
        for recurringTask: RecurringTask,
        quote: RecurringTaskTradeQuote,
        allowsRestrictedClaim: Bool
    ) {
        tradingRecurringTaskRoute = RecurringTaskTradeRoute(
            recurringTask: recurringTask,
            quote: quote,
            allowsRestrictedClaim: allowsRestrictedClaim
        )
    }

    private func confirmDelete(_ row: EarnListRowModel) {
        switch row {
        case .task(let taskRow):
            taskToDelete = taskRow.task
        case .recurringTask(let recurringTaskRow):
            recurringTaskToDelete = recurringTaskRow.recurringTask
        }
    }

    private func deleteTask(_ task: TaskItem) {
        let deletedAt = Date()
        withAnimation(.default) {
            EntityDeletionService.deleteTask(
                task,
                reminderStore: reminderStore,
                taskDependencyStore: taskDependencyStore,
                rewardDependencyStore: rewardDependencyStore,
                taskStore: taskStore,
                deletedAt: deletedAt
            )
            taskToDelete = nil
        }
    }

    private func deleteRecurringTask(_ recurringTask: RecurringTask) {
        let deletedAt = Date()
        withAnimation(.default) {
            EntityDeletionService.deleteRecurringTask(
                recurringTask,
                reminderStore: reminderStore,
                taskDependencyStore: taskDependencyStore,
                rewardDependencyStore: rewardDependencyStore,
                recurringTaskStore: recurringTaskStore,
                deletedAt: deletedAt
            )
            recurringTaskToDelete = nil
        }
    }

    private func presentTaskClaim(
        _ task: TaskItem,
        price: Int,
        warningReason: EntityActionGateReason? = nil,
        allowsRestrictedClaim: Bool = false
    ) {
        guard canCompleteTask(task) else { return }
        if let warningReason {
            pendingActionWarning = PendingEarnActionWarning(
                reason: warningReason,
                entityName: task.name,
                actionTitle: "Complete Task",
                continueAction: {
                    presentTaskClaim(
                        task,
                        price: price,
                        allowsRestrictedClaim: true
                    )
                }
            )
            return
        }

        guard allowsRestrictedClaim || !taskDependencyStore.isTaskBlocked(
            task,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            showingBlockedTaskAlert = true
            return
        }

        claimRoute = TaskClaimRoute(
            task: task,
            price: price,
            allowsRestrictedClaim: allowsRestrictedClaim
        )
    }

    private func completeTask(
        _ task: TaskItem,
        price: Int,
        adjustmentBaseAmount: Int? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        allowsRestrictedClaim: Bool = false
    ) {
        guard canCompleteTask(task) else { return }
        guard allowsRestrictedClaim || !taskDependencyStore.isTaskBlocked(
            task,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            showingBlockedTaskAlert = true
            return
        }
        withAnimation(.default) {
            _ = TaskCompletionService.completeTask(
                taskID: task.id,
                sourceName: task.name,
                price: price,
                adjustmentBaseAmount: adjustmentBaseAmount,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                tradeStore: tradeStore,
                taskStore: taskStore,
                balanceStore: balanceStore
            )
        }
    }

    private func canCompleteTask(_ task: TaskItem) -> Bool {
        task.canTrade && tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) == nil
    }

    private func requestTaskRefund(_ task: TaskItem) {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .refunds
            return
        }

        guard let trade = tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) else { return }

        withAnimation(.default) {
            let refundTrade = TradeRefundService.refund(
                for: trade,
                tradeStore: tradeStore,
                balanceStore: balanceStore
            )
            guard refundTrade != nil else { return }
            showingRefundFeedback = true
        }
    }

    private func duplicateTask(_ task: TaskItem) {
        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: task,
            tagIDs: tagStore.tagsForTask(taskId: task.id).map(\.id),
            reminderDrafts: reminderStore.reminderDrafts(for: .task(task.id)),
            taskDependencies: taskDependencyStore.activeTaskDependencies(for: task.id),
            recurringTaskDependencies: taskDependencyStore.activeRecurringTaskDependencies(for: task.id)
        )
        EntityListViewCoordinator.scheduleDeferredAction {
            appNavigationStore.openNewEntityForm(snapshot: snapshot, originTab: .earn)
        }
    }

    private func duplicateRecurringTask(_ recurringTask: RecurringTask) {
        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: recurringTask,
            tagIDs: tagStore.tagsForRecurringTask(recurringTaskId: recurringTask.id).map(\.id),
            reminderDrafts: reminderStore.reminderDrafts(for: .recurringTask(recurringTask.id))
        )
        EntityListViewCoordinator.scheduleDeferredAction {
            appNavigationStore.openNewEntityForm(snapshot: snapshot, originTab: .earn)
        }
    }

    private func queueScrollToRowIfVisible(_ rowID: EarnListRowID) {
        EntityListViewCoordinator.queueScrollToVisibleItem(
            rowID,
            visibleIDs: visibleRowIDs(),
            highlightedID: &highlightedRowID,
            pendingScrollTargetID: &pendingScrollTargetID
        )
    }

    private func scheduleNewRowHighlightFade(for rowID: EarnListRowID) {
        EntityListViewCoordinator.scheduleHighlightFade(
            for: rowID,
            highlightedID: { highlightedRowID },
            setHighlightedID: { highlightedRowID = $0 }
        )
    }

    @MainActor
    private func openPendingEarnFormIfNeeded() {
        guard appNavigationStore.selectedTab == .earn else { return }
        guard let request = appNavigationStore.pendingEntityFormRequest else { return }

        switch request.route {
        case .task(let taskID):
            guard taskFormRoute == nil,
                  !appNavigationStore.isPresentingNewEntityForm,
                  let task = taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil })
            else { return }
            openTaskChangeForm(task, focus: nil)
            appNavigationStore.clearPendingEntityFormRequest(id: request.id)
        case .recurringTask(let recurringTaskID):
            guard recurringTaskFormRoute == nil,
                  !appNavigationStore.isPresentingNewEntityForm,
                  let recurringTask = recurringTaskStore.recurringTasks.first(where: { $0.id == recurringTaskID && $0.deletedAt == nil })
            else { return }
            openRecurringTaskChangeForm(recurringTask, focus: nil)
            appNavigationStore.clearPendingEntityFormRequest(id: request.id)
        case .reward:
            return
        }
    }

    @MainActor
    private func revealPendingEarnIfNeeded() {
        guard appNavigationStore.selectedTab == .earn else { return }
        guard let request = appNavigationStore.pendingEntityRevealRequest else { return }

        switch request.route {
        case .task(let taskID):
            queueScrollToRowIfVisible(.task(taskID))
        case .recurringTask(let recurringTaskID):
            queueScrollToRowIfVisible(.recurringTask(recurringTaskID))
        case .reward:
            return
        }

        appNavigationStore.clearPendingEntityRevealRequest(id: request.id)
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }
}

#Preview {
    let authManager = AuthManager(
        apiClient: AppConfiguration.makeAuthAPIClient(),
        tokenStorage: KeychainTokenStorage(),
        appleEntitlementClient: StoreKitAppleEntitlementClient()
    )
    let taskStore = TaskStore()
    let recurringTaskStore = RecurringTaskStore()
    let tradeStore = TradeStore()

    EarnView()
        .environment(authManager)
        .environment(taskStore)
        .environment(TaskDependencyStore())
        .environment(RewardDependencyStore())
        .environment(recurringTaskStore)
        .environment(TagStore())
        .environment(tradeStore)
        .environment(BalanceStore())
        .environment(ReminderStore())
        .environment(AppNavigationStore())
        .environment(OmniSearchStore())
        .environment(ListPreferencesStore())
        .environment(UserSettingsStore())
        .environment(PremiumAccessStore())
}
