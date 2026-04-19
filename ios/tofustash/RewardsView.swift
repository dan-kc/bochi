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
    @State private var isListAtTop = true

    private var visibleRewards: [Reward] {
        EntityListQuery.apply(
            items: rewardStore.activeRewards,
            preferences: listPreferencesStore.rewardPreferences,
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
        let usedTagIDs = Set(
            tagStore.rewardTags
                .filter { $0.deletedAt == nil }
                .map(\.tagId)
        )

        return tagStore.activeTags.filter { usedTagIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rewardStore.activeRewards.isEmpty {
                    ContentUnavailableView(
                        "No Rewards Yet",
                        systemImage: "gift",
                        description: Text("Tap + to create your first reward.")
                    )
                } else {
                    List {
                        controlsRow

                        Section {
                            if visibleRewards.isEmpty {
                                filteredEmptyStateRow
                            } else {
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
                        }
                    }
                    .lockControlsUnlessScrolledToTop(isAtTop: $isListAtTop)
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(0)
                    .contentMargins(.top, 0, for: .scrollContent)
                }
            }
            .navigationTitle("Rewards")
            .onChange(of: visibleRewards.isEmpty) { _, isEmpty in
                if isEmpty {
                    isListAtTop = true
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    formRoute = RewardFormRoute(mode: .new, initialFocus: nil, prefill: nil)
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
        guard reward.canPurchase else { return 0 }
        let purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
        return RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            purchaseDates: purchaseDates,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
    }

    private func priceSortValue(for reward: Reward) -> Int? {
        guard reward.canPurchase else { return nil }
        return priceForReward(reward)
    }

    private var controlsRow: some View {
        EntityListControls(
            preferences: listPreferencesStore.rewardPreferences,
            availableTags: availableRewardTags,
            difficultyLabel: "Difficulty",
            frequencyLabel: "Freq",
            isEnabled: isListAtTop,
            onSelectSort: listPreferencesStore.setRewardSort,
            onSelectDifficultyFilter: listPreferencesStore.setRewardDifficultyFilter,
            onSelectFrequencyFilter: listPreferencesStore.setRewardFrequencyFilter,
            onSelectTagMatchMode: listPreferencesStore.setRewardTagMatchMode,
            onToggleTag: listPreferencesStore.toggleRewardTag,
            onClearFilters: listPreferencesStore.clearRewardFilters
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.top, -12)
        .padding(.bottom, -6)
    }

    private var filteredEmptyStateRow: some View {
        ContentUnavailableView {
            Label("No Matching Rewards", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try changing the filters or clear them to see more rewards.")
        } actions: {
            Button("Clear Filters") {
                listPreferencesStore.clearRewardFilters()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func rewardRow(_ reward: Reward) -> some View {
        let tags = tagStore.tagsForReward(rewardId: reward.id)
        let canPurchase = reward.canPurchase
        let price = canPurchase ? priceForReward(reward) : 0
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
