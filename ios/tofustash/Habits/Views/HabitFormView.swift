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

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
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

    // Which field in the name/description editor has keyboard focus.
    // @FocusState is SwiftUI's way to programmatically control keyboard focus.
    // Like using useRef + ref.current.focus() in React, but declarative —
    // set the state variable and SwiftUI moves focus automatically.
    enum NameDescField: Hashable {
        case name, description
    }

    @FocusState private var focusedField: NameDescField?

    // Tracks which field should receive focus when the name/description editor
    // next appears. We can't rely on @FocusState alone because SwiftUI resets
    // it to nil when the target TextField isn't in the view hierarchy yet
    // (during the ZStack cross-fade). This @State survives the transition and
    // is read by .onAppear to set the correct focus.
    // In React terms: @FocusState is like an uncontrolled ref that the browser
    // can reset; pendingFocus is the controlled state that tells us what to do.
    @State private var pendingFocus: NameDescField = .name

    // Track whether the initial focus has been applied
    @State private var hasAppliedInitialFocus = false

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
        Self.hasContent(
            name: trimmedName,
            description: description,
            frequency: frequency,
            difficultyRank: difficultyRank,
            tagCount: habitTags.count
        )
    }

    static func hasContent(
        name: String,
        description: String,
        frequency: Double?,
        difficultyRank: String?,
        tagCount: Int
    ) -> Bool {
        !name.isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || frequency != nil
            || difficultyRank != nil
            || tagCount > 0
    }

    // Prepares the name for auto-save by trimming whitespace.
    // The trimmed value is passed to updateHabit, which handles validation:
    // if the name is empty or too long, updateHabit keeps the existing name.
    // This lets other fields (frequency, description, etc.) still save
    // even while the user is mid-edit on the name field.
    static func nameForAutoSave(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
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
        self._pendingFocus = State(initialValue: initialFocus == .description ? .description : .name)
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
                : (mode.isNew ? "New Habit" : "Edit Habit"))
            .navigationBarTitleDisplayMode(.inline)
            // Fixed .medium detent (~half screen). Content scrolls within this
            // height. The sheet never resizes — simpler and more predictable.
            .presentationDetents([.medium])
            // Hide the drag indicator bar — the sheet height is fixed,
            // not user-draggable. The user can still swipe down to dismiss.
            .presentationDragIndicator(.hidden)
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
                } else if mode.isNew {
                    // Cancel and Add buttons only appear on the new form.
                    // The change form auto-saves when dismissed (no buttons needed).
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            persistHabit()
                            dismiss()
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
                    excludeHabitId: mode.isNew ? nil : habitId
                )
            }
            .sheet(isPresented: $showingTags) {
                TagsView(habitId: habitId)
            }
            .task {
                await initializeForm()
            }
            // Auto-save: in change mode, persist to the store whenever any field
            // changes. This makes the HabitListItem update immediately — like
            // calling onChange on every controlled input in React and dispatching
            // to the store on each keystroke.
            //
            // .onChange(of:) fires whenever the watched value changes — similar to
            // useEffect(() => { ... }, [dep]) in React, but synchronous.
            // The `guard hasAppliedInitialFocus` check prevents saving during
            // initial form population (when .task sets fields from the habit).
            .onChange(of: name) { _, _ in autoSave() }
            .onChange(of: description) { _, _ in autoSave() }
            .onChange(of: frequency) { _, _ in autoSave() }
            .onChange(of: difficultyRank) { _, _ in autoSave() }
            // Block drag-to-dismiss when the new form has content, so the user
            // doesn't accidentally lose their work. They can still tap Cancel
            // to dismiss intentionally. Like preventing accidental navigation
            // away from a dirty form in React (but without a confirmation dialog).
            .interactiveDismissDisabled(mode.isNew && hasContent)
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
                    pendingFocus = .name
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
                    pendingFocus = .description
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

            // Section 3: Tag pills — shown only when tags are applied.
            // The entire section is a tap target to open the tags modal.
            // In React, this is like wrapping a <div> with onClick instead of
            // putting onClick on each child. contentShape(Rectangle()) makes the
            // whitespace tappable too — without it, only the text/pills respond.
            if !habitTags.isEmpty {
                Section {
                    TagPillsRow(tags: habitTags)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showingTags = true
                }
            }
        }
    }

    // Scrollable editor for name and description.
    // Instead of presenting a separate sheet, this view morphs in-place
    // within the same sheet via the ZStack cross-fade.
    // The ScrollView handles long content (names/descriptions can be very long).
    // Because this view is created fresh each time showingNameDescription becomes
    // true, it always starts scrolled to the top.
    private var nameDescriptionEditor: some View {
        // ScrollViewReader lets us programmatically scroll to a specific child
        // view by ID — like calling element.scrollIntoView() in the DOM.
        // Used only for initial positioning when the editor opens with
        // description focused — ongoing cursor tracking is handled by
        // SwiftUI's built-in keyboard avoidance.
        ScrollViewReader { proxy in
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
                    // The .id lets ScrollViewReader target this field for initial scroll.
                    TextField("Description", text: $description, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(5...)
                        .id("description")
                }
                .padding()
            }
            .onAppear {
                // Apply the pending focus when the editor appears.
                // We read from pendingFocus (a @State that survives the ZStack
                // cross-fade) rather than focusedField (@FocusState which SwiftUI
                // resets to nil when the target TextField isn't in the hierarchy).
                // Like calling ref.current.focus() in useEffect based on a state
                // variable, not the DOM's current activeElement.
                focusedField = pendingFocus

                // If focusing description, scroll to show the bottom of the
                // description field (where the cursor is placed by default).
                // DispatchQueue.main.async defers to the next run loop tick so
                // SwiftUI finishes layout first — like setTimeout(fn, 0) in React.
                if pendingFocus == .description {
                    DispatchQueue.main.async {
                        proxy.scrollTo("description", anchor: .bottom)
                    }
                }
            }
            // No .onChange scroll handler — SwiftUI's built-in keyboard avoidance
            // tracks the cursor position within the focused TextField and scrolls
            // the parent ScrollView automatically. Manually scrolling to a fixed
            // anchor would override this, jumping to the bottom even when the
            // cursor is in the middle of the text.
        }
    }

    // Pure data for the pill row — actions are nil so it can be unit tested.
    // In React terms, this is like a selector that derives render data from state,
    // separated from the event handlers.
    static func buildPillData(
        hasTagsApplied: Bool,
        difficultyRank: String?,
        frequency: Double?
    ) -> [PillItem] {
        let freqLabel = FrequencyConversion.formatSummary(frequency) ?? "Frequency"
        return [
            PillItem(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            PillItem(id: "difficulty", label: "Difficulty", icon: "chart.bar", isSet: difficultyRank != nil),
            PillItem(id: "frequency", label: freqLabel, icon: "clock", isSet: frequency != nil),
        ]
    }

    // Build the pill items for the pill row, attaching action closures.
    // Like adding onClick handlers to stateless component props in React.
    private func buildPills() -> [PillItem] {
        var pills = Self.buildPillData(
            hasTagsApplied: !habitTags.isEmpty,
            difficultyRank: difficultyRank,
            frequency: frequency
        )

        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "difficulty": { showingDifficulty = true },
            "frequency": { showingFrequency = true },
        ]

        for i in pills.indices {
            pills[i].action = actions[pills[i].id]
        }
        return pills
    }

    // Initialize form state from the habit (change mode) or defaults (new mode).
    // Called from .task, which only runs once per view lifecycle (like useEffect
    // with [] deps). Sets hasAppliedInitialFocus at the end so auto-save
    // .onChange handlers skip firing during initial population.
    private func initializeForm() async {
        if case .change(let habit) = mode {
            // Populate form from existing habit
            name = habit.name
            description = habit.description
            frequency = habit.frequency
            difficultyRank = habit.difficultyRank
            habitId = habit.id
        }

        // Mark initialization complete so auto-save .onChange handlers start firing.
        hasAppliedInitialFocus = true

        // Apply initial focus — open the appropriate sub-modal.
        // .name/.description are handled in init() (no async delay needed, avoids flash).
        // Other focus targets still need a short delay for sheet presentation.
        let focus = initialFocus ?? (mode.isNew ? .name : nil)

        // Delay to let the view finish layout before presenting sheets.
        if let focus = focus, !focus.isNameDescription {
            try? await Task.sleep(nanoseconds: 300_000_000)
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

    // Auto-save for change mode: called by .onChange handlers whenever any
    // form field changes. Skips save during initial form population (before
    // hasAppliedInitialFocus is set) and in new mode (which uses explicit "Add").
    //
    // Like having a useEffect that runs on every state change and dispatches
    // to the store — except SwiftUI's .onChange is more targeted (one per field).
    private func autoSave() {
        guard !mode.isNew, hasAppliedInitialFocus else { return }
        persistHabit()
    }

    // Writes the current form state to the store (add or update).
    // For change mode, always passes the name — updateHabit handles validation
    // and keeps the existing name if the new one is invalid (empty/too long).
    // This lets other fields save even while the name is mid-edit.
    private func persistHabit() {
        if case .new = mode {
            // Pass the pre-generated habitId so the saved habit matches any tag
            // associations created during the form session. Without this, addHabit
            // would generate a new UUID and the tags would point to nowhere.
            habitStore.addHabit(
                id: habitId,
                name: name,
                description: description,
                frequency: frequency,
                difficultyRank: difficultyRank
            )
        } else {
            habitStore.updateHabit(
                id: habitId,
                name: Self.nameForAutoSave(name),
                description: description,
                frequency: .some(frequency),
                difficultyRank: .some(difficultyRank)
            )
        }
    }

}

#Preview("New") {
    HabitFormView(mode: .new)
        .environment(HabitStore())
        .environment(TagStore())
}
