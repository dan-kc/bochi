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
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var formRoute: RewardFormRoute? = nil
    @State private var purchasingReward: Reward? = nil
    @State private var rewardToDelete: Reward? = nil
    @State private var toastManager = ToastManager()

    private var visibleRewards: [Reward] {
        EntityListQuery.apply(
            items: rewardStore.activeRewards,
            preferences: listPreferencesStore.rewardPreferences,
            validTagIDs: tagStore.listFilterTagIDs(for: .rewards),
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.damageTier?.sortOrder },
            price: priceSortValue(for:),
            hasDifficulty: { $0.damageTier != nil },
            hasFrequency: { $0.maxFrequency != nil },
            tags: { tagStore.tagsForReward(rewardId: $0.id) }
        )
    }

    private var availableRewardTags: [Tag] {
        tagStore.listFilterTags(for: .rewards)
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
                filteredEmptyDescription: "Try changing the filters or clear them to see more rewards.",
                preferences: listPreferencesStore.rewardPreferences,
                availableTags: availableRewardTags,
                difficultyLabel: "Difficulty",
                frequencyLabel: "Freq",
                onSelectSort: listPreferencesStore.setRewardSort,
                onSelectDifficultyFilter: listPreferencesStore.setRewardDifficultyFilter,
                onSelectFrequencyFilter: listPreferencesStore.setRewardFrequencyFilter,
                onSelectTagMatchMode: listPreferencesStore.setRewardTagMatchMode,
                onToggleTag: listPreferencesStore.toggleRewardTag,
                onClearFilters: listPreferencesStore.clearRewardFilters
            ) {
                ForEach(visibleRewards) { reward in
                    rewardRow(reward)
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
        EntityActionSupport.visibleAmount(isActionable: reward.canPurchase) {
            let purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
            return RewardPriceCalculation.calculatePrice(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                purchaseDates: purchaseDates,
                generalDifficulty: userSettingsStore.generalDifficulty
            )
        }
    }

    private func priceSortValue(for reward: Reward) -> Int? {
        EntityActionSupport.sortableAmount(isActionable: reward.canPurchase) {
            priceForReward(reward)
        }
    }

    private func rewardRow(_ reward: Reward) -> some View {
        let tags = tagStore.tagsForReward(rewardId: reward.id)
        let canPurchase = reward.canPurchase
        let price = EntityActionSupport.visibleAmount(isActionable: canPurchase) {
            priceForReward(reward)
        }
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
                        isSet: reward.maxFrequency != nil,
                        animating: reward.maxFrequency == nil
                    )

                    EntityListMetaPill(
                        text: reward.damageTier?.displayName ?? "Damage",
                        isSet: reward.damageTier != nil,
                        animating: reward.damageTier == nil
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
}

#Preview {
    RewardsView()
        .environment(BalanceStore())
        .environment(RewardStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(UserSettingsStore())
        .environment(ListPreferencesStore())
}
