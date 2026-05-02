import SwiftUI

private struct RewardFormRoute: Identifiable {
    let id = UUID()
    let mode: RewardFormMode
    let initialFocus: RewardFormFocus?
    let prefill: RewardFormSnapshot?
}

struct RewardsView: View {
    @Environment(RewardStore.self) private var rewardStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(SpecialOfferStore.self) private var specialOfferStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: RewardFormRoute? = nil
    @State private var purchasingRewardRoute: RewardPurchaseRoute? = nil
    @State private var historyReward: Reward? = nil
    @State private var rewardToDelete: Reward? = nil
    @State private var toastManager = ToastManager()
    @State private var pendingScrollTargetID: RecordID? = nil
    @State private var highlightedRewardID: RecordID? = nil
    @Namespace private var searchChromeNamespace
    @State private var searchState = EntityListSearchState()

    private var filterState: EntityListFilterState {
        EntityListFilterState(
            preferences: listPreferencesStore.rewardPreferences,
            search: searchState
        )
    }

    private func visibleRewards(offerSnapshot: SpecialOfferSnapshot) -> [Reward] {
        EntityListQuery.apply(
            items: rewardStore.activeRewards,
            filterState: filterState,
            validTagIDs: tagStore.activeTagIDs,
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.damageTier?.sortOrder },
            price: { priceSortValue(for: $0, offerSnapshot: offerSnapshot) },
            tags: { tagStore.tagsForReward(rewardId: $0.id) }
        )
    }

    var body: some View {
        let offerSnapshot = specialOfferStore.makeSnapshot()
        let visibleRewards = visibleRewards(offerSnapshot: offerSnapshot)

        NavigationStack {
            EntityListScreen(
                hasAnyItems: !rewardStore.activeRewards.isEmpty,
                visibleItemCount: visibleRewards.count,
                emptyTitle: "No Rewards Yet",
                emptySystemImage: "gift",
                emptyDescription: "Tap + to create your first reward.",
                filteredEmptyTitle: "No Matching Rewards",
                filteredEmptyDescription: "Try changing the search text or selected tags to see more rewards.",
                searchPrompt: "Search rewards",
                searchChromeNamespace: searchChromeNamespace,
                filterState: filterState,
                tagScope: .rewards,
                rowIDs: visibleRewards.map(\.id),
                searchState: $searchState,
                pendingScrollTargetID: $pendingScrollTargetID,
                onAdd: openNewRewardForm,
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setRewardSort(option)
                    }
                },
                onClearFilters: listPreferencesStore.clearRewardFilters,
                onPendingScrollCompleted: { rewardID in
                    scheduleNewRewardHighlightFade(for: rewardID)
                }
            ) {
                ForEach(Array(visibleRewards.enumerated()), id: \.element.id) { index, reward in
                    EntityListRowSurface(
                        showsDivider: index < visibleRewards.count - 1,
                        isHighlighted: highlightedRewardID == reward.id,
                        isSpecialOffer: offerSnapshot.hasActiveOffer(for: .reward, entityID: reward.id)
                    ) {
                        rewardRow(reward, offerSnapshot: offerSnapshot)
                    }
                        .id(reward.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                // Behaviour: Swiping a row should only open the
                                // confirmation alert. Using a `.destructive` swipe button
                                // makes SwiftUI preview the removal before the user confirms,
                                // which causes the row to flicker out and then back in.
                                confirmDelete(reward)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .contextMenu {
                            rewardRowMenu(reward, offerSnapshot: offerSnapshot)
                        }
                }
            }
            .navigationTitle("Rewards")
            .overlay(alignment: .bottomTrailing) {
                EntityListFloatingActionOverlay(
                    showsSearchButton: !rewardStore.activeRewards.isEmpty,
                    namespace: searchChromeNamespace,
                    searchState: $searchState,
                    onAdd: openNewRewardForm
                )
            }
            .sheet(item: $formRoute) { route in
                RewardFormView(
                    mode: route.mode,
                    initialFocus: route.initialFocus,
                    prefill: route.prefill,
                    onCreated: { reward in
                        queueScrollToRewardIfVisible(reward.id)
                    },
                    onDiscard: route.mode.isNew ? { snapshot in
                        showDiscardToast(snapshot: snapshot)
                    } : nil,
                    onDelete: { reward in
                        deleteReward(reward)
                    }
                )
            }
            .sheet(item: $purchasingRewardRoute) { route in
                RewardPurchaseModalView(
                    reward: route.reward,
                    resolvedSpecialOffer: route.resolvedSpecialOffer
                )
            }
            .sheet(item: $historyReward) { reward in
                TradeHistorySheetView(
                    filter: .reward(reward.id),
                    detents: [.large]
                )
            }
            .alert(
                "Delete Reward?",
                isPresented: Binding(
                    get: { rewardToDelete != nil },
                    set: { if !$0 { rewardToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let reward = rewardToDelete {
                        deleteReward(reward)
                    }
                }
                Button("Cancel", role: .cancel) {
                    rewardToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .overlay {
                ToastOverlay(toastManager: toastManager)
            }
            .onAppear {
                schedulePendingRewardFormOpenIfNeeded()
            }
            .onChange(of: appNavigationStore.pendingEntityFormRequest) { _, _ in
                schedulePendingRewardFormOpenIfNeeded()
            }
            .onChange(of: appNavigationStore.selectedTab) { _, selectedTab in
                guard selectedTab == .rewards else { return }
                schedulePendingRewardFormOpenIfNeeded()
            }
        }
    }

    private func openNewRewardForm() {
        formRoute = RewardFormRoute(mode: .new, initialFocus: nil, prefill: nil)
    }

    private func confirmDelete(_ reward: Reward) {
        rewardToDelete = reward
    }

    private func deleteReward(_ reward: Reward) {
        rewardStore.deleteReward(id: reward.id)
        rewardToDelete = nil
    }

    private func showDiscardToast(snapshot: RewardFormSnapshot) {
        EntityListViewCoordinator.showDiscardToast(
            toastManager: toastManager,
            entityName: "Reward",
            snapshot: snapshot,
            makeRoute: {
                RewardFormRoute(mode: .new, initialFocus: nil, prefill: $0)
            },
            setRoute: { formRoute = $0 }
        )
    }

    private func priceForReward(_ reward: Reward, offerSnapshot: SpecialOfferSnapshot) -> Int {
        let purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
        return RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            purchaseDates: purchaseDates,
            generalDifficulty: userSettingsStore.generalDifficulty,
            specialOfferModifierPercent: offerSnapshot.activeModifierPercent(for: .reward, entityID: reward.id)
        )
    }

    private func priceSortValue(for reward: Reward, offerSnapshot: SpecialOfferSnapshot) -> Int? {
        EntityActionSupport.sortableAmount(isActionable: reward.canPurchase) {
            priceForReward(reward, offerSnapshot: offerSnapshot)
        }
    }

    private func rewardRow(_ reward: Reward, offerSnapshot: SpecialOfferSnapshot) -> some View {
        let tags = tagStore.tagsForReward(rewardId: reward.id)
        let canPurchase = reward.canPurchase
        let price = priceForReward(reward, offerSnapshot: offerSnapshot)
        let canAfford = canPurchase && balanceStore.balance >= price
        let offer = offerSnapshot.activeOffer(for: .reward, entityID: reward.id)

        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(reward.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !reward.description.isEmpty {
                    Text(reward.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    EntityListMetaPill(
                        text: FrequencyConversion.formatSummary(reward.maxFrequency).map { "Max \($0)" } ?? "Max Frequency",
                        isSet: reward.maxFrequency != nil
                    )

                    EntityListMetaPill(
                        text: reward.damageTier?.displayName ?? "Damage",
                        isSet: reward.damageTier != nil
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

            if canPurchase {
                TofuActionButton(
                    amount: price,
                    polarity: .spending,
                    layout: .compact,
                    isEnabled: canAfford
                ) {
                    if canAfford {
                        openPurchaseModal(for: reward, offer: offer)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            openChangeForm(reward, focus: nil)
        }
    }

    @ViewBuilder
    private func rewardRowMenu(_ reward: Reward, offerSnapshot: SpecialOfferSnapshot) -> some View {
        let price = priceForReward(reward, offerSnapshot: offerSnapshot)
        let canClaimReward = reward.canPurchase && balanceStore.balance >= price

        if canClaimReward {
            let offer = offerSnapshot.activeOffer(for: .reward, entityID: reward.id)
            Button {
                openPurchaseModal(for: reward, offer: offer)
            } label: {
                Label("Claim Reward", systemImage: "gift")
            }
        }

        EntityRowContextMenuActions.editHistoryDelete(
            onEdit: {
                openChangeForm(reward, focus: nil)
            },
            onViewHistory: {
                historyReward = reward
            },
            onDelete: {
                confirmDelete(reward)
            }
        )
    }

    private func openChangeForm(_ reward: Reward, focus: RewardFormFocus?) {
        formRoute = RewardFormRoute(
            mode: .change(reward),
            initialFocus: focus,
            prefill: nil
        )
    }

    private func openPurchaseModal(for reward: Reward, offer: SpecialOffer?) {
        purchasingRewardRoute = RewardPurchaseRoute(
            reward: reward,
            resolvedSpecialOffer: offer
        )
    }

    private func queueScrollToRewardIfVisible(_ rewardID: RecordID) {
        EntityListViewCoordinator.queueScrollToVisibleItem(
            rewardID,
            visibleIDs: visibleRewards(offerSnapshot: specialOfferStore.makeSnapshot()).map(\.id),
            highlightedID: &highlightedRewardID,
            pendingScrollTargetID: &pendingScrollTargetID
        )
    }

    private func scheduleNewRewardHighlightFade(for rewardID: RecordID) {
        EntityListViewCoordinator.scheduleHighlightFade(
            for: rewardID,
            highlightedID: { highlightedRewardID },
            setHighlightedID: { highlightedRewardID = $0 }
        )
    }

    @MainActor
    private func openPendingRewardFormIfNeeded() {
        EntityListViewCoordinator.openPendingFormIfNeeded(
            expectedTab: .rewards,
            selectedTab: appNavigationStore.selectedTab,
            request: appNavigationStore.pendingEntityFormRequest,
            extractID: { route in
                guard case .reward(let rewardID) = route else { return nil }
                return rewardID
            },
            resolveEntity: { rewardID in
                rewardStore.rewards.first(where: { $0.id == rewardID && $0.deletedAt == nil })
            },
            isPresentingForm: formRoute != nil,
            open: { reward in
                openChangeForm(reward, focus: nil)
            },
            clearRequest: { requestID in
                appNavigationStore.clearPendingEntityFormRequest(id: requestID)
            }
        )
    }

    private func schedulePendingRewardFormOpenIfNeeded() {
        EntityListViewCoordinator.schedulePendingFormOpen(openPendingRewardFormIfNeeded)
    }
}

#Preview {
    RewardsView()
        .environment(BalanceStore())
        .environment(RewardStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(UserSettingsStore())
        .environment(AppNavigationStore())
        .environment(ListPreferencesStore())
}
