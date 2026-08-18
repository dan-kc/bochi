import SwiftUI

private enum OmniSearchEditRoute: Identifiable {
    case task(TaskItem)
    case recurringTask(RecurringTask)
    case reward(Reward)

    var id: RecordID {
        switch self {
        case .task(let task):
            task.id
        case .recurringTask(let recurringTask):
            recurringTask.id
        case .reward(let reward):
            reward.id
        }
    }
}

private struct PendingOmniSearchActionWarning: Identifiable {
    let id = UUID()
    let reason: EntityActionGateReason
    let entityName: String
    let actionTitle: String
    let continueAction: () -> Void
}

private struct OmniSearchProjectionToken: Equatable {
    let preferences: EntityListPreferences
    let tasks: [TaskItem]
    let recurringTasks: [RecurringTask]
    let rewards: [Reward]
    let taskTaskDependencies: [TaskTaskDependency]
    let taskRecurringTaskDependencies: [TaskRecurringTaskDependency]
    let rewardTaskDependencies: [RewardTaskDependency]
    let rewardRecurringTaskDependencies: [RewardRecurringTaskDependency]
    let tags: [Tag]
    let taskTags: [TaskTag]
    let recurringTaskTags: [RecurringTaskTag]
    let rewardTags: [RewardTag]
    let trades: [Trade]
    let hasPremiumAccess: Bool
}

struct OmniSearchOverlay: View {
    @Environment(\.bochiTheme) private var theme
    private static var topFadeHiddenControlsHeight: CGFloat { 106 }
    private static var topFadeVisibleControlsExtension: CGFloat { 72 }
    private static var topFadeMaximumOpacity: Double { 0.90 }
    private static var topFadeCurveStrength: Double { 0.65 }

    @Environment(OmniSearchStore.self) private var omniSearchStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @Environment(\.omniSearchNamespace) private var searchNamespace

    @State private var editRoute: OmniSearchEditRoute?
    @State private var taskClaimRoute: TaskClaimRoute?
    @State private var recurringTaskTradeRoute: RecurringTaskTradeRoute?
    @State private var rewardPurchaseRoute: RewardPurchaseRoute?
    @State private var historyTask: TaskItem?
    @State private var historyRecurringTask: RecurringTask?
    @State private var historyReward: Reward?
    @State private var taskToDelete: TaskItem?
    @State private var recurringTaskToDelete: RecurringTask?
    @State private var rewardToDelete: Reward?
    @State private var pendingActionWarning: PendingOmniSearchActionWarning?
    @State private var premiumUpsellFeature: PremiumUpsellFeature?
    @State private var showingRefundFeedback = false
    @State private var query = ""
    @State private var projection: OmniSearchProjection?
    @State private var projectionTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool

    private let resultMetadataSpacing: CGFloat = 14

    private var projectionToken: OmniSearchProjectionToken {
        OmniSearchProjectionToken(
            preferences: omniSearchStore.preferences,
            tasks: taskStore.tasks,
            recurringTasks: recurringTaskStore.recurringTasks,
            rewards: rewardStore.rewards,
            taskTaskDependencies: taskDependencyStore.taskTaskDependencies,
            taskRecurringTaskDependencies: taskDependencyStore.taskRecurringTaskDependencies,
            rewardTaskDependencies: rewardDependencyStore.rewardTaskDependencies,
            rewardRecurringTaskDependencies: rewardDependencyStore.rewardRecurringTaskDependencies,
            tags: tagStore.tags,
            taskTags: tagStore.taskTags,
            recurringTaskTags: tagStore.recurringTaskTags,
            rewardTags: tagStore.rewardTags,
            trades: tradeStore.trades,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    var body: some View {
        if omniSearchStore.isPresented {
            overlayBody
        }
    }

    private var overlayBody: some View {
        presentationHost(lifecycleHost(navigationBody))
            .transition(.opacity)
    }

    private var navigationBody: some View {
        NavigationStack {
            resultsList
                .overlay(alignment: .top) {
                    topFadeOverlay
                }
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    searchAccessory
                }
        }
        .background(theme.appBackground())
    }

    private func lifecycleHost<Content: View>(_ content: Content) -> some View {
        content
            .omniSearchProjectionLifecycle(
                query: query,
                projectionToken: projectionToken,
                appear: appear,
                disappear: disappear,
                queryChanged: queryChanged,
                refreshProjection: updateProjection
            )
    }

    private func presentationHost<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $editRoute) { route in
                switch route {
                case .task(let task):
                    TaskFormView(
                        mode: .change(task),
                        onDelete: deleteTask,
                        onDuplicate: duplicateTask
                    )
                case .recurringTask(let recurringTask):
                    RecurringTaskFormView(
                        mode: .change(recurringTask),
                        onDelete: deleteRecurringTask,
                        onDuplicate: duplicateRecurringTask
                    )
                case .reward(let reward):
                    RewardFormView(
                        mode: .change(reward),
                        onDelete: deleteReward,
                        onDuplicate: duplicateReward
                    )
                }
            }
            .sheet(item: $taskClaimRoute) { route in
                TaskClaimModalView(
                    task: route.task,
                    price: route.price,
                    hasPremiumAccess: hasPremiumAccess
                ) { adjustedPrice, adjustmentBaseAmount, oneTimeAdjustmentMultiplier in
                    completeTask(
                        route.task,
                        price: adjustedPrice,
                        adjustmentBaseAmount: adjustmentBaseAmount,
                        oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                        allowsRestrictedClaim: route.allowsRestrictedClaim
                    )
                }
            }
            .sheet(item: $recurringTaskTradeRoute) { route in
                TradeModalView(
                    recurringTask: route.recurringTask,
                    quote: route.quote,
                    allowsRestrictedClaim: route.allowsRestrictedClaim
                )
            }
            .sheet(item: $rewardPurchaseRoute) { route in
                RewardPurchaseModalView(
                    reward: route.reward,
                    quote: route.quote,
                    allowsRestrictedPurchase: route.allowsRestrictedPurchase
                )
            }
            .sheet(item: $historyTask) { task in
                TradeHistorySheetView(filter: .task(task.id), detents: [.large])
            }
            .sheet(item: $historyRecurringTask) { recurringTask in
                TradeHistorySheetView(filter: .recurringTask(recurringTask.id), detents: [.large])
            }
            .sheet(item: $historyReward) { reward in
                TradeHistorySheetView(filter: .reward(reward.id), detents: [.large])
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
            .alert("Delete Task?", isPresented: taskDeleteConfirmationBinding) {
                Button("Delete") {
                    if let task = taskToDelete {
                        deleteTask(task)
                    }
                }
                Button("Cancel", role: .cancel) { taskToDelete = nil }
            } message: {
                Text("Your balance will not be affected.")
            }
            .alert("Delete Recurring Task?", isPresented: recurringTaskDeleteConfirmationBinding) {
                Button("Delete") {
                    if let recurringTask = recurringTaskToDelete {
                        deleteRecurringTask(recurringTask)
                    }
                }
                Button("Cancel", role: .cancel) { recurringTaskToDelete = nil }
            } message: {
                Text("Your balance will not be affected.")
            }
            .alert("Delete Reward?", isPresented: rewardDeleteConfirmationBinding) {
                Button("Delete") {
                    if let reward = rewardToDelete {
                        deleteReward(reward)
                    }
                }
                Button("Cancel", role: .cancel) { rewardToDelete = nil }
            } message: {
                Text("Your balance will not be affected.")
            }
    }

    private var resultsList: some View {
        List {
            if let projection {
                if projection.rows.isEmpty {
                    emptyResultsRow(projection.snapshot.message)
                } else {
                    resultRows(projection.rows)
                }
            } else {
                loadingResultsRow
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .contentMargins(.top, 36, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectHidden(true, for: .top)
        .animation(.default, value: projection?.rowIDs)
        .background(theme.appBackground())
    }

    @ViewBuilder
    private func resultRows(_ rows: [OmniSearchRowModel]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            EntityListRowSurface(
                showsDivider: index < rows.count - 1,
                role: row.role
            ) {
                rowView(row)
            }
            .contextMenu {
                rowMenu(row)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private func emptyResultsRow(_ message: String?) -> some View {
        ContentUnavailableView(
            message == nil ? "No Results" : "Start Typing",
            systemImage: "magnifyingglass",
            description: Text(message ?? "Try another name or turn filters back on.")
        )
        .frame(maxWidth: .infinity, minHeight: 260)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var loadingResultsRow: some View {
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: 260)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var topFadeOverlay: some View {
        LinearGradient(
            stops: topFadeStops(color: theme.appBackground()),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Self.topFadeHiddenControlsHeight + Self.topFadeVisibleControlsExtension)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private func topFadeStops(color: Color, samples: Int = 10) -> [Gradient.Stop] {
        (0...samples).map { index in
            let location = Double(index) / Double(samples)
            let easedLocation = softenedEaseInOutCubic(location)
            let opacity = Self.topFadeMaximumOpacity * (1 - easedLocation)

            return .init(color: color.opacity(opacity), location: location)
        }
    }

    private func softenedEaseInOutCubic(_ value: Double) -> Double {
        let cubic = easeInOutCubic(value)

        return value + (cubic - value) * Self.topFadeCurveStrength
    }

    private func easeInOutCubic(_ value: Double) -> Double {
        if value < 0.5 {
            return 4 * value * value * value
        }

        return 1 - pow(-2 * value + 2, 3) / 2
    }

    private var searchAccessory: some View {
        HStack(spacing: 3) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.secondaryText())
                    .omniSearchMatchedGeometry(id: "entity.search.icon", namespace: searchNamespace, isSource: true)

                TextField("Search tasks, recurring, rewards", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFieldFocused)
                    .submitLabel(.done)
                    .font(.body.weight(.medium))

                if !query.isEmpty {
                    Button {
                        query = ""
                        focusSearchField()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.secondaryText())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search text")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .glassEffect(.regular, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.subtleBorder(), lineWidth: 1)
            }
            .shadow(color: theme.highContrastText().opacity(0.06), radius: 14, y: 8)
            .contentShape(Capsule())
            .onTapGesture {
                focusSearchField()
            }
            .omniSearchMatchedGeometry(id: "entity.search.container", namespace: searchNamespace, isSource: true)

            EntityFloatingGlassButton {
                dismissOmniSearch()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText())
                    .rotationEffect(.degrees(45))
                    .omniSearchMatchedGeometry(id: "entity.add.icon", namespace: searchNamespace, isSource: true)
            }
            .omniSearchMatchedGeometry(id: "entity.add.container", namespace: searchNamespace, isSource: true)
            .accessibilityLabel("Close search")
            .accessibilityIdentifier("omniSearch.close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .background(.clear)
    }

    private func appear() {
        query = omniSearchStore.text
        updateProjection()
        focusSearchField()
    }

    private func disappear() {
        isSearchFieldFocused = false
        projectionTask?.cancel()
        projectionTask = nil
    }

    private func dismissOmniSearch() {
        isSearchFieldFocused = false
        omniSearchStore.collapse()
    }

    private func queryChanged(_ oldValue: String, _ newValue: String) {
        omniSearchStore.text = newValue
        updateProjection()
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            guard omniSearchStore.isPresented else { return }
            isSearchFieldFocused = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard omniSearchStore.isPresented else { return }
            isSearchFieldFocused = true
        }
    }

    private var taskDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { taskToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    taskToDelete = nil
                }
            }
        )
    }

    private var recurringTaskDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { recurringTaskToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    recurringTaskToDelete = nil
                }
            }
        )
    }

    private var rewardDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { rewardToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    rewardToDelete = nil
                }
            }
        )
    }

    private func updateProjection() {
        projectionTask?.cancel()

        let inputs = OmniSearchProjectionInputs(
            queryText: query,
            preferences: omniSearchStore.preferences,
            tasks: taskStore.tasks,
            recurringTasks: recurringTaskStore.recurringTasks,
            rewards: rewardStore.rewards,
            taskTagsByID: tagStore.tagsByTaskID(),
            recurringTaskTagsByID: tagStore.tagsByRecurringTaskID(),
            rewardTagsByID: tagStore.tagsByRewardID(),
            taskTaskDependencies: taskDependencyStore.taskTaskDependencies,
            taskRecurringTaskDependencies: taskDependencyStore.taskRecurringTaskDependencies,
            rewardTaskDependencies: rewardDependencyStore.rewardTaskDependencies,
            rewardRecurringTaskDependencies: rewardDependencyStore.rewardRecurringTaskDependencies,
            latestTaskTradesByTaskID: tradeStore.latestUnrefundedTaskTradesByTaskID(),
            recurringTaskCompletionCountsByRecurringTaskID: tradeStore.recurringTaskCompletionCountsByRecurringTaskID(),
            recurringTaskTradeDatesByRecurringTaskID: tradeStore.recurringTaskTradeDatesByRecurringTaskID(),
            rewardPurchaseDatesByRewardID: tradeStore.rewardPurchaseDatesByRewardID(),
            latestRewardPurchasesByRewardID: tradeStore.latestUnrefundedRewardPurchasesByRewardID(),
            hasPremiumAccess: hasPremiumAccess,
            now: Date()
        )

        projectionTask = Task.detached(priority: .userInitiated) {
            let nextProjection = OmniSearchProjectionBuilder.makeProjection(inputs: inputs)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                guard query == inputs.queryText, omniSearchStore.preferences == inputs.preferences else { return }
                projection = nextProjection
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: OmniSearchRowModel) -> some View {
        switch row {
        case .task(let taskRow):
            taskRowView(taskRow)
        case .recurringTask(let recurringTaskRow):
            recurringTaskRowView(recurringTaskRow)
        case .reward(let rewardRow):
            rewardRowView(rewardRow)
        }
    }

    private func taskRowView(_ row: OmniSearchTaskRowModel) -> some View {
        let task = row.task
        let rowStatus = row.listStatus
        let gateReason = EntityActionGateSupport.reason(isLocked: row.isBlocked, isHidden: task.hidden)

        return HStack(alignment: rowStatus == nil ? .bottom : .center) {
            EntityListRowText(
                name: task.name,
                description: task.description,
                metadataItems: taskResultMetadata(task: task),
                metadataSpacing: resultMetadataSpacing,
                pills: EntityListRowPillSupport.taskPills(task: task, tags: row.tags),
                role: .task,
                isNameStruckThrough: row.isCompleted,
                showsDetails: userSettingsStore.showsEntityRowDetails
            )

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
                        presentTaskClaim(task, price: row.price, warningReason: gateReason)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.isCompleted || row.isBlocked || task.hidden ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editRoute = .task(task) }
    }

    private func recurringTaskRowView(_ row: OmniSearchRecurringTaskRowModel) -> some View {
        let recurringTask = row.recurringTask
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
                metadataItems: recurringTaskResultMetadata(recurringTask: recurringTask),
                metadataSpacing: resultMetadataSpacing,
                pills: EntityListRowPillSupport.recurringTaskPills(recurringTask: recurringTask, tags: row.tags),
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
                            openTradeModal(for: recurringTask, quote: row.quote, warningReason: gateReason)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.isLocked || recurringTask.hidden ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editRoute = .recurringTask(recurringTask) }
    }

    private func rewardRowView(_ row: OmniSearchRewardRowModel) -> some View {
        let reward = row.reward
        let rowStatus = row.listStatus
        let gateReason = EntityActionGateSupport.reason(
            isLocked: row.isLocked || row.isBlocked,
            lockoutSummary: lockoutSummary(for: reward),
            isHidden: reward.hidden
        )

        return HStack(alignment: rowStatus == nil ? .bottom : .center) {
            EntityListRowText(
                name: reward.name,
                description: reward.description,
                metadataItems: rewardResultMetadata(reward: reward),
                metadataSpacing: resultMetadataSpacing,
                pills: EntityListRowPillSupport.rewardPills(reward: reward, tags: row.tags),
                role: .reward,
                showsDetails: userSettingsStore.showsEntityRowDetails
            )

            EntityListRowActionColumn {
                if let rowStatus {
                    EntityListRowStatusLabel(status: rowStatus, role: .reward)
                } else if reward.canPurchase {
                    VStack(alignment: .trailing, spacing: 4) {
                        EntityListRowPriceDeltaLabel(
                            percent: PriceDeltaSupport.percent(currentPrice: row.price, basePrice: reward.basePrice),
                            role: .reward
                        )
                        BochiActionButton(
                            amount: row.price,
                            polarity: .spending,
                            layout: .compact,
                            usesMainThemeStyle: gateReason != nil,
                            themeRoleOverride: .reward
                        ) {
                            openPurchaseModal(for: reward, quote: row.quote, warningReason: gateReason)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.isLocked || row.isBlocked || row.isSpent || reward.hidden ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editRoute = .reward(reward) }
    }

    private func taskResultMetadata(task: TaskItem) -> [EntityListRowMetadataItem] {
        [
            EntityListRowMetadataItem(
                id: "entity-type",
                label: "Task",
                icon: "checklist",
                accessibilityLabel: "Task"
            )
        ] + EntityListRowPillSupport.taskMetadata(task: task)
    }

    private func recurringTaskResultMetadata(recurringTask: RecurringTask) -> [EntityListRowMetadataItem] {
        [
            EntityListRowMetadataItem(
                id: "entity-type",
                label: "Task",
                icon: "checklist",
                accessibilityLabel: "Task"
            )
        ] + EntityListRowPillSupport.recurringTaskMetadata(recurringTask: recurringTask)
    }

    private func rewardResultMetadata(reward: Reward) -> [EntityListRowMetadataItem] {
        [
            EntityListRowMetadataItem(
                id: "entity-type",
                label: "Reward",
                icon: "gift",
                accessibilityLabel: "Reward"
            )
        ] + EntityListRowPillSupport.rewardMetadata(reward: reward)
    }

    @ViewBuilder
    private func rowMenu(_ row: OmniSearchRowModel) -> some View {
        switch row {
        case .task(let taskRow):
            taskRowMenu(taskRow)
        case .recurringTask(let recurringTaskRow):
            recurringTaskRowMenu(recurringTaskRow)
        case .reward(let rewardRow):
            rewardRowMenu(rewardRow)
        }
    }

    @ViewBuilder
    private func taskRowMenu(_ row: OmniSearchTaskRowModel) -> some View {
        let task = row.task

        if row.canComplete {
            Button {
                presentTaskClaim(
                    task,
                    price: row.price,
                    warningReason: EntityActionGateSupport.reason(isLocked: row.isBlocked, isHidden: task.hidden)
                )
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        } else if row.isCompleted {
            Button {
                requestTaskRefund(task)
            } label: {
                Label(
                    hasPremiumAccess ? "Refund" : "Refund (Premium)",
                    systemImage: hasPremiumAccess ? "arrow.uturn.backward" : "crown"
                )
            }
        }

        EntityRowContextMenuActions.editHistoryDelete(
            theme: theme,
            onEdit: { editRoute = .task(task) },
            onDuplicate: { duplicateTask(task) },
            onTogglePin: { taskStore.setPinned(id: task.id, pinned: !task.pinned) },
            isPinned: task.pinned,
            onToggleHidden: { taskStore.setHidden(id: task.id, hidden: !task.hidden) },
            isHidden: task.hidden,
            onViewHistory: { historyTask = task },
            onDelete: { taskToDelete = task }
        )
    }

    @ViewBuilder
    private func recurringTaskRowMenu(_ row: OmniSearchRecurringTaskRowModel) -> some View {
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
            onEdit: { editRoute = .recurringTask(recurringTask) },
            onDuplicate: { duplicateRecurringTask(recurringTask) },
            onTogglePin: { recurringTaskStore.setPinned(id: recurringTask.id, pinned: !recurringTask.pinned) },
            isPinned: recurringTask.pinned,
            onToggleHidden: { recurringTaskStore.setHidden(id: recurringTask.id, hidden: !recurringTask.hidden) },
            isHidden: recurringTask.hidden,
            onViewHistory: { historyRecurringTask = recurringTask },
            onDelete: { recurringTaskToDelete = recurringTask }
        )
    }

    @ViewBuilder
    private func rewardRowMenu(_ row: OmniSearchRewardRowModel) -> some View {
        let reward = row.reward

        if reward.canPurchase && !row.isSpent {
            Button {
                openPurchaseModal(
                    for: reward,
                    quote: row.quote,
                    warningReason: EntityActionGateSupport.reason(
                        isLocked: row.isLocked || row.isBlocked,
                        lockoutSummary: lockoutSummary(for: reward),
                        isHidden: reward.hidden
                    )
                )
            } label: {
                Label("Claim Reward", systemImage: "gift")
            }
        }

        if row.isSpent, row.canRefund {
            Button {
                requestRewardRefund(reward)
            } label: {
                Label(
                    hasPremiumAccess ? "Refund" : "Refund (Premium)",
                    systemImage: hasPremiumAccess ? "arrow.uturn.backward" : "crown"
                )
            }
        }

        EntityRowContextMenuActions.editHistoryDelete(
            theme: theme,
            onEdit: { editRoute = .reward(reward) },
            onDuplicate: { duplicateReward(reward) },
            onTogglePin: { rewardStore.setPinned(id: reward.id, pinned: !reward.pinned) },
            isPinned: reward.pinned,
            onToggleHidden: { rewardStore.setHidden(id: reward.id, hidden: !reward.hidden) },
            isHidden: reward.hidden,
            onViewHistory: { historyReward = reward },
            onDelete: { rewardToDelete = reward }
        )
    }

    private func presentTaskClaim(
        _ task: TaskItem,
        price: Int,
        warningReason: EntityActionGateReason? = nil,
        allowsRestrictedClaim: Bool = false
    ) {
        guard task.canTrade && tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) == nil else { return }
        if let warningReason {
            pendingActionWarning = PendingOmniSearchActionWarning(
                reason: warningReason,
                entityName: task.name,
                actionTitle: "Complete Task",
                continueAction: {
                    presentTaskClaim(task, price: price, allowsRestrictedClaim: true)
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
            return
        }

        taskClaimRoute = TaskClaimRoute(
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
        guard task.canTrade && tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) == nil else { return }
        guard allowsRestrictedClaim || !taskDependencyStore.isTaskBlocked(
            task,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
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

    private func openTradeModal(
        for recurringTask: RecurringTask,
        quote: RecurringTaskTradeQuote,
        warningReason: EntityActionGateReason? = nil
    ) {
        if let warningReason {
            pendingActionWarning = PendingOmniSearchActionWarning(
                reason: warningReason,
                entityName: recurringTask.name,
                actionTitle: "Complete Task",
                continueAction: {
                    recurringTaskTradeRoute = RecurringTaskTradeRoute(
                        recurringTask: recurringTask,
                        quote: quote,
                        allowsRestrictedClaim: true
                    )
                }
            )
            return
        }

        recurringTaskTradeRoute = RecurringTaskTradeRoute(recurringTask: recurringTask, quote: quote)
    }

    private func openPurchaseModal(
        for reward: Reward,
        quote: RewardPurchaseQuote,
        warningReason: EntityActionGateReason? = nil
    ) {
        if let warningReason {
            pendingActionWarning = PendingOmniSearchActionWarning(
                reason: warningReason,
                entityName: reward.name,
                actionTitle: "Buy Reward",
                continueAction: {
                    rewardPurchaseRoute = RewardPurchaseRoute(
                        reward: reward,
                        quote: quote,
                        allowsRestrictedPurchase: true
                    )
                }
            )
            return
        }

        rewardPurchaseRoute = RewardPurchaseRoute(reward: reward, quote: quote)
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

    private func requestRewardRefund(_ reward: Reward) {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .refunds
            return
        }
        guard let trade = tradeStore.latestRewardPurchase(rewardId: reward.id, includeRefunded: false) else { return }

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

    private func lockoutSummary(for reward: Reward) -> String? {
        guard let remainingSeconds = RewardLockout.remainingSeconds(
            reward: reward,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            return nil
        }

        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
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

    private func deleteReward(_ reward: Reward) {
        let deletedAt = Date()
        withAnimation(.default) {
            EntityDeletionService.deleteReward(
                reward,
                rewardDependencyStore: rewardDependencyStore,
                rewardStore: rewardStore,
                deletedAt: deletedAt
            )
            rewardToDelete = nil
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
            appNavigationStore.openNewEntityForm(snapshot: snapshot, originTab: .tasks)
        }
    }

    private func duplicateRecurringTask(_ recurringTask: RecurringTask) {
        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: recurringTask,
            tagIDs: tagStore.tagsForRecurringTask(recurringTaskId: recurringTask.id).map(\.id),
            reminderDrafts: reminderStore.reminderDrafts(for: .recurringTask(recurringTask.id))
        )
        EntityListViewCoordinator.scheduleDeferredAction {
            appNavigationStore.openNewEntityForm(snapshot: snapshot, originTab: .recurringTasks)
        }
    }

    private func duplicateReward(_ reward: Reward) {
        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: reward,
            tagIDs: tagStore.tagsForReward(rewardId: reward.id).map(\.id)
        )
        EntityListViewCoordinator.scheduleDeferredAction {
            appNavigationStore.openNewEntityForm(snapshot: snapshot, originTab: .rewards)
        }
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }
}

private extension OmniSearchTaskRowModel {
    var listStatus: EntityListRowStatus? {
        if isBlocked {
            return .locked
        }
        if task.hidden {
            return .hidden
        }
        if isCompleted {
            return .completed
        }
        return nil
    }
}

private extension OmniSearchRecurringTaskRowModel {
    var listStatus: EntityListRowStatus? {
        if isLocked {
            return .locked
        }
        if recurringTask.hidden {
            return .hidden
        }
        return nil
    }
}

private extension OmniSearchRewardRowModel {
    var listStatus: EntityListRowStatus? {
        if isLocked || isBlocked {
            return .locked
        }
        if reward.hidden {
            return .hidden
        }
        if isSpent {
            return .completed
        }
        return nil
    }
}
