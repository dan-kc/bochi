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
            // New habit sheet
            .sheet(isPresented: $showingNewForm) {
                HabitFormView(mode: .new)
            }
            // Change/edit habit sheet — triggered by tapping a row element.
            // .sheet(item:) automatically sets editingHabit back to nil on dismiss.
            .sheet(item: $editingHabit) { habit in
                HabitFormView(mode: .change(habit), initialFocus: editFocus)
            }
        }
    }

    // Each habit row in the list. Layout:
    //   Name (tappable → opens main change form)
    //   [Description]  (its own line, truncated)
    //   [Frequency pill] [Difficulty pill]  (bordered capsules)
    //   [Tag1] [Tag2]  (colored pills)
    //
    // Tapping name/description opens the change form (no sub-modal).
    // Tapping frequency/difficulty/tags opens the form focused on that field.
    private func habitRow(_ habit: Habit) -> some View {
        let tags = tagStore.tagsForHabit(habitId: habit.id)

        // The whole row is a Button so tapping anywhere (including whitespace)
        // opens the change form. In SwiftUI List, a row-level Button is the
        // only reliable way to make the entire row tappable — .onTapGesture
        // on a child VStack gets swallowed by the List's gesture handling.
        // This is like wrapping a <div> in an <a> or <button> in React.
        //
        // Inner elements (pills, tags) use nested Buttons to intercept taps
        // before they bubble up to this row-level Button. SwiftUI's gesture
        // system gives inner Buttons priority, similar to stopPropagation().
        return Button {
            openChangeForm(habit, focus: nil)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: Name — tapping opens the main change form (not name editor)
                Text(habit.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Row 2: Description on its own line, truncated to one line
                if !habit.description.isEmpty {
                    Text(habit.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Row 3: Frequency & Difficulty as bordered capsule pills.
                // No background fill — just a colored border outline.
                // Each pill is a Button so it gets the same subtle press
                // animation that tag pills have (default SwiftUI tap feedback).
                if habit.frequency != nil || habit.difficultyRank != nil {
                    HStack(spacing: 8) {
                        if let freq = habit.frequency {
                            borderedPill(
                                text: FrequencyConversion.formatSummary(freq) ?? "",
                                onTap: { openChangeForm(habit, focus: .frequency) }
                            )
                        }

                        if habit.difficultyRank != nil {
                            borderedPill(
                                text: "Difficulty",
                                onTap: { openChangeForm(habit, focus: .difficulty) }
                            )
                        }
                    }
                }

                // Row 4: Tag pills — colored with hex code backgrounds.
                // The whole row is tappable via onTapGesture (no per-tag buttons).
                if !tags.isEmpty {
                    TagPillsRow(tags: tags)
                        .onTapGesture {
                            openChangeForm(habit, focus: .tags)
                        }
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
    // The Button wrapper provides the same subtle press animation
    // that tag pills get — like a <Pressable> with opacity feedback in React Native.
    private func borderedPill(text: String, onTap: @escaping () -> Void) -> some View {
        Button {
            onTap()
        } label: {
            Text(text)
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                // Capsule().stroke draws only the border — no fill.
                // Like border + borderRadius: 999 with no backgroundColor in CSS.
                .overlay(Capsule().stroke(.orange, lineWidth: 1))
        }
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
