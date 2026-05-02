import SwiftUI

private struct TradeDetailRoute: Identifiable {
    let id: RecordID
}

struct TradeHistorySheetView: View {
    let filter: TradeHistoryFilter
    let title: String
    let detents: Set<PresentationDetent>

    @Environment(\.dismiss) private var dismiss
    @Environment(TradeStore.self) private var tradeStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(HabitStore.self) private var habitStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @State private var tradeDetailRoute: TradeDetailRoute?

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
        TradeHistoryBuilder.buildEntries(
            trades: tradeStore.trades,
            tasks: taskStore.tasks,
            habits: habitStore.habits,
            rewards: rewardStore.rewards,
            filter: filter
        )
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all:
            return "No Trades Yet"
        case .task:
            return "No Task Trades Yet"
        case .habit:
            return "No Habit Trades Yet"
        case .reward:
            return "No Reward Trades Yet"
        }
    }

    private var emptyStateDescription: String {
        switch filter {
        case .all:
            return "Habit claims and reward purchases will appear here."
        case .task:
            return "Completions for this task will appear here."
        case .habit:
            return "Claims for this habit will appear here."
        case .reward:
            return "Purchases for this reward will appear here."
        }
    }

    var body: some View {
        NavigationStack {
            Group {
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
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        // Behaviour: the sheet opens at medium height for a quick glance, but
        // the user can drag it to full-screen when they want to browse deeper.
        .presentationDetents(detents)
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
        .sheet(item: $tradeDetailRoute) { route in
            TradeDetailSheetView(
                tradeID: route.id,
                onOpenSource: {
                    dismiss()
                }
            )
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
                Button(role: .destructive) {
                    _ = TradeRefundService.refund(
                    for: trade,
                    tradeStore: tradeStore,
                    taskStore: taskStore,
                    balanceStore: balanceStore
                )
                } label: {
                    Label("Refund", systemImage: "arrow.uturn.backward")
                }
            }

            if let route = TradeSourceNavigationSupport.route(
                for: trade,
                tasks: taskStore.tasks,
                habits: habitStore.habits,
                rewards: rewardStore.rewards
            ) {
                Button {
                    openSource(route)
                } label: {
                    Label(route.viewActionTitle, systemImage: "arrow.up.forward.square")
                }
            }
        }
    }

    private func openSource(_ route: TradeSourceNavigationRoute) {
        switch route {
        case .task(let taskID):
            appNavigationStore.openTaskForm(taskID: taskID)
        case .habit(let habitID):
            appNavigationStore.openHabitForm(habitID: habitID)
        case .reward(let rewardID):
            appNavigationStore.openRewardForm(rewardID: rewardID)
        }
        dismiss()
    }
}

private struct TradeHistoryRow: View {
    let entry: TradeHistoryEntry

    private var amountColor: Color {
        if entry.isRefunded {
            return .secondary
        }
        return entry.isPositive ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if entry.isSourceDeleted {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Deleted source")
                }
            }

            if let statusText = entry.statusText {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(entry.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Text(entry.amountText)
                    Image(systemName: "cube.fill")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(amountColor)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TradeDetailSheetView: View {
    let tradeID: RecordID
    let onOpenSource: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(TradeStore.self) private var tradeStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(HabitStore.self) private var habitStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(AppNavigationStore.self) private var appNavigationStore

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
            habits: habitStore.habits,
            rewards: rewardStore.rewards
        )

        if let taskID = trade.taskId {
            let task = taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil })
            return SourceDetails(
                kindLabel: sourceSummary.kindLabel,
                name: sourceSummary.name,
                isDeleted: sourceSummary.isDeleted,
                openEditor: task == nil ? nil : {
                    appNavigationStore.openTaskForm(taskID: taskID)
                    onOpenSource()
                }
            )
        }

        if let habitID = trade.habitId {
            let habit = habitStore.habits.first(where: { $0.id == habitID && $0.deletedAt == nil })
            return SourceDetails(
                kindLabel: sourceSummary.kindLabel,
                name: sourceSummary.name,
                isDeleted: sourceSummary.isDeleted,
                openEditor: habit == nil ? nil : {
                    appNavigationStore.openHabitForm(habitID: habitID)
                    onOpenSource()
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
                    appNavigationStore.openRewardForm(rewardID: rewardID)
                    onOpenSource()
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
        let sign = trade.amount >= 0 ? "+" : "-"
        return "\(sign)\(abs(trade.amount))"
    }

    private func amountColor(for trade: Trade) -> Color {
        if trade.isRefundTrade {
            return .secondary
        }
        return trade.amount >= 0 ? .green : .orange
    }

    var body: some View {
        NavigationStack {
            Group {
                if let trade, let sourceDetails {
                    List {
                        Section("Trade") {
                            LabeledContent("Amount") {
                                HStack(spacing: 4) {
                                    Text(amountText(for: trade))
                                    Image(systemName: "cube.fill")
                                }
                                .foregroundStyle(amountColor(for: trade))
                            }

                            LabeledContent("Created") {
                                Text(trade.createdAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                            }

                            LabeledContent("Status") {
                                Text(trade.isRefundTrade ? "Refund" : "Active")
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
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.square")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Text(sourceDetails.name)
                                        .foregroundStyle(sourceDetails.isDeleted ? .secondary : .primary)

                                    if sourceDetails.isDeleted {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if tradeStore.canRefundTrade(trade) {
                            Section {
                                Button("Refund", role: .destructive) {
                                    _ = TradeRefundService.refund(
                                        for: trade,
                                        tradeStore: tradeStore,
                                        taskStore: taskStore,
                                        balanceStore: balanceStore
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ContentUnavailableView(
                        "Trade Unavailable",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("This trade could not be found.")
                    )
                }
            }
            .navigationTitle("Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }
}

#Preview {
    TradeHistorySheetView()
        .environment(TradeStore())
        .environment(TaskStore())
        .environment(HabitStore())
        .environment(RewardStore())
        .environment(BalanceStore())
        .environment(AppNavigationStore())
}
