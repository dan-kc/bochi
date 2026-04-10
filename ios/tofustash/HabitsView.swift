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
    //   Name (tappable → name/desc modal)
    //   [Description] [Frequency] [Difficulty]  (orange if set)
    //   [Tag1] [Tag2]  (colored pills)
    //
    // Tapping any element opens the change form with the appropriate sub-modal.
    private func habitRow(_ habit: Habit) -> some View {
        let tags = tagStore.tagsForHabit(habitId: habit.id)

        // The whole row is a Button so tapping anywhere (including whitespace)
        // opens the change form. In SwiftUI List, a row-level Button is the
        // only reliable way to make the entire row tappable — .onTapGesture
        // on a child VStack gets swallowed by the List's gesture handling.
        // This is like wrapping a <div> in an <a> or <button> in React.
        //
        // Inner elements (description, frequency, difficulty, tags) use
        // .onTapGesture to intercept taps before they bubble up to this Button.
        // In React terms: e.stopPropagation() on the inner onClick handler.
        return Button {
            openChangeForm(habit, focus: nil)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: Name — tapping the name itself opens the name/desc editor.
                // The .onTapGesture intercepts before the outer Button fires,
                // like e.stopPropagation() in React.
                Text(habit.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .onTapGesture {
                        openChangeForm(habit, focus: .name)
                    }

                // Row 2: Description, Frequency, Difficulty — orange indicators
                let hasSecondRow = !habit.description.isEmpty || habit.frequency != nil || habit.difficultyRank != nil
                if hasSecondRow {
                    HStack(spacing: 8) {
                        if !habit.description.isEmpty {
                            // Description tap focuses the description field in the editor,
                            // not the name field — uses .description instead of .name.
                            Text(habit.description)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .onTapGesture {
                                    openChangeForm(habit, focus: .description)
                                }
                        }

                        if let freq = habit.frequency {
                            Text(FrequencyConversion.formatSummary(freq) ?? "")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .onTapGesture {
                                    openChangeForm(habit, focus: .frequency)
                                }
                        }

                        if habit.difficultyRank != nil {
                            Text("Difficulty")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .onTapGesture {
                                    openChangeForm(habit, focus: .difficulty)
                                }
                        }
                    }
                }

                // Row 3: Tag pills — colored with hex code backgrounds
                if !tags.isEmpty {
                    TagPillsRow(tags: tags) {
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
