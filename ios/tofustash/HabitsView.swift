import SwiftUI

struct HabitsView: View {
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    // State for the new habit form (FAB)
    @State private var showingNewForm = false

    // State for the change form — which habit is being edited and which
    // sub-modal to auto-open. Using an Identifiable binding with .sheet(item:)
    // is the idiomatic SwiftUI pattern for "present a sheet for a specific item."
    @State private var editingHabit: Habit? = nil
    @State private var editFocus: HabitFormFocus? = nil

    // State for the trade modal — which habit's trade modal is open.
    // Set when the user taps a price button on a habit list item.
    @State private var tradingHabit: Habit? = nil

    // Toast manager for showing recovery toasts when habits are discarded.
    @State private var toastManager = ToastManager()

    // Holds saved form state for recovery.
    @State private var recoveringPrefill: HabitFormSnapshot? = nil

    // Current time bucket for price calculations. Updated every 60 seconds
    // to detect when the 30-minute bucket changes.
    @State private var timeBucket = RewardCalculation.getCurrentTimeBucket()

    var body: some View {
        NavigationStack {
            ZStack {
                if habitStore.activeHabits.isEmpty {
                    ContentUnavailableView(
                        "No Habits Yet",
                        systemImage: "checkmark.circle",
                        description: Text("Tap + to create your first habit.")
                    )
                } else {
                    List(habitStore.activeHabits) { habit in
                        habitRow(habit)
                    }
                }
            }
            .navigationTitle("Habits")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    recoveringPrefill = nil
                    showingNewForm = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.blue, in: .circle)
                        .shadow(radius: 4)
                }
                .padding()
            }
            .sheet(isPresented: $showingNewForm) {
                HabitFormView(
                    mode: .new,
                    prefill: recoveringPrefill,
                    onDiscard: { snapshot in
                        showDiscardToast(snapshot: snapshot)
                    }
                )
            }
            .sheet(item: $editingHabit) { habit in
                HabitFormView(mode: .change(habit), initialFocus: editFocus)
            }
            .sheet(item: $tradingHabit) { habit in
                TradeModalView(habit: habit)
            }
            .overlay {
                ToastOverlay(toastManager: toastManager)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    timeBucket = RewardCalculation.getCurrentTimeBucket()
                }
            }
        }
    }

    private func showDiscardToast(snapshot: HabitFormSnapshot) {
        recoveringPrefill = nil
        toastManager.show(
            message: "Habit Discarded",
            actionLabel: "Recover"
        ) {
            recoveringPrefill = snapshot
            showingNewForm = true
        }
    }

    // Whether a habit has the required properties to calculate a price.
    // Both frequency and difficulty rank must be set for the reward formula
    // to produce meaningful results — without frequency, the frequency
    // multiplier F is always 1 (no diminishing returns), and without
    // difficulty rank, D defaults to 0.5 (no relative positioning).
    private func habitCanTrade(_ habit: Habit) -> Bool {
        habit.frequency != nil && habit.difficultyRank != nil
    }

    // Calculate the current reward price for a habit.
    private func priceForHabit(_ habit: Habit) -> Int {
        let completions = tradeStore.tradesInPeriod(habitId: habit.id, days: 7)
        return RewardCalculation.calculateReward(
            habit: habit,
            allHabits: habitStore.activeHabits,
            completionsInPeriod: completions,
            timeBucket: timeBucket,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
    }

    // Each habit row in the list.
    private func habitRow(_ habit: Habit) -> some View {
        let tags = tagStore.tagsForHabit(habitId: habit.id)
        let canTrade = habitCanTrade(habit)

        return HStack(alignment: .center) {
            // Left side: habit info, taps to open change form.
            Button {
                openChangeForm(habit, focus: nil)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !habit.description.isEmpty {
                        Text(habit.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Frequency & Difficulty as bordered capsule pills (display only).
                    if habit.frequency != nil || habit.difficultyRank != nil {
                        HStack(spacing: 8) {
                            if let freq = habit.frequency {
                                borderedPill(text: FrequencyConversion.formatSummary(freq) ?? "")
                            }

                            if habit.difficultyRank != nil {
                                borderedPill(text: "Difficulty")
                            }
                        }
                    }

                    if !tags.isEmpty {
                        TagPillsRow(tags: tags)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Right side: price button OR incomplete indicator.
            // If the habit has both frequency and difficulty set, show the
            // price button that opens the trade modal. Otherwise show a
            // small indicator that tapping opens the change form so the
            // user can set the missing properties.
            if canTrade {
                let price = priceForHabit(habit)
                Button {
                    tradingHabit = habit
                } label: {
                    HStack(spacing: 2) {
                        Text("\(price)")
                            .contentTransition(.numericText())
                        Image(systemName: "cube.fill")
                            .font(.caption2)
                    }
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.green, in: .capsule)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 2.0), value: price)
            } else {
                // Incomplete habit — show a hint that opens the change form.
                // The exclamation mark triangle signals "action needed" without
                // being alarming. Tapping opens the change form so the user
                // can set the missing frequency/difficulty.
                Button {
                    openChangeForm(habit, focus: habit.frequency == nil ? .frequency : .difficulty)
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func borderedPill(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(.orange, lineWidth: 1))
    }

    private func openChangeForm(_ habit: Habit, focus: HabitFormFocus?) {
        editFocus = focus
        editingHabit = habit
    }
}

#Preview {
    HabitsView()
        .environment(HabitStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
}
