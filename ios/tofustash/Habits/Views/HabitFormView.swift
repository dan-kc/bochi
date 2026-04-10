import SwiftUI

// HabitFormMode is like a tagged union / discriminated union in TypeScript:
//   type FormMode = { type: "new" } | { type: "change", habit: Habit }
//
// Swift enums can carry associated values — each case is like a variant
// that holds different data. `.new` carries nothing, `.change` carries
// the Habit being edited.
enum HabitFormMode: Equatable {
    case new
    case change(Habit)
}

// Which sub-modal should auto-open when the form appears.
// Used when tapping a specific field in the list view — e.g. tapping
// "Frequency" opens the change form AND immediately shows the frequency modal.
//
// nil = don't auto-open any sub-modal (default for change form).
// For new forms, .nameDescription is the default (focus on name).
enum HabitFormFocus: Equatable {
    case nameDescription
    case frequency
    case difficulty
    case tags
}

// The main habit form — handles both creating new habits and editing existing ones.
//
// DRY: a single view with a mode enum instead of two separate views.
// Like React's pattern of `<HabitForm mode="new" />` vs `<HabitForm mode="change" habit={habit} />`.
struct HabitFormView: View {
    let mode: HabitFormMode
    let initialFocus: HabitFormFocus?

    @Environment(\.dismiss) private var dismiss
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore

    // Form state — initialized from the habit in .onAppear for change mode.
    // In React, these would be multiple useState hooks.
    @State private var name = ""
    @State private var description = ""
    @State private var frequency: Double? = nil
    @State private var difficultyRank: String? = nil

    // The habit's ID — needed for tag associations in change mode.
    // For new mode, we generate one up front so tags can be associated
    // before the habit is actually saved.
    @State private var habitId: String = UUID().uuidString

    // Sub-modal presentation states — like multiple useState booleans in React.
    // When set to true, the corresponding .sheet modifier presents the modal.
    @State private var showingNameDescription = false
    @State private var showingFrequency = false
    @State private var showingDifficulty = false
    @State private var showingTags = false

    // Which field in the name/description modal should be focused
    @State private var nameDescFocus: NameDescriptionModal.Field = .name

    // Track whether the initial focus has been applied
    @State private var hasAppliedInitialFocus = false

    // Convenience: is this a new habit form?
    private var isNewMode: Bool {
        if case .new = mode { return true }
        return false
    }

    // Tags currently applied to this habit
    private var habitTags: [Tag] {
        tagStore.tagsForHabit(habitId: habitId)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 100
    }

    init(mode: HabitFormMode = .new, initialFocus: HabitFormFocus? = nil) {
        self.mode = mode
        self.initialFocus = initialFocus
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Name & Description — tappable buttons that open the modal
                Section {
                    // Name button — shows truncated name, taps to edit
                    Button {
                        nameDescFocus = .name
                        showingNameDescription = true
                    } label: {
                        if trimmedName.isEmpty {
                            Text("Name")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(name)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                    }

                    // Description button — shows truncated description, taps to edit
                    Button {
                        nameDescFocus = .description
                        showingNameDescription = true
                    } label: {
                        if description.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Description")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(description)
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                // Section 2: Pill row — Tags, Difficulty, Frequency
                Section {
                    PillRow(pills: buildPills())
                }

                // Section 3: Tag pills — shown only when tags are applied
                if !habitTags.isEmpty {
                    Section {
                        TagPillsRow(tags: habitTags) {
                            showingTags = true
                        }
                    }
                }
            }
            .navigationTitle(isNewMode ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isNewMode ? "Add" : "Save") {
                        saveHabit()
                    }
                    .disabled(!isValid)
                }
            }
            // Name/Description modal — .sheet is SwiftUI's modal presentation.
            // The animation is automatic — SwiftUI handles the slide-up transition.
            .sheet(isPresented: $showingNameDescription) {
                NameDescriptionModal(
                    name: $name,
                    description: $description,
                    initialFocus: nameDescFocus
                )
            }
            .sheet(isPresented: $showingFrequency) {
                FrequencyModal(frequency: $frequency)
            }
            .sheet(isPresented: $showingDifficulty) {
                DifficultyRankerView(
                    habitName: trimmedName.isEmpty ? "New Habit" : trimmedName,
                    difficultyRank: $difficultyRank,
                    excludeHabitId: isNewMode ? nil : habitId
                )
            }
            .sheet(isPresented: $showingTags) {
                TagsView(habitId: habitId)
            }
            .onAppear {
                initializeForm()
            }
        }
    }

    // Build the pill items for the pill row
    private func buildPills() -> [PillItem] {
        var pills: [PillItem] = []

        // Tags pill — only show if no tags are currently applied.
        // When tags exist, they appear in the TagPillsRow below instead.
        if habitTags.isEmpty {
            pills.append(PillItem(
                id: "tags",
                label: "Tags",
                icon: "tag",
                isSet: false,
                action: { showingTags = true }
            ))
        }

        // Difficulty pill — turns orange when set
        pills.append(PillItem(
            id: "difficulty",
            label: "Difficulty",
            icon: "chart.bar",
            isSet: difficultyRank != nil,
            action: { showingDifficulty = true }
        ))

        // Frequency pill — shows summary when set
        let freqLabel = FrequencyConversion.formatSummary(frequency) ?? "Frequency"
        pills.append(PillItem(
            id: "frequency",
            label: freqLabel,
            icon: "clock",
            isSet: frequency != nil,
            action: { showingFrequency = true }
        ))

        return pills
    }

    // Initialize form state from the habit (change mode) or defaults (new mode)
    private func initializeForm() {
        guard !hasAppliedInitialFocus else { return }
        hasAppliedInitialFocus = true

        if case .change(let habit) = mode {
            // Populate form from existing habit
            name = habit.name
            description = habit.description
            frequency = habit.frequency
            difficultyRank = habit.difficultyRank
            habitId = habit.id
        }

        // Apply initial focus — open the appropriate sub-modal
        let focus = initialFocus ?? (isNewMode ? .nameDescription : nil)

        // Dispatch async to let the view finish layout before presenting sheets.
        // Like using setTimeout(fn, 0) in React to defer modal opening.
        if let focus = focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                switch focus {
                case .nameDescription:
                    nameDescFocus = .name
                    showingNameDescription = true
                case .frequency:
                    showingFrequency = true
                case .difficulty:
                    showingDifficulty = true
                case .tags:
                    showingTags = true
                }
            }
        }
    }

    private func saveHabit() {
        if case .new = mode {
            habitStore.addHabit(
                name: name,
                description: description,
                frequency: frequency,
                difficultyRank: difficultyRank
            )
        } else {
            habitStore.updateHabit(
                id: habitId,
                name: name,
                description: description,
                frequency: .some(frequency),
                difficultyRank: .some(difficultyRank)
            )
        }

        dismiss()
    }
}

#Preview("New") {
    HabitFormView(mode: .new)
        .environment(HabitStore())
        .environment(TagStore())
}
