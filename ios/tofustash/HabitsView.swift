import SwiftUI

private struct HabitFormRoute: Identifiable {
    let id = UUID()
    let mode: HabitFormMode
    let initialFocus: HabitFormFocus?
    let prefill: HabitFormSnapshot?
}

struct HabitsView: View {
    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: HabitFormRoute? = nil
    @State private var tradingHabit: Habit? = nil
    @State private var habitToDelete: Habit? = nil
    @State private var toastManager = ToastManager()
    @State private var isListAtTop = true

    private var visibleHabits: [Habit] {
        EntityListQuery.apply(
            items: habitStore.activeHabits,
            preferences: listPreferencesStore.habitPreferences,
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: priceSortValue(for:),
            hasDifficulty: { $0.difficultyTier != nil },
            hasFrequency: { $0.frequency != nil },
            tags: { tagStore.tagsForHabit(habitId: $0.id) }
        )
    }

    private var availableHabitTags: [Tag] {
        let usedTagIDs = Set(
            tagStore.habitTags
                .filter { $0.deletedAt == nil }
                .map(\.tagId)
        )

        return tagStore.activeTags.filter { usedTagIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if habitStore.activeHabits.isEmpty {
                    ContentUnavailableView(
                        "No Habits Yet",
                        systemImage: "checkmark.circle",
                        description: Text("Tap + to create your first habit.")
                    )
                } else {
                    List {
                        controlsRow

                        Section {
                            if visibleHabits.isEmpty {
                                filteredEmptyStateRow
                            } else {
                                ForEach(visibleHabits) { habit in
                                    habitRow(habit)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button {
                                                // Behaviour: Swiping a row should only stage the delete
                                                // confirmation. SwiftUI animates `.destructive` swipe
                                                // buttons as if the row is already gone, which causes the
                                                // brief disappear/reappear glitch before the user confirms.
                                                habitToDelete = habit
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            .tint(.red)
                                        }
                                }
                            }
                        }
                    }
                    .lockControlsUnlessScrolledToTop(isAtTop: $isListAtTop)
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(0)
                    .contentMargins(.top, 0, for: .scrollContent)
                }
            }
            .navigationTitle("Habits")
            .onChange(of: visibleHabits.isEmpty) { _, isEmpty in
                if isEmpty {
                    isListAtTop = true
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    formRoute = HabitFormRoute(
                        mode: .new,
                        initialFocus: nil,
                        prefill: nil
                    )
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
            .sheet(item: $formRoute) { route in
                HabitFormView(
                    mode: route.mode,
                    initialFocus: route.initialFocus,
                    prefill: route.prefill,
                    onDiscard: route.mode.isNew ? { snapshot in
                        showDiscardToast(snapshot: snapshot)
                    } : nil,
                    onDelete: { habit in
                        habitToDelete = habit
                    }
                )
            }
            .sheet(item: $tradingHabit) { habit in
                TradeModalView(habit: habit)
            }
            .alert(
                "Delete Habit?",
                isPresented: Binding(
                    get: { habitToDelete != nil },
                    set: { if !$0 { habitToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let habit = habitToDelete {
                        habitStore.deleteHabit(id: habit.id)
                    }
                    habitToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    habitToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .overlay {
                ToastOverlay(toastManager: toastManager)
            }
        }
    }

    // Behaviour: when the user dismisses a new-habit sheet with unsaved content,
    // show a toast so they can recover the exact draft they just closed.
    private func showDiscardToast(snapshot: HabitFormSnapshot) {
        toastManager.show(
            message: "Habit Discarded",
            actionLabel: "Recover"
        ) {
            formRoute = HabitFormRoute(
                mode: .new,
                initialFocus: nil,
                prefill: snapshot
            )
        }
    }

    private func priceForHabit(_ habit: Habit) -> Int {
        let completionDates = tradeStore.habitTradeDates(habitId: habit.id)
        return RewardCalculation.calculateReward(
            habit: habit,
            allHabits: habitStore.activeHabits,
            completionDates: completionDates,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
    }

    private func priceSortValue(for habit: Habit) -> Int? {
        guard habit.canTrade else { return nil }
        return priceForHabit(habit)
    }

    private var controlsRow: some View {
        EntityListControls(
            preferences: listPreferencesStore.habitPreferences,
            availableTags: availableHabitTags,
            difficultyLabel: "Difficulty",
            frequencyLabel: "Freq",
            isEnabled: isListAtTop,
            onSelectSort: listPreferencesStore.setHabitSort,
            onSelectDifficultyFilter: listPreferencesStore.setHabitDifficultyFilter,
            onSelectFrequencyFilter: listPreferencesStore.setHabitFrequencyFilter,
            onSelectTagMatchMode: listPreferencesStore.setHabitTagMatchMode,
            onToggleTag: listPreferencesStore.toggleHabitTag,
            onClearFilters: listPreferencesStore.clearHabitFilters
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.top, -12)
        .padding(.bottom, -6)
    }

    private var filteredEmptyStateRow: some View {
        ContentUnavailableView {
            Label("No Matching Habits", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try changing the filters or clear them to see more habits.")
        } actions: {
            Button("Clear Filters") {
                listPreferencesStore.clearHabitFilters()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func habitRow(_ habit: Habit) -> some View {
        let tags = tagStore.tagsForHabit(habitId: habit.id)
        let canTrade = habit.canTrade

        return HStack(alignment: .bottom) {
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

                HStack(spacing: 8) {
                    habitMetaPill(
                        text: FrequencyConversion.formatSummary(habit.frequency) ?? "Frequency",
                        isSet: habit.frequency != nil,
                        animating: habit.frequency == nil
                    )

                    habitMetaPill(
                        text: habit.difficultyTier?.displayName ?? "Difficulty",
                        isSet: habit.difficultyTier != nil,
                        animating: habit.difficultyTier == nil
                    )
                }

                if !tags.isEmpty {
                    TagPillsRow(tags: tags)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                openChangeForm(habit, focus: nil)
            }

            if canTrade {
                let price = priceForHabit(habit)
                ClaimRewardButton(price: price, layout: .compact) {
                    tradingHabit = habit
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func habitMetaPill(text: String, isSet: Bool, animating: Bool) -> some View {
        EntityListMetaPill(text: text, isSet: isSet, animating: animating)
    }

    private func openChangeForm(_ habit: Habit, focus: HabitFormFocus?) {
        formRoute = HabitFormRoute(
            mode: .change(habit),
            initialFocus: focus,
            prefill: nil
        )
    }
}

#Preview {
    HabitsView()
        .environment(HabitStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
        .environment(ListPreferencesStore())
}
