import SwiftUI

private struct TradeDetailRoute: Identifiable {
    let id: RecordID
}

private enum TradeSourceEditorRoute: Identifiable {
    case task(TaskItem)
    case recurringTask(RecurringTask)
    case reward(Reward)

    var id: String {
        switch self {
        case .task(let task):
            return "task:\(task.id.rawValue)"
        case .recurringTask(let recurringTask):
            return "recurringTask:\(recurringTask.id.rawValue)"
        case .reward(let reward):
            return "reward:\(reward.id.rawValue)"
        }
    }
}

struct TradeHistorySheetView: View {
    @Environment(\.bochiTheme) private var theme
    let filter: TradeHistoryFilter
    let title: String
    let detents: Set<PresentationDetent>

    @Environment(\.dismiss) private var dismiss
    @Environment(TradeStore.self) private var tradeStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @State private var tradeDetailRoute: TradeDetailRoute?
    @State private var sourceEditorRoute: TradeSourceEditorRoute?
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var showingRefundFeedback = false

    init(
        filter: TradeHistoryFilter = .all,
        title: String = "Trades",
        detents: Set<PresentationDetent> = [.medium, .large]
    ) {
        self.filter = filter
        self.title = title
        self.detents = detents
    }

    // Computed property — like deriving `const rows = useMemo(...)` from store
    // state in React. Swift recalculates it on access, and SwiftUI refreshes
    // the view when any observed dependency used here changes.
    private var entries: [TradeHistoryEntry] {
        // Behaviour: refunds made from a nested trade detail sheet should
        // refresh this still-open history sheet immediately.
        _ = tradeStore.trades
        return TradeHistoryBuilder.buildEntries(
            trades: tradeStore.historyTrades(filter: filter),
            tasks: taskStore.tasks,
            recurringTasks: recurringTaskStore.recurringTasks,
            rewards: rewardStore.rewards,
            filter: filter,
            // The store query already returns newest-first rows using SQLite indexes.
            sortNewestFirst: false
        )
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all:
            return "No Trades Yet"
        case .task:
            return "No Task Trades Yet"
        case .recurringTask:
            return "No Recurring Task Trades Yet"
        case .reward:
            return "No Reward Trades Yet"
        }
    }

    private var emptyStateDescription: String {
        switch filter {
        case .all:
            return "Recurring task completions and reward purchases will appear here."
        case .task:
            return "Completions for this task will appear here."
        case .recurringTask:
            return "Completions for this recurring task will appear here."
        case .reward:
            return "Purchases for this reward will appear here."
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.appBackground()
                    .ignoresSafeArea()

                if showingRefundFeedback {
                    RefundFeedbackView {
                        showingRefundFeedback = false
                    }
                    .transition(.opacity)
                } else {
                    historyContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingRefundFeedback)
            .navigationTitle(showingRefundFeedback ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showingRefundFeedback {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        // Behaviour: the sheet opens at medium height for a quick glance, but
        // the user can drag it to full-screen when they want to browse deeper.
        .presentationDetents(detents)
        .presentationBackground(theme.appBackground())
        .presentationContentInteraction(.scrolls)
        .sheet(item: $tradeDetailRoute) { route in
            TradeDetailSheetView(
                tradeID: route.id
            )
        }
        .sheet(item: $sourceEditorRoute) { route in
            TradeSourceEditorSheet(route: route)
        }
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                emptyStateTitle,
                systemImage: "arrow.left.arrow.right",
                description: Text(emptyStateDescription)
            )
        } else {
            List(entries) { entry in
                Button {
                    tradeDetailRoute = TradeDetailRoute(id: entry.id)
                } label: {
                    TradeHistoryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    tradeRowMenu(for: entry)
                }
                .listRowBackground(theme.appBackground())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
        }
    }

    @ViewBuilder
    private func tradeRowMenu(for entry: TradeHistoryEntry) -> some View {
        if let trade = tradeStore.trades.first(where: { $0.id == entry.id && $0.deletedAt == nil }) {
            Button {
                tradeDetailRoute = TradeDetailRoute(id: trade.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if tradeStore.canRefundTrade(trade) {
                Button {
                    requestRefund(trade)
                } label: {
                    Label(
                        hasPremiumAccess ? "Refund" : "Refund (Premium)",
                        systemImage: hasPremiumAccess ? "arrow.uturn.backward" : "crown"
                    )
                    .foregroundStyle(theme.destructiveText())
                }
            }

            if let route = TradeSourceNavigationSupport.route(
                for: trade,
                tasks: taskStore.tasks,
                recurringTasks: recurringTaskStore.recurringTasks,
                rewards: rewardStore.rewards
            ) {
                Button {
                    openSource(route)
                } label: {
                    Label(route.viewActionTitle, systemImage: "pencil")
                }
            }
        }
    }

    private func openSource(_ route: TradeSourceNavigationRoute) {
        switch route {
        case .task(let taskID):
            guard let task = taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil }) else { return }
            sourceEditorRoute = .task(task)
        case .recurringTask(let recurringTaskID):
            guard let recurringTask = recurringTaskStore.recurringTasks.first(where: { $0.id == recurringTaskID && $0.deletedAt == nil }) else { return }
            sourceEditorRoute = .recurringTask(recurringTask)
        case .reward(let rewardID):
            guard let reward = rewardStore.rewards.first(where: { $0.id == rewardID && $0.deletedAt == nil }) else { return }
            sourceEditorRoute = .reward(reward)
        }
    }

    private func requestRefund(_ trade: Trade) {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .refunds
            return
        }

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

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }
}

private struct TradeHistoryRow: View {
    @Environment(\.bochiTheme) private var theme
    let entry: TradeHistoryEntry

    private var amountColor: Color {
        if entry.isRefunded {
            return theme.secondaryText()
        }
        return entry.isPositive ? theme.positiveText() : theme.warningText()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(theme.primaryText())
                    .lineLimit(1)

                if entry.isSourceDeleted {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText())
                        .accessibilityLabel("Deleted source")
                }
            }

            if let statusText = entry.statusText {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText())
            }

            if !entry.adjustmentTexts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.adjustmentTexts, id: \.self) { adjustmentText in
                        Label(adjustmentText, systemImage: "slider.horizontal.3")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText())
            }

            HStack(alignment: .firstTextBaseline) {
                Text(entry.dateText)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText())

                Spacer()

                HStack(spacing: 6) {
                    if let originalAmountText = entry.originalAmountText {
                        PointsAmountLabel(text: originalAmountText)
                            .strikethrough()
                            .foregroundStyle(theme.secondaryText())
                    }
                    PointsAmountLabel(text: entry.amountText)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(amountColor)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TradeDetailSheetView: View {
    @Environment(\.bochiTheme) private var theme
    let tradeID: RecordID

    @Environment(\.dismiss) private var dismiss
    @Environment(TradeStore.self) private var tradeStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @State private var sourceEditorRoute: TradeSourceEditorRoute?
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var showingRefundFeedback = false

    private struct SourceDetails {
        let kindLabel: String
        let name: String
        let isDeleted: Bool
        let openEditor: (() -> Void)?
    }

    private var trade: Trade? {
        tradeStore.trades.first(where: { $0.id == tradeID })
    }

    private var sourceDetails: SourceDetails? {
        guard let trade else { return nil }
        let sourceSummary = TradeHistoryBuilder.sourceSummary(
            for: trade,
            tasks: taskStore.tasks,
            recurringTasks: recurringTaskStore.recurringTasks,
            rewards: rewardStore.rewards
        )

        if let taskID = trade.taskId {
            let task = taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil })
            return SourceDetails(
                kindLabel: sourceSummary.kindLabel,
                name: sourceSummary.name,
                isDeleted: sourceSummary.isDeleted,
                openEditor: task == nil ? nil : {
                    sourceEditorRoute = task.map(TradeSourceEditorRoute.task)
                }
            )
        }

        if let recurringTaskID = trade.recurringTaskId {
            let recurringTask = recurringTaskStore.recurringTasks.first(where: { $0.id == recurringTaskID && $0.deletedAt == nil })
            return SourceDetails(
                kindLabel: sourceSummary.kindLabel,
                name: sourceSummary.name,
                isDeleted: sourceSummary.isDeleted,
                openEditor: recurringTask == nil ? nil : {
                    sourceEditorRoute = recurringTask.map(TradeSourceEditorRoute.recurringTask)
                }
            )
        }

        if let rewardID = trade.rewardId {
            let reward = rewardStore.rewards.first(where: { $0.id == rewardID && $0.deletedAt == nil })
            return SourceDetails(
                kindLabel: sourceSummary.kindLabel,
                name: sourceSummary.name,
                isDeleted: sourceSummary.isDeleted,
                openEditor: reward == nil ? nil : {
                    sourceEditorRoute = reward.map(TradeSourceEditorRoute.reward)
                }
            )
        }

        return SourceDetails(
            kindLabel: sourceSummary.kindLabel,
            name: sourceSummary.name,
            isDeleted: sourceSummary.isDeleted,
            openEditor: nil
        )
    }

    private func amountText(for trade: Trade) -> String {
        if trade.tradeKind.isVault, let vaultAmountMicro = trade.vaultAmountMicro {
            let sign = vaultAmountMicro >= 0 ? "+" : "-"
            return "\(sign)\(VaultAmount.formatted(abs(vaultAmountMicro)))"
        }

        let sign = trade.amount >= 0 ? "+" : "-"
        return "\(sign)\(abs(trade.amount))"
    }

    private func originalAmountText(for trade: Trade) -> String? {
        trade.adjustmentBaseAmount.map { baseAmount in
            let sign = baseAmount >= 0 ? "+" : "-"
            return "\(sign)\(abs(baseAmount))"
        }
    }

    private func amountColor(for trade: Trade) -> Color {
        if trade.isRefundTrade {
            return theme.secondaryText()
        }
        if trade.tradeKind.isVault, let vaultAmountMicro = trade.vaultAmountMicro {
            return vaultAmountMicro >= 0 ? theme.positiveText() : theme.warningText()
        }
        return trade.amount >= 0 ? theme.positiveText() : theme.warningText()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.appBackground()
                    .ignoresSafeArea()

                if showingRefundFeedback {
                    RefundFeedbackView {
                        dismiss()
                    }
                    .transition(.opacity)
                } else {
                    tradeDetailContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingRefundFeedback)
            .navigationTitle(showingRefundFeedback ? "" : "Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showingRefundFeedback {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.appBackground())
        .sheet(item: $sourceEditorRoute) { route in
            TradeSourceEditorSheet(route: route)
        }
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
    }

    @ViewBuilder
    private var tradeDetailContent: some View {
        if let trade, let sourceDetails {
            List {
                Section("Trade") {
                    LabeledContent("Amount") {
                        HStack(spacing: 6) {
                            if let originalAmountText = originalAmountText(for: trade) {
                                PointsAmountLabel(text: originalAmountText)
                                    .strikethrough()
                                    .foregroundStyle(theme.secondaryText())
                            }
                            PointsAmountLabel(text: amountText(for: trade))
                        }
                        .foregroundStyle(amountColor(for: trade))
                    }

                    LabeledContent("Created") {
                        Text(trade.createdAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                    }

                    LabeledContent("Status") {
                        Text(trade.isRefundTrade ? "Refund" : "Active")
                    }

                    if trade.oneTimeAdjustmentMultiplier != nil {
                        LabeledContent("One-time Adjustment") {
                            Text("Applied")
                        }
                    }
                }

                Section(sourceDetails.kindLabel) {
                    if let openEditor = sourceDetails.openEditor {
                        Button {
                            openEditor()
                        } label: {
                            HStack {
                                Text(sourceDetails.name)
                                if sourceDetails.isDeleted {
                                    Image(systemName: "trash")
                                        .foregroundStyle(theme.secondaryText())
                                }
                                Spacer()
                                Image(systemName: "pencil")
                                    .foregroundStyle(theme.secondaryText())
                            }
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(sourceDetails.name)
                                .foregroundStyle(sourceDetails.isDeleted ? theme.secondaryText() : theme.primaryText())

                            if sourceDetails.isDeleted {
                                Image(systemName: "trash")
                                    .foregroundStyle(theme.secondaryText())
                            }
                        }
                    }
                }

                if tradeStore.canRefundTrade(trade) {
                    Section {
                        Button {
                            requestRefund(trade)
                        } label: {
                            HStack {
                                Text("Refund")
                                if !hasPremiumAccess {
                                    PremiumFeatureBadge()
                                }
                            }
                        }
                        .foregroundStyle(theme.destructiveText())
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
        } else {
            ContentUnavailableView(
                "Trade Unavailable",
                systemImage: "arrow.left.arrow.right",
                description: Text("This trade could not be found.")
            )
        }
    }

    private func requestRefund(_ trade: Trade) {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .refunds
            return
        }

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

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }
}

private struct TradeSourceEditorSheet: View {
    let route: TradeSourceEditorRoute

    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskDependencyStore.self) private var taskDependencyStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(ReminderStore.self) private var reminderStore

    var body: some View {
        switch route {
        case .task(let task):
            TaskFormView(
                mode: .change(task),
                onDelete: { task in
                    let deletedAt = Date()
                    EntityDeletionService.deleteTask(
                        task,
                        reminderStore: reminderStore,
                        taskDependencyStore: taskDependencyStore,
                        rewardDependencyStore: rewardDependencyStore,
                        taskStore: taskStore,
                        deletedAt: deletedAt
                    )
                }
            )
        case .recurringTask(let recurringTask):
            RecurringTaskFormView(
                mode: .change(recurringTask),
                onDelete: { recurringTask in
                    let deletedAt = Date()
                    EntityDeletionService.deleteRecurringTask(
                        recurringTask,
                        reminderStore: reminderStore,
                        taskDependencyStore: taskDependencyStore,
                        rewardDependencyStore: rewardDependencyStore,
                        recurringTaskStore: recurringTaskStore,
                        deletedAt: deletedAt
                    )
                }
            )
        case .reward(let reward):
            RewardFormView(
                mode: .change(reward),
                onDelete: { reward in
                    let deletedAt = Date()
                    EntityDeletionService.deleteReward(
                        reward,
                        rewardDependencyStore: rewardDependencyStore,
                        rewardStore: rewardStore,
                        deletedAt: deletedAt
                    )
                }
            )
        }
    }
}

#Preview {
    let previewAuthManager = AuthManager(
        apiClient: AppConfiguration.makeAuthAPIClient(),
        tokenStorage: KeychainTokenStorage(),
        appleEntitlementClient: StoreKitAppleEntitlementClient()
    )

    TradeHistorySheetView()
        .environment(previewAuthManager)
        .environment(TradeStore())
        .environment(TaskStore())
        .environment(RecurringTaskStore())
        .environment(RewardStore())
        .environment(RewardDependencyStore())
        .environment(BalanceStore())
        .environment(AppNavigationStore())
        .environment(PremiumAccessStore())
}
