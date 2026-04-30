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
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: RewardFormRoute? = nil
    @State private var purchasingReward: Reward? = nil
    @State private var rewardToDelete: Reward? = nil
    @State private var toastManager = ToastManager()
    @State private var pendingScrollTargetID: RecordID? = nil
    @State private var highlightedRewardID: RecordID? = nil

    private var visibleRewards: [Reward] {
        EntityListQuery.apply(
            items: rewardStore.activeRewards,
            preferences: listPreferencesStore.rewardPreferences,
            validTagIDs: tagStore.activeTagIDs,
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.damageTier?.sortOrder },
            price: priceSortValue(for:),
            tags: { tagStore.tagsForReward(rewardId: $0.id) }
        )
    }

    var body: some View {
        NavigationStack {
            EntityListScreen(
                hasAnyItems: !rewardStore.activeRewards.isEmpty,
                visibleItemCount: visibleRewards.count,
                emptyTitle: "No Rewards Yet",
                emptySystemImage: "gift",
                emptyDescription: "Tap + to create your first reward.",
                filteredEmptyTitle: "No Matching Rewards",
                filteredEmptyDescription: "Try changing the selected tags or clear them to see more rewards.",
                preferences: listPreferencesStore.rewardPreferences,
                tagScope: .rewards,
                rowIDs: visibleRewards.map(\.id),
                pendingScrollTargetID: $pendingScrollTargetID,
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
                        isHighlighted: highlightedRewardID == reward.id
                    ) {
                        rewardRow(reward)
                    }
                        .id(reward.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                // Behaviour: Swiping a row should only open the
                                // confirmation alert. Using a `.destructive` swipe button
                                // makes SwiftUI preview the removal before the user confirms,
                                // which causes the row to flicker out and then back in.
                                rewardToDelete = reward
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
            .navigationTitle("Rewards")
            .overlay(alignment: .bottomTrailing) {
                EntityFloatingAddButton {
                    formRoute = RewardFormRoute(mode: .new, initialFocus: nil, prefill: nil)
                }
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
                        rewardToDelete = reward
                    }
                )
            }
            .sheet(item: $purchasingReward) { reward in
                RewardPurchaseModalView(reward: reward)
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
                        rewardStore.deleteReward(id: reward.id)
                    }
                    rewardToDelete = nil
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

    private func showDiscardToast(snapshot: RewardFormSnapshot) {
        toastManager.show(
            message: "Reward Discarded",
            actionLabel: "Recover"
        ) {
            formRoute = RewardFormRoute(
                mode: .new,
                initialFocus: nil,
                prefill: snapshot
            )
        }
    }

    private func priceForReward(_ reward: Reward) -> Int {
        let purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
        return RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            purchaseDates: purchaseDates,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
    }

    private func priceSortValue(for reward: Reward) -> Int? {
        EntityActionSupport.sortableAmount(isActionable: reward.canPurchase) {
            priceForReward(reward)
        }
    }

    private func rewardRow(_ reward: Reward) -> some View {
        let tags = tagStore.tagsForReward(rewardId: reward.id)
        let canPurchase = reward.canPurchase
        let price = priceForReward(reward)
        let canAfford = canPurchase && balanceStore.balance >= price

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
                }

                if !tags.isEmpty {
                    TagPillsRow(tags: tags)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                openChangeForm(reward, focus: nil)
            }

            if canPurchase {
                TofuActionButton(amount: price, polarity: .spending, layout: .compact) {
                    if canAfford {
                        purchasingReward = reward
                    }
                }
                .disabled(!canAfford)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openChangeForm(_ reward: Reward, focus: RewardFormFocus?) {
        formRoute = RewardFormRoute(
            mode: .change(reward),
            initialFocus: focus,
            prefill: nil
        )
    }

    private func queueScrollToRewardIfVisible(_ rewardID: RecordID) {
        guard visibleRewards.contains(where: { $0.id == rewardID }) else { return }
        highlightedRewardID = rewardID
        pendingScrollTargetID = rewardID
    }

    private func scheduleNewRewardHighlightFade(for rewardID: RecordID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard highlightedRewardID == rewardID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                highlightedRewardID = nil
            }
        }
    }

    @MainActor
    private func openPendingRewardFormIfNeeded() {
        guard appNavigationStore.selectedTab == .rewards else { return }
        guard let request = appNavigationStore.pendingEntityFormRequest else { return }
        guard case .reward(let rewardID) = request.route else { return }
        guard let reward = rewardStore.rewards.first(where: { $0.id == rewardID && $0.deletedAt == nil }) else { return }
        guard formRoute == nil else { return }
        openChangeForm(reward, focus: nil)
        appNavigationStore.clearPendingEntityFormRequest(id: request.id)
    }

    private func schedulePendingRewardFormOpenIfNeeded() {
        DispatchQueue.main.async {
            self.openPendingRewardFormIfNeeded()
        }
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
