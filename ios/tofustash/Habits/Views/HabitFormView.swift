import SwiftUI

// HabitFormMode is like a discriminated union in TypeScript:
//   { type: "new" } | { type: "change", habit: Habit }
//
// Swift enums can carry data directly, so `.change` includes the habit being edited.
enum HabitFormMode: Equatable {
    case new
    case change(Habit)

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

// Which secondary editor should open automatically when the form appears.
// This is used when the user taps a specific affordance from the habit list.
enum HabitFormFocus: Equatable {
    case frequency
    case difficulty
    case tags
}

// Captures the draft values from a dismissed new-habit form so the user can
// recover what they typed from a toast or another recovery affordance.
struct HabitFormSnapshot {
    let name: String
    let description: String
    let frequency: Double?
    let difficultyRank: String?
    let habitId: String
}

struct HabitFormView: View {
    let mode: HabitFormMode
    let initialFocus: HabitFormFocus?
    let prefill: HabitFormSnapshot?
    let onDiscard: ((HabitFormSnapshot) -> Void)?
    let onDelete: ((Habit) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    @State private var name = ""
    @State private var description = ""
    @State private var frequency: Double? = nil
    @State private var difficultyRank: String? = nil
    @State private var habitId: String = UUID().uuidString

    @State private var showingFrequency = false
    @State private var showingDifficulty = false
    @State private var showingTags = false
    @State private var tradingHabit: Habit? = nil
    @State private var showingDeleteConfirmation = false

    @State private var hasInitialized = false
    @State private var hasAppliedInitialLoad = false
    @State private var didPersist = false
    @State private var timeBucket = RewardCalculation.getCurrentTimeBucket()
    @FocusState private var focusedField: FieldFocus?

    enum FieldFocus: Hashable {
        case name
        case description
    }

    private var habitTags: [Tag] {
        tagStore.tagsForHabit(habitId: habitId)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNewMode: Bool {
        mode.isNew
    }

    private var isFirstHabit: Bool {
        Self.isFirstHabit(mode: mode, activeHabitsCount: habitStore.activeHabits.count)
    }

    private var hasComparableHabits: Bool {
        let rankedCount = habitStore.activeHabits
            .filter { $0.difficultyRank != nil && $0.id != habitId }
            .count
        return Self.hasComparableHabits(rankedHabitCount: rankedCount, excludeHabitId: mode.isNew ? nil : habitId)
    }

    private var canTrade: Bool {
        frequency != nil && difficultyRank != nil
    }

    private var showsTradeButton: Bool {
        !isNewMode && canTrade
    }

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

    // The trade preview is based on the draft currently visible in the sheet.
    // If the user changes frequency or difficulty, the price preview follows the
    // draft immediately instead of waiting for them to close and reopen.
    private var draftHabitForTrade: Habit? {
        guard case .change(let existingHabit) = mode else { return nil }

        return Habit(
            id: existingHabit.id,
            name: Self.nameForAutoSave(name).isEmpty ? existingHabit.name : Self.nameForAutoSave(name),
            description: description,
            createdAt: existingHabit.createdAt,
            updatedAt: existingHabit.updatedAt,
            deletedAt: existingHabit.deletedAt,
            frequency: frequency,
            difficultyRank: difficultyRank
        )
    }

    private var currentPrice: Int {
        guard let habit = draftHabitForTrade else { return 0 }
        let completions = tradeStore.tradesInPeriod(habitId: habit.id, days: 7)
        return RewardCalculation.calculateReward(
            habit: habit,
            allHabits: habitStore.activeHabits,
            completionsInPeriod: completions,
            timeBucket: timeBucket,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
    }

    init(
        mode: HabitFormMode = .new,
        initialFocus: HabitFormFocus? = nil,
        prefill: HabitFormSnapshot? = nil,
        onDiscard: ((HabitFormSnapshot) -> Void)? = nil,
        onDelete: ((Habit) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onDiscard = onDiscard
        self.onDelete = onDelete
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        textFieldsSection
                            .padding(.horizontal, 16)

                        if !habitTags.isEmpty {
                            TagPillsRow(tags: habitTags, leadingInset: 16)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showingTags = true
                                }
                                .opacity(isEditingText ? 0 : 1)
                                .allowsHitTesting(!isEditingText)
                        }

                        PillRow(pills: buildPills(), leadingInset: 16)
                            .opacity(isEditingText ? 0 : 1)
                            .allowsHitTesting(!isEditingText)

                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear.frame(height: showsTradeButton ? 94 : 16)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)

                floatingControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .opacity(isEditingText ? 0 : 1)
                    .allowsHitTesting(!isEditingText)
            }
            .navigationTitle(isNewMode ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isNewMode {
                        Button("Cancel") {
                            dismiss()
                        }
                    } else if case .change = mode {
                        Menu {
                            Button("Delete Habit", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingText ? "Done" : (isNewMode ? "Add" : "Done")) {
                        if isEditingText {
                            focusedField = nil
                            return
                        }

                        guard isNewMode ? !trimmedName.isEmpty : true else { return }
                        didPersist = true
                        _ = persistHabit()
                        dismiss()
                    }
                    .disabled(!isEditingText && isNewMode && trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.18), value: isEditingText)
        .sheet(isPresented: $showingFrequency) {
            FrequencyModal(frequency: $frequency)
        }
        .sheet(isPresented: $showingDifficulty) {
            DifficultyRankerView(
                habitName: trimmedName.isEmpty ? "New Habit" : trimmedName,
                difficultyRank: $difficultyRank,
                currentDifficultyRank: difficultyRank,
                excludeHabitId: mode.isNew ? nil : habitId
            )
        }
        .sheet(isPresented: $showingTags) {
            TagsView(target: .habit(habitId))
        }
        .sheet(item: $tradingHabit) { habit in
            TradeModalView(habit: habit) {
                dismiss()
            }
        }
        .alert("Delete Habit?", isPresented: $showingDeleteConfirmation) {
            if case .change(let habit) = mode {
                Button("Delete", role: .destructive) {
                    dismiss()
                    onDelete?(habit)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .task {
            // `.task` is SwiftUI's lifecycle hook for async startup work. Here it
            // hydrates the form once when the sheet appears.
            initializeIfNeeded()
        }
        .task {
            // Behaviour: while the user keeps the edit sheet open, the previewed
            // reward price refreshes right when the next minute bucket starts.
            while !Task.isCancelled {
                let nanos = RewardCalculation.nanosUntilNextBucket()
                try? await Task.sleep(nanoseconds: nanos)
                timeBucket = RewardCalculation.getCurrentTimeBucket()
            }
        }
        .onChange(of: name) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: description) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: frequency) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: difficultyRank) { _, _ in
            autoSaveIfNeeded()
        }
        .onDisappear {
            // New-habit dismissal is treated as a recoverable discard only when
            // the user actually entered meaningful content.
            if isNewMode && !didPersist && hasContent {
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

    private var textFieldsSection: some View {
        EntityFormTextFieldsSection(
            name: $name,
            description: $description,
            focusedField: $focusedField,
            nameFocus: .name,
            descriptionFocus: .description
        )
    }

    private var floatingControls: some View {
        VStack(spacing: 10) {
            if showsTradeButton {
                tradeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tradeButton: some View {
        ClaimRewardButton(price: currentPrice, layout: .expanded(title: "Claim Reward")) {
            guard let persistedHabit = persistHabit() else { return }
            didPersist = true
            tradingHabit = persistedHabit
        }
    }

    static func hasContent(
        name: String,
        description: String,
        frequency: Double?,
        difficultyRank: String?,
        tagCount: Int,
        isFirstHabit: Bool = false
    ) -> Bool {
        let hasDifficulty = isFirstHabit ? false : difficultyRank != nil

        return !name.isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || frequency != nil
            || hasDifficulty
            || tagCount > 0
    }

    static func nameForAutoSave(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
    }

    static func isFirstHabit(mode: HabitFormMode, activeHabitsCount: Int) -> Bool {
        mode.isNew && activeHabitsCount == 0
    }

    static func defaultDifficultyRankForFirstHabit() -> String {
        DifficultyRanker.makeSession(habitName: "", rankedHabits: []).generateRank()
    }

    static func hasComparableHabits(rankedHabitCount: Int, excludeHabitId: String?) -> Bool {
        rankedHabitCount > 0
    }

    static func shouldOpenDifficultyRanker(hasComparableHabits: Bool) -> Bool {
        hasComparableHabits
    }

    static func difficultyRankAfterSelection(
        currentDifficultyRank: String?,
        hasComparableHabits: Bool
    ) -> String? {
        guard !hasComparableHabits, currentDifficultyRank == nil else {
            return currentDifficultyRank
        }

        return defaultDifficultyRankForFirstHabit()
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        difficultyRank: String?,
        frequency: Double?
    ) -> [PillItem] {
        let frequencyLabel = FrequencyConversion.formatSummary(frequency) ?? "Frequency"
        return [
            PillItem(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            PillItem(id: "difficulty", label: "Difficulty", icon: "chart.bar", isSet: difficultyRank != nil),
            PillItem(id: "frequency", label: frequencyLabel, icon: "clock", isSet: frequency != nil),
        ]
    }

    private func buildPills() -> [PillItem] {
        var pills = Self.buildPillData(
            hasTagsApplied: !habitTags.isEmpty,
            difficultyRank: difficultyRank,
            frequency: frequency
        )

        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "difficulty": {
                if Self.shouldOpenDifficultyRanker(hasComparableHabits: hasComparableHabits) {
                    showingDifficulty = true
                } else {
                    difficultyRank = Self.difficultyRankAfterSelection(
                        currentDifficultyRank: difficultyRank,
                        hasComparableHabits: hasComparableHabits
                    )
                }
            },
            "frequency": { showingFrequency = true },
        ]

        for index in pills.indices {
            pills[index].action = actions[pills[index].id]

            if !canTrade {
                let shouldPulse =
                    (pills[index].id == "frequency" && frequency == nil) ||
                    (pills[index].id == "difficulty" && difficultyRank == nil)
                pills[index].animating = shouldPulse
            }
        }

        return pills
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, mode.isNew {
            name = prefill.name
            description = prefill.description
            frequency = prefill.frequency
            difficultyRank = prefill.difficultyRank
            habitId = prefill.habitId
        } else if case .change(let habit) = mode {
            name = habit.name
            description = habit.description
            frequency = habit.frequency
            difficultyRank = habit.difficultyRank
            habitId = habit.id
        }

        // Behaviour: the very first habit gets a midpoint difficulty automatically
        // because there is nothing else to compare it against yet.
        if isFirstHabit && difficultyRank == nil {
            difficultyRank = Self.defaultDifficultyRankForFirstHabit()
        }

        hasAppliedInitialLoad = true

        guard let initialFocus else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch initialFocus {
            case .frequency:
                showingFrequency = true
            case .difficulty:
                if Self.shouldOpenDifficultyRanker(hasComparableHabits: hasComparableHabits) {
                    showingDifficulty = true
                } else {
                    difficultyRank = Self.difficultyRankAfterSelection(
                        currentDifficultyRank: difficultyRank,
                        hasComparableHabits: hasComparableHabits
                    )
                }
            case .tags:
                showingTags = true
            }
        }
    }

    private func autoSaveIfNeeded() {
        guard !isNewMode, hasAppliedInitialLoad else { return }
        _ = persistHabit()
    }

    @discardableResult
    private func persistHabit() -> Habit? {
        if case .new = mode {
            return habitStore.addHabit(
                id: habitId,
                name: name,
                description: description,
                frequency: frequency,
                difficultyRank: difficultyRank
            )
        }

        habitStore.updateHabit(
            id: habitId,
            name: Self.nameForAutoSave(name),
            description: description,
            frequency: .some(frequency),
            difficultyRank: .some(difficultyRank)
        )

        return draftHabitForTrade
    }
}

// A shared claim button keeps the list row and edit form visually aligned while
// centralizing the "price changed" animation in one place.
struct ClaimRewardButton: View {
    enum Layout {
        case compact
        case expanded(title: String)
    }

    let price: Int
    let layout: Layout
    let action: () -> Void

    @State private var displayedPrice: Int
    @State private var tintColor: Color = Self.baseTint
    @State private var hasAppeared = false
    @State private var colorResetTask: Task<Void, Never>? = nil

    private static let baseTint: Color = .gray

    init(price: Int, layout: Layout, action: @escaping () -> Void) {
        self.price = price
        self.layout = layout
        self.action = action
        _displayedPrice = State(initialValue: price)
    }

    var body: some View {
        Button(action: action) {
            labelContent
        }
        .buttonStyle(.borderedProminent)
        .tint(tintColor)
        .controlSize(controlSize)
        .clipShape(Capsule())
        .onAppear {
            displayedPrice = price
            tintColor = Self.baseTint
            hasAppeared = true
        }
        .onChange(of: price) { oldPrice, newPrice in
            guard oldPrice != newPrice else { return }

            // Behaviour: users see whether the minute refresh helped or hurt the
            // current deal before the button settles back to its neutral state.
            guard hasAppeared else {
                displayedPrice = newPrice
                return
            }

            animatePriceChange(from: oldPrice, to: newPrice)
        }
        .onDisappear {
            colorResetTask?.cancel()
        }
    }

    private var priceValue: some View {
        Text("+\(displayedPrice)")
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private var labelContent: some View {
        switch layout {
        case .compact:
            HStack(spacing: 4) {
                priceValue
                Image(systemName: "cube.fill")
                    .font(.caption2)
            }
            .font(.callout)
            .fontWeight(.semibold)
        case .expanded(let title):
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 4) {
                    priceValue
                    Image(systemName: "cube.fill")
                        .font(.caption2)
                }
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var controlSize: ControlSize {
        switch layout {
        case .compact:
            return .regular
        case .expanded:
            return .large
        }
    }

    private func animatePriceChange(from oldPrice: Int, to newPrice: Int) {
        colorResetTask?.cancel()

        let flashColor: Color = newPrice < oldPrice ? .red : .green

        withAnimation(.easeIn(duration: 0.2)) {
            tintColor = flashColor
        }

        withAnimation(.easeInOut(duration: 0.6)) {
            displayedPrice = newPrice
        }

        colorResetTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    tintColor = Self.baseTint
                }
            }
        }
    }
}

#Preview("New Habit") {
    HabitFormView(mode: .new)
        .environment(HabitStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
}
