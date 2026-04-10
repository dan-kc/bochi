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

        return VStack(alignment: .leading, spacing: 6) {
            // Row 1: Name — tapping opens change form with name/description modal
            Button {
                openChangeForm(habit, focus: .nameDescription)
            } label: {
                Text(habit.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            // Row 2: Description, Frequency, Difficulty — orange indicators
            // FlowLayout-like: uses HStack that wraps content
            let hasSecondRow = !habit.description.isEmpty || habit.frequency != nil || habit.difficultyRank != nil
            if hasSecondRow {
                HStack(spacing: 8) {
                    if !habit.description.isEmpty {
                        Button {
                            openChangeForm(habit, focus: .nameDescription)
                        } label: {
                            Text(habit.description)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }

                    if let freq = habit.frequency {
                        Button {
                            openChangeForm(habit, focus: .frequency)
                        } label: {
                            Text(FrequencyConversion.formatSummary(freq) ?? "")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }

                    if habit.difficultyRank != nil {
                        Button {
                            openChangeForm(habit, focus: .difficulty)
                        } label: {
                            Text("Difficulty")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
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
