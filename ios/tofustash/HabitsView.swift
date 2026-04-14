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

    // State for the delete confirmation alert — which habit the user is
    // about to delete. Set by swipe action; the alert reads this to know
    // which habit to delete on confirmation. Like a useState<Habit | null>
    // that gates a <ConfirmDialog> in React.
    @State private var habitToDelete: Habit? = nil

    // Toast manager for showing recovery toasts when habits are discarded.
    // Like a useState + context provider for a toast notification system in React.
    @State private var toastManager = ToastManager()

    // Holds saved form state for recovery. When the user taps "Recover" on
    // a toast, this is set to re-open the form with the discarded values.
    // Like a useState<FormSnapshot | null>(null) in React.
    @State private var recoveringPrefill: HabitFormSnapshot? = nil

    // Current time bucket for price calculations. Sleeps until the next
    // 30-minute boundary, then updates — so prices refresh exactly when
    // the bucket rolls over.
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
                            // Trailing swipe = swipe left. This is Apple's standard
                            // delete gesture (like Mail, Notes, Reminders). The
                            // .trailing edge is idiomatic for destructive actions.
                            // In React terms, this is like attaching an onSwipeLeft
                            // handler that renders a red "Delete" button.
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    habitToDelete = habit
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Habits")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    // Clear any lingering recovery state so the FAB always
                    // opens a fresh form, not a recovered one.
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
            // New habit sheet — passes an onDiscard callback so we can show a
            // recovery toast when the user dismisses a form that had content.
            // The prefill parameter restores form state when recovering.
            .sheet(isPresented: $showingNewForm) {
                HabitFormView(
                    mode: .new,
                    prefill: recoveringPrefill,
                    onDiscard: { snapshot in
                        showDiscardToast(snapshot: snapshot)
                    }
                )
            }
            // Change/edit habit sheet — triggered by tapping a row element.
            // .sheet(item:) automatically sets editingHabit back to nil on dismiss.
            .sheet(item: $editingHabit) { habit in
                HabitFormView(
                    mode: .change(habit),
                    initialFocus: editFocus,
                    onDelete: { habitToDelete in
                        // The form requests deletion — set the state so the
                        // confirmation alert appears after the sheet dismisses.
                        // editingHabit is cleared by .sheet(item:) on dismiss,
                        // then the alert takes over.
                        self.habitToDelete = habitToDelete
                    }
                )
            }
            .sheet(item: $tradingHabit) { habit in
                TradeModalView(habit: habit)
            }
            // Delete confirmation alert — triggered by swipe action or the
            // delete button in the edit form. Uses .alert(item:) which
            // automatically sets habitToDelete back to nil on dismiss.
            // Like a <ConfirmDialog open={!!habitToDelete}> in React.
            //
            // `role: .destructive` makes the "Delete" button red — the
            // system standard for irreversible actions.
            .alert(
                "Delete Habit?",
                isPresented: Binding(
                    get: { habitToDelete != nil },
                    set: { if !$0 { habitToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let habit = habitToDelete {
                        habitStore.deleteHabit(id: habit.id)
                    }
                    habitToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    habitToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
            // Toast overlay sits on top of everything, at the bottom of the screen.
            // Like a portal-rendered <ToastContainer /> in React.
            .overlay {
                ToastOverlay(toastManager: toastManager)
            }
            // Sleep until the next 30-minute bucket boundary, then update.
            // More efficient than polling every 60s — wakes exactly once per
            // bucket change instead of ~29 unnecessary checks.
            .task {
                while !Task.isCancelled {
                    let nanos = RewardCalculation.nanosUntilNextBucket()
                    try? await Task.sleep(nanoseconds: nanos)
                    timeBucket = RewardCalculation.getCurrentTimeBucket()
                }
            }
        }
    }

    // Show a toast that lets the user recover a discarded habit form.
    // The toast has a 5-second countdown, after which it auto-dismisses.
    private func showDiscardToast(snapshot: HabitFormSnapshot) {
        // Clear any previous prefill so it doesn't leak into new forms.
        recoveringPrefill = nil
        toastManager.show(
            message: "Habit Discarded",
            actionLabel: "Recover"
        ) {
            // When the user taps "Recover", save the snapshot and re-open
            // the form. The form reads recoveringPrefill to restore state.
            recoveringPrefill = snapshot
            showingNewForm = true
        }
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

    // Each habit row in the list. Layout:
    //   [Habit info (left)]     [Price button OR warning icon (right)]
    //
    // Split into two buttons in an HStack: the left side opens the change form,
    // the right side opens the trade modal (or change form if incomplete).
    // This replaces the old single-button approach since the row now has two
    // distinct tap targets.
    private func habitRow(_ habit: Habit) -> some View {
        let tags = tagStore.tagsForHabit(habitId: habit.id)
        let canTrade = habit.canTrade

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
                // .frame(maxWidth:) stretches the VStack to fill the available width.
                // .contentShape ensures taps register on the gaps between text rows.
                // Together they make the entire left side a single tap target.
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

    // A pill with a colored border outline and no background fill.
    // Used for frequency and difficulty indicators in the list row.
    // Like border + borderRadius: 999 with no backgroundColor in CSS.
    private func borderedPill(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(.orange, lineWidth: 1))
    }

    // Opens the change form for a habit, optionally auto-opening a sub-modal.
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
