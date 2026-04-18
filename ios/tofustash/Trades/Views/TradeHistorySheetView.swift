import SwiftUI

struct TradeHistorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TradeStore.self) private var tradeStore
    @Environment(HabitStore.self) private var habitStore
    @Environment(RewardStore.self) private var rewardStore

    // Computed property — like deriving `const rows = useMemo(...)` from store
    // state in React. Swift recalculates it on access, and SwiftUI refreshes
    // the view when any observed dependency used here changes.
    private var entries: [TradeHistoryEntry] {
        TradeHistoryBuilder.buildEntries(
            trades: tradeStore.trades,
            habits: habitStore.habits,
            rewards: rewardStore.rewards
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Trades Yet",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("Habit claims and reward purchases will appear here.")
                    )
                } else {
                    List(entries) { entry in
                        TradeHistoryRow(entry: entry)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Trades")
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
        .presentationDetents([.medium, .large])
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
