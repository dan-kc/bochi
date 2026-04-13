import SwiftUI

struct HabitsView: View {
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore

    // State for the new habit form (FAB)
    @State private var showingNewForm = false

    // State for the change form — which habit is being edited and which
    // sub-modal to auto-open. Using an Identifiable binding with .sheet(item:)
    // is the idiomatic SwiftUI pattern for "present a sheet for a specific item."
    @State private var editingHabit: Habit? = nil
    @State private var editFocus: HabitFormFocus? = nil

    // Toast manager for showing recovery toasts when habits are discarded.
    // Like a useState + context provider for a toast notification system in React.
    @State private var toastManager = ToastManager()

    // Holds saved form state for recovery. When the user taps "Recover" on
    // a toast, this is set to re-open the form with the discarded values.
    // Like a useState<FormSnapshot | null>(null) in React.
    @State private var recoveringPrefill: HabitFormSnapshot? = nil

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
                HabitFormView(mode: .change(habit), initialFocus: editFocus)
            }
            // Toast overlay sits on top of everything, at the bottom of the screen.
            // Like a portal-rendered <ToastContainer /> in React.
            .overlay {
                ToastOverlay(toastManager: toastManager)
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

    // Each habit row in the list. Layout:
    //   Name
    //   [Description]  (its own line, truncated)
    //   [Frequency pill] [Difficulty pill]  (bordered capsules)
    //   [Tag1] [Tag2]  (colored pills)
    //
    // The entire row is a single Button — tapping anywhere opens the change form.
    // There are no nested buttons or tap handlers on individual elements.
    private func habitRow(_ habit: Habit) -> some View {
        let tags = tagStore.tagsForHabit(habitId: habit.id)

        // The whole row is a Button so tapping anywhere (including whitespace)
        // opens the change form. In SwiftUI List, a row-level Button is the
        // only reliable way to make the entire row tappable — .onTapGesture
        // on a child VStack gets swallowed by the List's gesture handling.
        // This is like wrapping a <div> in an <a> or <button> in React.
        return Button {
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

                // Tag pills — colored with hex code backgrounds (display only).
                if !tags.isEmpty {
                    TagPillsRow(tags: tags)
                }
            }
            // .frame(maxWidth:) stretches the VStack to fill the full row width.
            // Without this, the button's tap target only covers the text content,
            // leaving the whitespace to the right of short text untappable.
            // .contentShape ensures taps register on the gaps between text rows too.
            // Together they make the entire List row a single tap target.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // A pill with a colored border outline and no background fill.
    // Used for frequency and difficulty indicators in the list row.
    // Display-only — not individually tappable; the row button handles all taps.
    private func borderedPill(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // Capsule().stroke draws only the border — no fill.
            // Like border + borderRadius: 999 with no backgroundColor in CSS.
            .overlay(Capsule().stroke(.orange, lineWidth: 1))
    }

    // Opens the change form for a habit, optionally auto-opening a sub-modal
    private func openChangeForm(_ habit: Habit, focus: HabitFormFocus?) {
        editFocus = focus
        editingHabit = habit
    }
}

#Preview {
    HabitsView()
        .environment(HabitStore())
        .environment(TagStore())
}
