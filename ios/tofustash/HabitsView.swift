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
    @Environment(SpecialOfferStore.self) private var specialOfferStore
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: HabitFormRoute? = nil
    @State private var tradingHabitRoute: HabitTradeRoute? = nil
    @State private var historyHabit: Habit? = nil
    @State private var habitToDelete: Habit? = nil
    @State private var toastManager = ToastManager()
    @State private var pendingScrollTargetID: RecordID? = nil
    @State private var highlightedHabitID: RecordID? = nil
    @Namespace private var searchChromeNamespace
    @State private var searchState = EntityListSearchState()

    private var filterState: EntityListFilterState {
        EntityListFilterState(
            preferences: listPreferencesStore.habitPreferences,
            search: searchState
        )
    }

    private func visibleHabits(offerSnapshot: SpecialOfferSnapshot) -> [Habit] {
        EntityListQuery.apply(
            items: habitStore.activeHabits,
            filterState: filterState,
            validTagIDs: tagStore.activeTagIDs,
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { priceSortValue(for: $0, offerSnapshot: offerSnapshot) },
            tags: { tagStore.tagsForHabit(habitId: $0.id) }
        )
    }

    var body: some View {
        let offerSnapshot = specialOfferStore.makeSnapshot()
        let visibleHabits = visibleHabits(offerSnapshot: offerSnapshot)
        let habitSections = EntityListSectionSupport.habitSections(
            habits: visibleHabits,
            tradeStore: tradeStore
        )

        NavigationStack {
            EntityListScreen(
                hasAnyItems: !habitStore.activeHabits.isEmpty,
                visibleItemCount: visibleHabits.count,
                emptyTitle: "No Habits Yet",
                emptySystemImage: "checkmark.circle",
                emptyDescription: "Tap + to create your first habit.",
                filteredEmptyTitle: "No Matching Habits",
                filteredEmptyDescription: "Try changing the search text or selected tags to see more habits.",
                searchPrompt: "Search habits",
                searchChromeNamespace: searchChromeNamespace,
                filterState: filterState,
                tagScope: .habits,
                rowIDs: visibleHabits.map(\.id),
                searchState: $searchState,
                pendingScrollTargetID: $pendingScrollTargetID,
                onAdd: openNewHabitForm,
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setHabitSort(option)
                    }
                },
                onClearFilters: listPreferencesStore.clearHabitFilters,
                onPendingScrollCompleted: { habitID in
                    scheduleNewHabitHighlightFade(for: habitID)
                }
            ) {
                ForEach(habitSections) { section in
                    Section {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, habit in
                            EntityListRowSurface(
                                showsDivider: index < section.items.count - 1,
                                isHighlighted: highlightedHabitID == habit.id,
                                isSpecialOffer: offerSnapshot.hasActiveOffer(for: .habit, entityID: habit.id)
                            ) {
                                habitRow(habit, offerSnapshot: offerSnapshot, isDimmed: section.isDimmed)
                            }
                            .id(habit.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    // Behaviour: Swiping a row should only stage the delete
                                    // confirmation. SwiftUI animates `.destructive` swipe
                                    // buttons as if the row is already gone, which causes the
                                    // brief disappear/reappear glitch before the user confirms.
                                    confirmDelete(habit)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                            .contextMenu {
                                habitRowMenu(habit, offerSnapshot: offerSnapshot)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        if let title = section.title {
                            EntityListSectionHeader(title: title)
                        }
                    }
                }
            }
            .navigationTitle("Habits")
            .overlay(alignment: .bottomTrailing) {
                EntityListFloatingActionOverlay(
                    showsSearchButton: !habitStore.activeHabits.isEmpty,
                    namespace: searchChromeNamespace,
                    searchState: $searchState,
                    onAdd: openNewHabitForm
                )
            }
            .sheet(item: $formRoute) { route in
                HabitFormView(
                    mode: route.mode,
                    initialFocus: route.initialFocus,
                    prefill: route.prefill,
                    onCreated: { habit in
                        queueScrollToHabitIfVisible(habit.id)
                    },
                    onDiscard: route.mode.isNew ? { snapshot in
                        showDiscardToast(snapshot: snapshot)
                    } : nil,
                    onDelete: { habit in
                        deleteHabit(habit)
                    }
                )
            }
            .sheet(item: $tradingHabitRoute) { route in
                TradeModalView(
                    habit: route.habit,
                    resolvedSpecialOffer: route.resolvedSpecialOffer
                )
            }
            .sheet(item: $historyHabit) { habit in
                TradeHistorySheetView(
                    filter: .habit(habit.id),
                    detents: [.large]
                )
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
                        deleteHabit(habit)
                    }
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
            .onAppear {
                schedulePendingHabitFormOpenIfNeeded()
            }
            .onChange(of: appNavigationStore.pendingEntityFormRequest) { _, _ in
                schedulePendingHabitFormOpenIfNeeded()
            }
            .onChange(of: appNavigationStore.selectedTab) { _, selectedTab in
                guard selectedTab == .habits else { return }
                schedulePendingHabitFormOpenIfNeeded()
            }
        }
    }

    private func openNewHabitForm() {
        formRoute = HabitFormRoute(
            mode: .new,
            initialFocus: nil,
            prefill: nil
        )
    }

    private func confirmDelete(_ habit: Habit) {
        habitToDelete = habit
    }

    private func deleteHabit(_ habit: Habit) {
        reminderStore.deleteAllReminders(for: .habit(habit.id))
        withAnimation(.default) {
            habitStore.deleteHabit(id: habit.id)
            habitToDelete = nil
        }
    }

    // Behaviour: when the user dismisses a new-habit sheet with unsaved content,
    // show a toast so they can recover the exact draft they just closed.
    private func showDiscardToast(snapshot: HabitFormSnapshot) {
        EntityListViewCoordinator.showDiscardToast(
            toastManager: toastManager,
            entityName: "Habit",
            snapshot: snapshot,
            makeRoute: {
                HabitFormRoute(mode: .new, initialFocus: nil, prefill: $0)
            },
            setRoute: { formRoute = $0 }
        )
    }

    private func priceForHabit(_ habit: Habit, offerSnapshot: SpecialOfferSnapshot) -> Int {
        let completionDates = tradeStore.habitTradeDates(habitId: habit.id)
        return RewardCalculation.calculateReward(
            habit: habit,
            allHabits: habitStore.activeHabits,
            completionDates: completionDates,
            specialOfferModifierPercent: offerSnapshot.activeModifierPercent(for: .habit, entityID: habit.id)
        )
    }

    private func priceSortValue(for habit: Habit, offerSnapshot: SpecialOfferSnapshot) -> Int? {
        let isLocked = HabitLockout.isLocked(habit: habit, tradeStore: tradeStore)
        return EntityActionSupport.sortableAmount(isActionable: habit.canTrade && !isLocked) {
            priceForHabit(habit, offerSnapshot: offerSnapshot)
        }
    }

    private func habitRow(
        _ habit: Habit,
        offerSnapshot: SpecialOfferSnapshot,
        isDimmed: Bool
    ) -> some View {
        let tags = tagStore.tagsForHabit(habitId: habit.id)
        let isLocked = HabitLockout.isLocked(habit: habit, tradeStore: tradeStore)
        let offer = offerSnapshot.activeOffer(for: .habit, entityID: habit.id)

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
                    EntityListMetaPill(
                        text: FrequencyConversion.formatSummary(habit.frequency) ?? "Frequency",
                        isSet: habit.frequency != nil
                    )

                    EntityListMetaPill(
                        text: habit.difficultyTier?.displayName ?? "Difficulty",
                        isSet: habit.difficultyTier != nil
                    )

                    if let offer {
                        SpecialOfferMetaPill(offer: offer)
                    }
                }

                if !tags.isEmpty {
                    TagPillsRow(
                        tags: tags,
                        leadingInset: 16,
                        showsTrailingFade: true,
                        trailingFadeInset: 36
                    )
                    .padding(.leading, -16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if habit.canTrade {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44, alignment: .center)
                } else {
                    let price = priceForHabit(habit, offerSnapshot: offerSnapshot)
                    ClaimRewardButton(price: price, layout: .compact) {
                        openTradeModal(for: habit, offer: offer)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            openChangeForm(habit, focus: nil)
        }
    }

    @ViewBuilder
    private func habitRowMenu(_ habit: Habit, offerSnapshot: SpecialOfferSnapshot) -> some View {
        let isLocked = HabitLockout.isLocked(habit: habit, tradeStore: tradeStore)

        if habit.canTrade && !isLocked {
            let offer = offerSnapshot.activeOffer(for: .habit, entityID: habit.id)
            Button {
                openTradeModal(for: habit, offer: offer)
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        }

        EntityRowContextMenuActions.editHistoryDelete(
            onEdit: {
                openChangeForm(habit, focus: nil)
            },
            onViewHistory: {
                historyHabit = habit
            },
            onDelete: {
                confirmDelete(habit)
            }
        )
    }

    private func openChangeForm(_ habit: Habit, focus: HabitFormFocus?) {
        formRoute = HabitFormRoute(
            mode: .change(habit),
            initialFocus: focus,
            prefill: nil
        )
    }

    private func openTradeModal(for habit: Habit, offer: SpecialOffer?) {
        tradingHabitRoute = HabitTradeRoute(
            habit: habit,
            resolvedSpecialOffer: offer
        )
    }

    private func queueScrollToHabitIfVisible(_ habitID: RecordID) {
        EntityListViewCoordinator.queueScrollToVisibleItem(
            habitID,
            visibleIDs: visibleHabits(offerSnapshot: specialOfferStore.makeSnapshot()).map(\.id),
            highlightedID: &highlightedHabitID,
            pendingScrollTargetID: &pendingScrollTargetID
        )
    }

    private func scheduleNewHabitHighlightFade(for habitID: RecordID) {
        EntityListViewCoordinator.scheduleHighlightFade(
            for: habitID,
            highlightedID: { highlightedHabitID },
            setHighlightedID: { highlightedHabitID = $0 }
        )
    }

    @MainActor
    private func openPendingHabitFormIfNeeded() {
        EntityListViewCoordinator.openPendingFormIfNeeded(
            expectedTab: .habits,
            selectedTab: appNavigationStore.selectedTab,
            request: appNavigationStore.pendingEntityFormRequest,
            extractID: { route in
                guard case .habit(let habitID) = route else { return nil }
                return habitID
            },
            resolveEntity: { habitID in
                habitStore.habits.first(where: { $0.id == habitID && $0.deletedAt == nil })
            },
            isPresentingForm: formRoute != nil,
            open: { habit in
                openChangeForm(habit, focus: nil)
            },
            clearRequest: { requestID in
                appNavigationStore.clearPendingEntityFormRequest(id: requestID)
            }
        )
    }

    private func schedulePendingHabitFormOpenIfNeeded() {
        EntityListViewCoordinator.schedulePendingFormOpen(openPendingHabitFormIfNeeded)
    }
}

#Preview {
    HabitsView()
        .environment(HabitStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
        .environment(ReminderStore(
            taskStore: TaskStore(),
            habitStore: HabitStore(),
            notificationScheduler: NoOpReminderNotificationScheduler()
        ))
        .environment(AppNavigationStore())
        .environment(ListPreferencesStore())
}
