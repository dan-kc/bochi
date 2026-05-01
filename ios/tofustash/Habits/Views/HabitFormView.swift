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
    case duration
    case lockout
    case skipConsequence
    case reminders
    case tags
}

// Captures the draft values from a dismissed new-habit form so the user can
// recover what they typed from a toast or another recovery affordance.
struct HabitFormSnapshot {
    let name: String
    let description: String
    let frequency: Double?
    let difficultyTier: HabitDifficultyTier?
    let durationSeconds: Int?
    let lockoutDurationSeconds: Int?
    let skipConsequence: Int?
    let reminderDrafts: [ReminderDraft]
    let habitId: RecordID
}

struct HabitFormView: View {
    let mode: HabitFormMode
    let initialFocus: HabitFormFocus?
    let prefill: HabitFormSnapshot?
    let onCreated: ((Habit) -> Void)?
    let onDiscard: ((HabitFormSnapshot) -> Void)?
    let onDelete: ((Habit) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(ReminderStore.self) private var reminderStore
    @State private var name = ""
    @State private var description = ""
    @State private var frequency: Double? = nil
    @State private var difficultyTier: HabitDifficultyTier? = nil
    @State private var durationSeconds: Int? = nil
    @State private var lockoutDurationSeconds: Int? = nil
    @State private var skipConsequence: Int? = nil
    @State private var reminderDrafts: [ReminderDraft] = []
    @State private var habitId = RecordID()

    @State private var showingFrequency = false
    @State private var showingDifficulty = false
    @State private var showingDuration = false
    @State private var showingLockout = false
    @State private var showingSkipConsequence = false
    @State private var showingReminders = false
    @State private var showingTags = false
    @State private var tradingHabit: Habit? = nil
    @State private var showingHistory = false
    @State private var showingDeleteConfirmation = false

    @State private var hasInitialized = false
    @State private var hasAppliedInitialLoad = false
    @State private var didPersist = false
    @FocusState private var focusedField: FieldFocus?

    enum FieldFocus: Hashable {
        case name
        case description
    }

    private var habitTags: [Tag] {
        tagStore.tagsForHabit(habitId: habitId)
    }

    private var activeReminderDrafts: [ReminderDraft] {
        ReminderDraftSupport.active(reminderDrafts, now: reminderStore.referenceDate)
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

    private var showsTradeButton: Bool {
        !isNewMode
    }

    private var draftHabit: Habit {
        switch mode {
        case .new:
            return Habit(
                id: habitId,
                name: Self.nameForAutoSave(name),
                description: description,
                createdAt: Date(),
                updatedAt: Date(),
                deletedAt: nil,
                frequency: frequency,
                difficultyTier: difficultyTier,
                durationSeconds: durationSeconds,
                lockoutDurationSeconds: lockoutDurationSeconds,
                skipConsequence: skipConsequence
            )
        case .change(let existingHabit):
            return Habit(
                id: existingHabit.id,
                name: Self.nameForAutoSave(name).isEmpty ? existingHabit.name : Self.nameForAutoSave(name),
                description: description,
                createdAt: existingHabit.createdAt,
                updatedAt: existingHabit.updatedAt,
                deletedAt: existingHabit.deletedAt,
                frequency: frequency,
                difficultyTier: difficultyTier,
                durationSeconds: durationSeconds,
                lockoutDurationSeconds: lockoutDurationSeconds,
                skipConsequence: skipConsequence
            )
        }
    }

    private var isLocked: Bool {
        HabitLockout.isLocked(habit: draftHabit, tradeStore: tradeStore)
    }

    private var lockoutSummary: String? {
        guard let remainingSeconds = HabitLockout.remainingSeconds(habit: draftHabit, tradeStore: tradeStore) else {
            return nil
        }
        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: description,
            frequency: frequency,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            lockoutDurationSeconds: lockoutDurationSeconds,
            skipConsequence: skipConsequence,
            reminderCount: activeReminderDrafts.count,
            tagCount: habitTags.count,
            isFirstHabit: false
        )
    }

    private var currentPrice: Int {
        let completionDates = tradeStore.habitTradeDates(habitId: draftHabit.id)
        return RewardCalculation.calculateReward(
            habit: draftHabit,
            allHabits: habitStore.activeHabits,
            completionDates: completionDates
        )
    }

    init(
        mode: HabitFormMode = .new,
        initialFocus: HabitFormFocus? = nil,
        prefill: HabitFormSnapshot? = nil,
        onCreated: ((Habit) -> Void)? = nil,
        onDiscard: ((HabitFormSnapshot) -> Void)? = nil,
        onDelete: ((Habit) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onCreated = onCreated
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
                            TagPillsRow(tags: habitTags, size: .form, leadingInset: 16)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showingTags = true
                                }
                                .opacity(isEditingText ? 0 : 1)
                                .allowsHitTesting(!isEditingText)
                        }

                        PillRow(pills: buildPills(), leadingInset: 16, trailingInset: 16)
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
                            Button("History") {
                                showingHistory = true
                            }

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

                        if isNewMode {
                            guard !trimmedName.isEmpty else { return }
                            guard let habit = persistHabit() else { return }
                            didPersist = true
                            onCreated?(habit)
                        } else {
                            didPersist = true
                            _ = persistHabit()
                        }
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
            TierSelectionSheet(
                title: "Set Difficulty",
                currentSelection: difficultyTier,
                onSave: { difficultyTier = $0 },
                onUnset: difficultyTier != nil ? { difficultyTier = nil } : nil
            )
        }
        .sheet(isPresented: $showingDuration) {
            HabitDurationModal(durationSeconds: $durationSeconds)
        }
        .sheet(isPresented: $showingLockout) {
            HabitLockoutDurationModal(durationSeconds: $lockoutDurationSeconds)
        }
        .sheet(isPresented: $showingSkipConsequence) {
            TierSelectionSheet(
                title: "Set Skip Consequence",
                currentSelection: SkipConsequenceTier.from(skipConsequence),
                onSave: { skipConsequence = $0?.rawValue },
                onUnset: skipConsequence != nil ? { skipConsequence = nil } : nil
            )
        }
        .sheet(isPresented: $showingReminders) {
            ReminderModalView(
                reminders: $reminderDrafts,
                dueDate: nil,
                referenceDate: reminderStore.referenceDate
            )
        }
        .sheet(isPresented: $showingTags) {
            TagsView(selectionMode: .assignment(.habit(habitId)))
        }
        .sheet(item: $tradingHabit) { habit in
            TradeModalView(habit: habit) {
                dismiss()
            }
        }
        .sheet(isPresented: $showingHistory) {
            TradeHistorySheetView(
                filter: .habit(draftHabit.id),
                detents: [.large]
            )
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
        .onChange(of: name) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: description) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: frequency) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: difficultyTier) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: durationSeconds) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: lockoutDurationSeconds) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: skipConsequence) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: reminderDrafts) { _, _ in
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
                    difficultyTier: difficultyTier,
                    durationSeconds: durationSeconds,
                    lockoutDurationSeconds: lockoutDurationSeconds,
                    skipConsequence: skipConsequence,
                    reminderDrafts: reminderDrafts,
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
                if isLocked {
                    lockedTradeSummary
                } else {
                    tradeButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockedTradeSummary: some View {
        HStack {
            Label("Locked", systemImage: "lock.fill")
            Spacer()
            if let lockoutSummary {
                Text(lockoutSummary)
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: Capsule())
    }

    private var tradeButton: some View {
        ClaimRewardButton(price: currentPrice, layout: .expanded(title: "Claim Reward")) {
            guard !HabitLockout.isLocked(habit: draftHabit, tradeStore: tradeStore) else { return }
            guard let persistedHabit = persistHabit() else { return }
            didPersist = true
            tradingHabit = persistedHabit
        }
    }

    static func hasContent(
        name: String,
        description: String,
        frequency: Double?,
        difficultyTier: HabitDifficultyTier?,
        durationSeconds: Int?,
        lockoutDurationSeconds: Int?,
        skipConsequence: Int?,
        reminderCount: Int,
        tagCount: Int,
        isFirstHabit: Bool = false
    ) -> Bool {
        EntityFormSupport.hasRecoverableContent(
            name: name,
            description: description,
            primaryValueIsSet: frequency != nil,
            secondaryValueIsSet: difficultyTier != nil,
            tagCount: tagCount,
            ignoreSecondaryValue: isFirstHabit
        ) || durationSeconds != nil || lockoutDurationSeconds != nil || skipConsequence != nil || reminderCount > 0
    }

    static func nameForAutoSave(_ name: String) -> String {
        EntityFormSupport.trimmedName(name)
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        difficultyTier: HabitDifficultyTier?,
        frequency: Double?,
        durationSeconds: Int?,
        lockoutDurationSeconds: Int?,
        skipConsequence: Int?,
        reminderSummary: String,
        hasReminders: Bool
    ) -> [EntityFormPillConfig] {
        let frequencyLabel = FrequencyConversion.formatSummary(frequency) ?? "Frequency"
        let durationLabel = DurationFormatting.summary(seconds: durationSeconds) ?? "Duration"
        let lockoutLabel = DurationFormatting.summary(seconds: lockoutDurationSeconds) ?? "Lockout"
        let skipLabel = SkipConsequenceTier.from(skipConsequence)?.displayName ?? "Skip"
        return [
            EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            EntityFormPillConfig(id: "difficulty", label: difficultyTier?.displayName ?? "Difficulty", icon: "chart.bar", isSet: difficultyTier != nil),
            EntityFormPillConfig(id: "frequency", label: frequencyLabel, icon: "clock", isSet: frequency != nil),
            EntityFormPillConfig(id: "reminders", label: reminderSummary, icon: "bell", isSet: hasReminders),
            EntityFormPillConfig(id: "duration", label: durationLabel, icon: "timer", isSet: durationSeconds != nil),
            EntityFormPillConfig(id: "lockout", label: lockoutLabel, icon: "lock", isSet: lockoutDurationSeconds != nil),
            EntityFormPillConfig(id: "skip", label: skipLabel, icon: "exclamationmark.triangle", isSet: skipConsequence != nil),
        ]
    }

    private func buildPills() -> [PillItem] {
        let configs = Self.buildPillData(
            hasTagsApplied: !habitTags.isEmpty,
            difficultyTier: difficultyTier,
            frequency: frequency,
            durationSeconds: durationSeconds,
            lockoutDurationSeconds: lockoutDurationSeconds,
            skipConsequence: skipConsequence,
            reminderSummary: ReminderDraftSupport.summary(for: reminderDrafts, now: reminderStore.referenceDate),
            hasReminders: !activeReminderDrafts.isEmpty
        )
        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "difficulty": { showingDifficulty = true },
            "frequency": { showingFrequency = true },
            "reminders": { showingReminders = true },
            "duration": { showingDuration = true },
            "lockout": { showingLockout = true },
            "skip": { showingSkipConsequence = true },
        ]

        return EntityFormSupport.buildPills(
            configs: configs,
            actions: actions
        )
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, mode.isNew {
            name = prefill.name
            description = prefill.description
            frequency = prefill.frequency
            difficultyTier = prefill.difficultyTier
            durationSeconds = prefill.durationSeconds
            lockoutDurationSeconds = prefill.lockoutDurationSeconds
            skipConsequence = prefill.skipConsequence
            reminderDrafts = prefill.reminderDrafts
            habitId = prefill.habitId
        } else if case .change(let habit) = mode {
            name = habit.name
            description = habit.description
            frequency = habit.frequency
            difficultyTier = habit.difficultyTier
            durationSeconds = habit.durationSeconds
            lockoutDurationSeconds = habit.lockoutDurationSeconds
            skipConsequence = habit.skipConsequence
            reminderDrafts = reminderStore.reminderDrafts(for: .habit(habit.id))
            habitId = habit.id
        }

        hasAppliedInitialLoad = true

        guard let initialFocus else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch initialFocus {
            case .frequency:
                showingFrequency = true
            case .difficulty:
                showingDifficulty = true
            case .duration:
                showingDuration = true
            case .lockout:
                showingLockout = true
            case .skipConsequence:
                showingSkipConsequence = true
            case .reminders:
                showingReminders = true
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
            let habit = habitStore.addHabit(
                id: habitId,
                name: name,
                description: description,
                frequency: frequency,
                difficultyTier: difficultyTier,
                durationSeconds: durationSeconds,
                lockoutDurationSeconds: lockoutDurationSeconds,
                skipConsequence: skipConsequence
            )
            if habit != nil {
                reminderStore.replaceReminders(for: .habit(habitId), with: reminderDrafts)
            }
            return habit
        }

        habitStore.updateHabit(
            id: habitId,
            name: Self.nameForAutoSave(name),
            description: description,
            frequency: .some(frequency),
            difficultyTier: .some(difficultyTier),
            durationSeconds: .some(durationSeconds),
            lockoutDurationSeconds: .some(lockoutDurationSeconds),
            skipConsequence: .some(skipConsequence)
        )
        reminderStore.replaceReminders(for: .habit(habitId), with: reminderDrafts)

        return draftHabit
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
        Group {
            switch layout {
            case .compact:
                TofuActionSurface(layout: .compact, action: action) {
                    labelContent
                }
            case .expanded:
                TofuActionSurface(layout: .expanded(tint: tintColor), action: action) {
                    labelContent
                }
            }
        }
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
