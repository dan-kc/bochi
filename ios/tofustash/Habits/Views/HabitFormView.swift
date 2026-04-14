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

// Captures the form state when a new habit is discarded so it can be
// recovered later. Like serializing a React form's state to restore it.
// The habitId is preserved so any tag associations created during the
// form session remain valid on recovery.
struct HabitFormSnapshot {
    let name: String
    let description: String
    let frequency: Double?
    let difficultyRank: String?
    let habitId: String
}

// The main habit form — handles both creating new habits and editing existing ones.
struct HabitFormView: View {
    let mode: HabitFormMode
    let initialFocus: HabitFormFocus?
    // Called when a new form with content is dismissed without saving.
    // The snapshot contains all form values so the caller can offer recovery.
    // Like an onDiscard callback prop in React.
    let onDiscard: ((HabitFormSnapshot) -> Void)?
    // Pre-populates form fields when recovering a discarded habit.
    // When set, the form opens to the main view (not the name editor)
    // and does not auto-focus any field.
    let prefill: HabitFormSnapshot?

    @Environment(\.dismiss) private var dismiss
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

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

    // Trade modal presentation state — only used in .change mode.
    // When the trade completes, shouldDismissAfterTrade is set so the
    // form also dismisses (returning to the habit list).
    @State private var showingTradeModal = false
    @State private var shouldDismissAfterTrade = false

    // Alert shown when the user taps the difficulty pill for the first habit.
    // Since difficulty is auto-set, the ranker isn't needed — this explains why.
    // Like a window.alert() in React, but declarative: set the bool and SwiftUI
    // renders the alert. Dismissed by the system when the user taps "OK".
    @State private var showingFirstHabitAlert = false

    // Triggers a bounce animation on the difficulty pill after the ranker
    // sheet dismisses with a rank set. Like a CSS animation class toggled
    // via state in React: className={animating ? "bounce" : ""}
    @State private var difficultyPillAnimating = false

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

    // Whether this is the very first habit being created. Computed from store state.
    // Like a derived selector in React: useMemo(() => isFirstHabit(mode, habits), [mode, habits])
    private var isFirstHabit: Bool {
        Self.isFirstHabit(mode: mode, activeHabitsCount: habitStore.activeHabits.count)
    }

    // Whether there are other ranked habits to compare against. When false,
    // tapping the difficulty pill shows an alert instead of opening the ranker.
    private var hasComparableHabits: Bool {
        let rankedCount = habitStore.activeHabits
            .filter { $0.difficultyRank != nil && $0.id != habitId }
            .count
        return Self.hasComparableHabits(rankedHabitCount: rankedCount, excludeHabitId: mode.isNew ? nil : habitId)
    }

    // Current reward price for this habit — used by the trade button.
    // Recalculates automatically when trade history or settings change.
    // Uses the actual habit from the store (via the mode's associated value)
    // rather than creating a throwaway Habit, so properties like createdAt
    // are correct for the formula.
    private var currentPrice: Int {
        guard case .change(let habit) = mode else { return 0 }
        let completions = tradeStore.tradesInPeriod(habitId: habit.id, days: 7)
        return RewardCalculation.calculateReward(
            habit: habit,
            allHabits: habitStore.activeHabits,
            completionsInPeriod: completions,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
    }

    // Whether the current form state has the required properties to trade.
    // Uses the local form state (not the persisted habit) since the user may
    // have just set frequency/difficulty without saving yet.
    private var canTrade: Bool {
        frequency != nil && difficultyRank != nil
    }

    // Human-readable text describing which properties are missing.
    // Delegates to RewardCalculation to keep the logic in one place.
    private var missingPropertiesText: String {
        RewardCalculation.missingTradeProperties(frequency: frequency, difficultyRank: difficultyRank) ?? ""
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 100
    }

    // Whether the user has entered any content into the form.
    // Used to decide if we should show a recovery toast on dismiss.
    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: description,
            frequency: frequency,
            difficultyRank: difficultyRank,
            tagCount: habitTags.count,
            isFirstHabit: isFirstHabit
        )
    }

    static func hasContent(
        name: String,
        description: String,
        frequency: Double?,
        difficultyRank: String?,
        tagCount: Int,
        isFirstHabit: Bool = false
    ) -> Bool {
        // For the first habit, difficulty is auto-set (not user-entered), so
        // ignore it when deciding if the form has content. This prevents the
        // discard/recovery toast from appearing when the user opens a new form
        // and immediately dismisses it without entering anything.
        let hasDifficulty = isFirstHabit ? false : difficultyRank != nil
        return !name.isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || frequency != nil
            || hasDifficulty
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

    // Tracks whether the habit was saved via "Add". When the form disappears
    // without this being true (and it has content), we treat it as a discard
    // and call onDiscard so the parent can show a recovery toast.
    @State private var didPersist = false

    init(
        mode: HabitFormMode = .new,
        initialFocus: HabitFormFocus? = nil,
        prefill: HabitFormSnapshot? = nil,
        onDiscard: ((HabitFormSnapshot) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onDiscard = onDiscard

        // When recovering from a discard (prefill is set), skip the name/description
        // editor and show the main form instead — don't auto-focus anything.
        // For normal new forms, start directly on the name/description editor so the
        // user never sees a flash of the empty main form. For change forms, start on
        // the main form unless initialFocus says otherwise.
        // In Swift, @State must be initialized via _propertyName = State(initialValue:)
        // inside init — like setting useState's initial value in React.
        let startOnNameDesc: Bool
        if prefill != nil {
            // Recovery mode: show main form, no auto-focus.
            startOnNameDesc = false
        } else if case .new = mode {
            startOnNameDesc = initialFocus == nil || initialFocus?.isNameDescription == true
        } else {
            startOnNameDesc = initialFocus?.isNameDescription == true
        }
        self._showingNameDescription = State(initialValue: startOnNameDesc)
        self._pendingFocus = State(initialValue: initialFocus == .description ? .description : .name)

        // If recovering, pre-populate the habitId so tag associations are preserved.
        if let prefill {
            self._habitId = State(initialValue: prefill.habitId)
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
                : (mode.isNew ? "New Habit" : "Edit Habit"))
            .navigationBarTitleDisplayMode(.inline)
            // Fixed .medium detent (~half screen). Content scrolls within this
            // height. The sheet never resizes — simpler and more predictable.
            // Change mode gets a slightly taller sheet to accommodate the trade
            // button at bottom. .fraction(0.55) is just a bit taller than .medium
            // (~50%). New mode stays at .medium since there's no trade button.
            .presentationDetents([mode.isNew ? .medium : .fraction(0.55)])
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
                            didPersist = true
                            dismiss()
                        }
                        .disabled(!isValid)
                    }
                }
            }
            .sheet(isPresented: $showingFrequency) {
                FrequencyModal(frequency: $frequency)
            }
            .sheet(isPresented: $showingDifficulty, onDismiss: {
                // After the difficulty sheet closes, if a rank was set,
                // animate the pill to draw the user's attention.
                // The onDismiss fires after the sheet's dismiss animation
                // completes, so the form is fully visible again.
                if difficultyRank != nil {
                    // withAnimation triggers the scale-up immediately.
                    // DispatchQueue resets after 0.6s so the pill springs back.
                    // Like: setState(true); setTimeout(() => setState(false), 600)
                    withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                        difficultyPillAnimating = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                            difficultyPillAnimating = false
                        }
                    }
                }
            }) {
                DifficultyRankerView(
                    habitName: trimmedName.isEmpty ? "New Habit" : trimmedName,
                    difficultyRank: $difficultyRank,
                    currentDifficultyRank: difficultyRank,
                    excludeHabitId: mode.isNew ? nil : habitId
                )
            }
            .sheet(isPresented: $showingTags) {
                TagsView(habitId: habitId)
            }
            // Trade modal — presented when the "Claim Reward" button is tapped.
            // When the trade completes, onClaim fires, setting shouldDismissAfterTrade.
            // On dismiss, if the flag is set, this form also dismisses — returning
            // the user to the habit list (chained dismissal).
            .sheet(isPresented: $showingTradeModal, onDismiss: {
                if shouldDismissAfterTrade {
                    shouldDismissAfterTrade = false
                    dismiss()
                }
            }) {
                if case .change(let habit) = mode {
                    TradeModalView(habit: habit) {
                        shouldDismissAfterTrade = true
                    }
                }
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
            // Alert for tapping the difficulty pill on the first habit.
            // Since difficulty is auto-set, the ranker isn't needed — this
            // explains why. Like a <dialog> element shown via state in React.
            .alert("Difficulty Set", isPresented: $showingFirstHabitAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("There are no other habits to compare against. Add more habits to adjust difficulty ranking.")
            }
            .onChange(of: name) { _, _ in autoSave() }
            .onChange(of: description) { _, _ in autoSave() }
            .onChange(of: frequency) { _, _ in autoSave() }
            .onChange(of: difficultyRank) { _, _ in autoSave() }
            // When the form disappears without saving (user swiped, tapped
            // outside, or hit Cancel), notify the parent so it can show a
            // recovery toast. Like calling an onUnmount cleanup in React's
            // useEffect that checks if the form was "dirty".
            .onDisappear {
                if mode.isNew && !didPersist && hasContent {
                    onDiscard?(HabitFormSnapshot(
                        name: name,
                        description: description,
                        frequency: frequency,
                        difficultyRank: difficultyRank,
                        habitId: habitId
                    ))
                }
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

            // Trade section — only shown in change mode (not for new habits).
            // If frequency and difficulty are both set, shows a "Claim Reward"
            // button with the price. Otherwise shows a helper message telling
            // the user what they need to set.
            if case .change = mode {
                if canTrade {
                    Section {
                        Button {
                            showingTradeModal = true
                        } label: {
                            HStack {
                                Text("Claim Reward")
                                Spacer()
                                HStack(spacing: 2) {
                                    Text("\(currentPrice)")
                                        .contentTransition(.numericText())
                                    Image(systemName: "cube.fill")
                                        .font(.caption2)
                                }
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                            }
                        }
                    }
                } else {
                    Section {
                        Label {
                            Text("Set \(missingPropertiesText) to enable rewards")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
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

    // Whether this is the very first habit being created (no existing active habits).
    // When true, difficulty is auto-set to the midpoint since there's nothing to compare.
    // Like a selector in React: `const isFirstHabit = habits.length === 0 && mode === "new"`
    static func isFirstHabit(mode: HabitFormMode, activeHabitsCount: Int) -> Bool {
        mode.isNew && activeHabitsCount == 0
    }

    // The default difficulty rank assigned to the first habit ever created.
    // Delegates to the ranker's empty-session logic to get the midpoint key ("m").
    // Reuses existing DifficultyRanker logic rather than hardcoding the value.
    static func defaultDifficultyRankForFirstHabit() -> String {
        DifficultyRanker.makeSession(habitName: "", rankedHabits: []).generateRank()
    }

    // Whether there are ranked habits available for comparison, excluding the
    // current habit (which can't compare against itself). When false, the
    // ranker would immediately complete with nothing to show.
    // `rankedHabitCount` is the count of active habits with a difficultyRank,
    // already excluding the current habit's ID.
    static func hasComparableHabits(rankedHabitCount: Int, excludeHabitId: String?) -> Bool {
        rankedHabitCount > 0
    }

    // Whether tapping the difficulty pill should open the ranker modal.
    // Returns false when there's nothing to compare against — either because
    // it's the first habit (auto-set) or because no other ranked habits exist
    // (e.g. editing the only habit). An alert is shown instead.
    static func shouldOpenDifficultyRanker(isFirstHabit: Bool, hasComparableHabits: Bool) -> Bool {
        !isFirstHabit && hasComparableHabits
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
            // When there's nothing to compare against (first habit or editing
            // the only habit), show an informational alert instead of the ranker.
            "difficulty": {
                if Self.shouldOpenDifficultyRanker(isFirstHabit: isFirstHabit, hasComparableHabits: hasComparableHabits) {
                    showingDifficulty = true
                } else {
                    showingFirstHabitAlert = true
                }
            },
            "frequency": { showingFrequency = true },
        ]

        for i in pills.indices {
            pills[i].action = actions[pills[i].id]
            // Pass the animation state to the difficulty pill so it bounces
            // after the ranker sheet dismisses with a rank set.
            if pills[i].id == "difficulty" {
                pills[i].animating = difficultyPillAnimating
            }
        }
        return pills
    }

    // Initialize form state from the habit (change mode) or defaults (new mode).
    // Called from .task, which only runs once per view lifecycle (like useEffect
    // with [] deps). Sets hasAppliedInitialFocus at the end so auto-save
    // .onChange handlers skip firing during initial population.
    private func initializeForm() async {
        if let prefill, mode.isNew {
            // Recovery mode: restore the discarded form state.
            // habitId was already set in init() to preserve tag associations.
            name = prefill.name
            description = prefill.description
            frequency = prefill.frequency
            difficultyRank = prefill.difficultyRank
        } else if case .change(let habit) = mode {
            // Populate form from existing habit
            name = habit.name
            description = habit.description
            frequency = habit.frequency
            difficultyRank = habit.difficultyRank
            habitId = habit.id
        }

        // Auto-set difficulty for the first habit — no comparisons needed since
        // there are no other habits to compare against. The midpoint key ("m")
        // is used, leaving room for future habits above and below.
        if isFirstHabit && difficultyRank == nil {
            difficultyRank = Self.defaultDifficultyRankForFirstHabit()
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
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
}
