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

    @State private var formRoute: RewardFormRoute? = nil
    @State private var purchasingReward: Reward? = nil
    @State private var rewardToDelete: Reward? = nil
    @State private var toastManager = ToastManager()

    var body: some View {
        NavigationStack {
            ZStack {
                if rewardStore.activeRewards.isEmpty {
                    ContentUnavailableView(
                        "No Rewards Yet",
                        systemImage: "gift",
                        description: Text("Tap + to create your first reward.")
                    )
                } else {
                    List(rewardStore.activeRewards) { reward in
                        rewardRow(reward)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    rewardToDelete = reward
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Rewards")
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
}
