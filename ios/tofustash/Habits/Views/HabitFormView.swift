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
// For new forms, .name is the default (focus on name).
//
// .name and .description both open the same name/description editor —
// the difference is which text field gets keyboard focus. Like having
// two React onClick handlers that open the same modal but call
// different ref.current.focus() targets.
enum HabitFormFocus: Equatable {
    case name
    case description
    case frequency
    case difficulty
    case tags

    // Whether this focus opens the name/description editor.
    // Both .name and .description open the same inline editor view,
    // just focusing different fields — so they share this check.
    var isNameDescription: Bool {
        self == .name || self == .description
    }
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
    // showingNameDescription is NOT initialized here — it's set in init() based
    // on mode, so new forms start directly on the name/description editor (no flash).
    @State private var showingNameDescription: Bool
    @State private var showingFrequency = false
    @State private var showingDifficulty = false
    @State private var showingTags = false

    // Which field in the name/description editor should be focused.
    // Like a ref target in React — determines which input to auto-focus.
    enum NameDescField: Hashable {
        case name, description
    }

    @State private var nameDescFocus: NameDescField = .name

    // @FocusState is SwiftUI's way to programmatically control keyboard focus.
    // Like using useRef + ref.current.focus() in React, but declarative —
    // set the state variable and SwiftUI moves focus automatically.
    @FocusState private var focusedField: NameDescField?

    // Track whether the initial focus has been applied
    @State private var hasAppliedInitialFocus = false

    // Controls which sheet height (detent) is currently active.
    // Without this binding, SwiftUI may auto-select .large when the detent
    // set changes (e.g. switching to name/description editor). The binding
    // pins it to .medium so it only goes large if the user drags up.
    // Like a controlled component in React — we own the state, not the framework.
    @State private var selectedDetent: PresentationDetent = .medium

    // Controls the discard confirmation dialog shown when the user tries to
    // interactively dismiss (drag-down or tap-outside) a new form with content.
    @State private var showDiscardConfirmation = false

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

    // Whether the user has entered any content into the form.
    // Used to decide if we need a discard confirmation on new forms.
    private var hasContent: Bool {
        !trimmedName.isEmpty
            || !description.trimmingCharacters(in: .whitespaces).isEmpty
            || frequency != nil
            || difficultyRank != nil
            || !habitTags.isEmpty
    }

    init(mode: HabitFormMode = .new, initialFocus: HabitFormFocus? = nil) {
        self.mode = mode
        self.initialFocus = initialFocus

        // For new forms, start directly on the name/description editor so the user
        // never sees a flash of the empty main form. For change forms, start on the
        // main form unless initialFocus says otherwise.
        // In Swift, @State must be initialized via _propertyName = State(initialValue:)
        // inside init — like setting useState's initial value in React.
        let startOnNameDesc: Bool
        if case .new = mode {
            startOnNameDesc = initialFocus == nil || initialFocus?.isNameDescription == true
        } else {
            startOnNameDesc = initialFocus?.isNameDescription == true
        }
        self._showingNameDescription = State(initialValue: startOnNameDesc)

        // If opening for description, focus description field; otherwise default to name.
        if initialFocus == .description {
            self._nameDescFocus = State(initialValue: .description)
        }
    }

    var body: some View {
        NavigationStack {
            // ZStack layers the form and name/description editor on top of each
            // other. Only one is visible at a time — they cross-fade via .opacity
            // transitions. This is the "morph" effect: the sheet content transforms
            // in-place rather than presenting a new sheet on top.
            // In React, this is like conditionally rendering two components with
            // CSS transitions (opacity + transform) on a shared container.
            ZStack {
                if !showingNameDescription {
                    mainFormContent
                        .transition(.opacity)
                }

                if showingNameDescription {
                    nameDescriptionEditor
                        .transition(.opacity)
                }
            }
            // .animation makes SwiftUI interpolate between the two states —
            // fading one out and the other in. Like CSS `transition: opacity 0.25s`.
            .animation(.easeInOut(duration: 0.25), value: showingNameDescription)
            .navigationTitle(showingNameDescription
                ? "Name & Description"
                : (isNewMode ? "New Habit" : "Edit Habit"))
            .navigationBarTitleDisplayMode(.inline)
            // Dynamic detents: name/description editor offers both .medium and .large
            // so it starts at half-screen but the user can drag up for more space
            // when content is long. The form always uses .medium.
            .presentationDetents(
                showingNameDescription ? [.medium, .large] : [.medium],
                selection: $selectedDetent
            )
            // Reset to .medium when leaving the name/description editor,
            // so the main form doesn't stay at .large if the user dragged up.
            .onChange(of: showingNameDescription) { _, newValue in
                if !newValue {
                    selectedDetent = .medium
                }
            }
            // Shows a small horizontal bar at the top of the sheet — a visual
            // hint that the user can drag down to dismiss. Like a drawer handle.
            .presentationDragIndicator(.visible)
            .toolbar {
                if showingNameDescription {
                    // Done button (checkmark) to return from name/description to the form.
                    // Placed on the right (confirmationAction) — like a "Done" button in iOS conventions.
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            // Clear keyboard focus before closing, otherwise the
                            // keyboard may briefly flash during the transition.
                            focusedField = nil
                            showingNameDescription = false
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                } else if isNewMode {
                    // Cancel and Add buttons only appear on the new form.
                    // The change form auto-saves when dismissed (no buttons needed).
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            saveHabit()
                        }
                        .disabled(!isValid)
                    }
                }
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
            .onDisappear {
                // Auto-save for change mode: persist the current form state when
                // the sheet dismisses. Like an onUnmount cleanup in React's useEffect.
                // New mode only saves via the explicit "Add" button.
                if !isNewMode && isValid {
                    persistHabit()
                }
            }
            // DismissGuard intercepts drag-down and tap-outside dismiss attempts
            // on new forms that have content, showing a discard confirmation instead.
            // Only included in the view tree for new mode — for change mode, we don't
            // want it at all because it overrides SwiftUI's presentation controller
            // delegate, which would break normal tap-outside-to-dismiss behavior.
            .background {
                if isNewMode {
                    DismissGuard(isEnabled: hasContent) {
                        showDiscardConfirmation = true
                    }
                }
            }
            // The discard confirmation — a small action sheet that slides up from the bottom.
            // Like window.confirm() in the browser, but styled natively.
            .confirmationDialog(
                "Discard this habit?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                // "Cancel" (keep editing) is added automatically by SwiftUI
                // when using .confirmationDialog — no need to add it explicitly.
            }
        }
    }

    // MARK: - Sub-views

    // The main form showing name/description buttons, pills, and tags.
    // Extracted from body so the ZStack can swap between this and the editor.
    // In React terms, this is like a component rendered inside a conditional:
    //   {!showingNameDesc && <MainForm />}
    //
    // Because this view is removed/re-added via the `if` conditional in the ZStack,
    // SwiftUI destroys and recreates it on each transition. This means the Form's
    // scroll position resets to the top automatically — no manual scrollTo needed.
    private var mainFormContent: some View {
        Form {
            // Section 1: Name & Description — tappable buttons that open the editor
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
    }

    // Fullscreen-ish scrollable editor for name and description.
    // Replaces the old NameDescriptionModal sheet — instead of presenting a new
    // sheet on top, this view morphs in-place within the same sheet.
    //
    // Like the old modal, but rendered inline with a cross-fade transition.
    // The ScrollView handles long content (names/descriptions can be very long).
    // Because this view is created fresh each time showingNameDescription becomes
    // true, it always starts scrolled to the top.
    private var nameDescriptionEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Name", text: $name)
                    .font(.title2)
                    // .focused binds this field's keyboard focus to the focusedField
                    // state. When focusedField == .name, this field gets focus.
                    // Like managing focus via a ref in React, but declarative.
                    .focused($focusedField, equals: .name)

                // axis: .vertical makes this a multiline text field (like <textarea>).
                // .lineLimit(5...) means at least 5 lines tall, grows as needed.
                TextField("Description", text: $description, axis: .vertical)
                    .focused($focusedField, equals: .description)
                    .lineLimit(5...)
            }
            .padding()
        }
        .onAppear {
            // Small delay ensures the view is fully laid out before focusing.
            // Without this, focus sometimes doesn't take effect — similar to
            // needing setTimeout(fn, 0) before calling ref.current.focus() in React.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = nameDescFocus
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

        // Apply initial focus — open the appropriate sub-modal.
        // .name/.description are handled in init() (no async delay needed, avoids flash).
        // Other focus targets still need a short delay for sheet presentation.
        let focus = initialFocus ?? (isNewMode ? .name : nil)

        // Dispatch async to let the view finish layout before presenting sheets.
        // Like using setTimeout(fn, 0) in React to defer modal opening.
        if let focus = focus, !focus.isNameDescription {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                switch focus {
                case .name, .description:
                    break // handled in init()
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

    // Writes the current form state to the store (add or update).
    // Separated from saveHabit() so it can also be called from onDisappear
    // for auto-save in change mode, without triggering dismiss().
    private func persistHabit() {
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
    }

    // Called by the "Add" button (new mode only). Saves and closes the form.
    private func saveHabit() {
        persistHabit()
        dismiss()
    }
}

#Preview("New") {
    HabitFormView(mode: .new)
        .environment(HabitStore())
        .environment(TagStore())
}
