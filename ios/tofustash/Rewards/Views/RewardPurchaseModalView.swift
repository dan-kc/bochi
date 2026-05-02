import SwiftUI

// Confirmation flow for spending tofu on one reward. The user sees the current
// price, whether they can afford it, and a small celebration after purchase.
struct RewardPurchaseModalView: View {
    let reward: Reward
    var onPurchase: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(RewardStore.self) private var rewardStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(SpecialOfferStore.self) private var specialOfferStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    static let maxQuantity = 99
    @State private var quantity = 1
    @State private var purchased = false
    @State private var spentAmount = 0
    @State private var purchaseErrorMessage: String? = nil

    private var purchaseDates: [Date] {
        tradeStore.rewardPurchaseDates(rewardId: reward.id)
    }

    private var totalPrice: Int {
        RewardPriceCalculation.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            purchaseDates: purchaseDates,
            quantity: quantity,
            generalDifficulty: userSettingsStore.generalDifficulty,
            specialOfferModifierPercent: specialOffer?.modifierPercent
        )
    }

    private var specialOffer: SpecialOffer? {
        specialOfferStore.activeOffer(for: .reward, entityID: reward.id)
    }

    private var canAfford: Bool {
        balanceStore.balance >= totalPrice
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if purchased {
                    RewardPurchaseCelebrationView(amount: spentAmount) {
                        dismiss()
                        onPurchase?()
                    }
                    .transition(.opacity)
                } else {
                    formContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: purchased)
            .navigationTitle(purchased ? "" : "Buy Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !purchased {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert("Cannot Purchase", isPresented: Binding(
            get: { purchaseErrorMessage != nil },
            set: { if !$0 { purchaseErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                purchaseErrorMessage = nil
            }
        } message: {
            Text(purchaseErrorMessage ?? "")
        }
    }

    private var formContent: some View {
        VStack(spacing: 24) {
            // Behaviour: the sheet now leads with the current total cost so
            // the user sees the spend decision before any supporting copy.
            VStack(spacing: 4) {
                Text("Total Cost")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("\(totalPrice)")
                        .font(.title)
                        .fontWeight(.bold)
                        .contentTransition(.numericText())
                    Image(systemName: "cube.fill")
                }
                .foregroundStyle(canAfford ? Color.primary : Color.red)

                if let specialOffer {
                    Text(SpecialOfferSupport.badgeText(modifierPercent: specialOffer.modifierPercent))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 8)

            if !reward.description.isEmpty {
                Text(reward.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            HStack(spacing: 24) {
                Button {
                    if quantity > 1 { quantity -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(quantity > 1 ? Color.blue : Color.gray)
                }
                .disabled(quantity <= 1)

                Text("\(quantity)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: quantity)
                    .frame(minWidth: 80)

                Button {
                    if quantity < Self.maxQuantity { quantity += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(quantity < Self.maxQuantity ? Color.blue : Color.gray)
                }
                .disabled(quantity >= Self.maxQuantity)
            }

            Spacer()

            // Behaviour: the buy action sits directly under the total so the
            // user confirms cost and purchase in one focused area of the sheet.
            TofuActionButton(amount: totalPrice, polarity: .spending, layout: .expanded(title: "Buy")) {
                purchaseReward()
            }
            .disabled(!canAfford)

            if !canAfford {
                Text("You need \(totalPrice - balanceStore.balance) more tofu to buy this reward.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func purchaseReward() {
        do {
            spentAmount = try RewardPurchaseService.purchase(
                reward: reward,
                rewardStore: rewardStore,
                tradeStore: tradeStore,
                balanceStore: balanceStore,
                generalDifficulty: userSettingsStore.generalDifficulty,
                specialOfferModifierPercent: specialOffer?.modifierPercent,
                quantity: quantity
            )
            purchased = true
        } catch let error as RewardPurchaseError {
            purchaseErrorMessage = error.message
        } catch {
            purchaseErrorMessage = "Unable to complete this purchase right now."
        }
    }
}

private struct RewardPurchaseCelebrationView: View {
    let amount: Int
    let onComplete: () -> Void

    @State private var showAnimation = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("-\(amount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Image(systemName: "cube.fill")
                    .font(.title)
            }
            .foregroundStyle(.orange)
            .scaleEffect(showAnimation ? 1.0 : 0.0)
            .animation(.spring(duration: 0.4, bounce: 0.5), value: showAnimation)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            showAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                onComplete()
            }
        }
    }
}
