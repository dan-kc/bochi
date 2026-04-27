import SwiftUI

struct TradeHistorySheetView: View {
    let filter: TradeHistoryFilter
    let title: String
    let detents: Set<PresentationDetent>

    @Environment(\.dismiss) private var dismiss
    @Environment(TradeStore.self) private var tradeStore
    @Environment(HabitStore.self) private var habitStore
    @Environment(RewardStore.self) private var rewardStore

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
            habits: habitStore.habits,
            rewards: rewardStore.rewards,
            filter: filter
        )
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all:
            return "No Trades Yet"
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
                        TradeHistoryRow(entry: entry)
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
    }
}

private struct TradeHistoryRow: View {
    let entry: TradeHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

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
                .foregroundStyle(entry.isPositive ? .green : .orange)
            }
        }
        // Behaviour: each row is informational only; there is no secondary tap
        // action, so the full row reads as static history rather than a button.
        .padding(.vertical, 4)
    }
}

#Preview {
    TradeHistorySheetView()
        .environment(TradeStore())
        .environment(HabitStore())
        .environment(RewardStore())
}
