import SwiftUI

// Confirmation flow for spending points on one reward. The user sees the current
// price, whether they can afford it, and a small celebration after purchase.
struct RewardPurchaseModalView: View {
    @Environment(\.bochiTheme) private var theme
    let reward: Reward
    let quote: RewardPurchaseQuote?
    var onPurchase: (() -> Void)?
    var allowsRestrictedPurchase: Bool

    init(
        reward: Reward,
        quote: RewardPurchaseQuote? = nil,
        onPurchase: (() -> Void)? = nil,
        allowsRestrictedPurchase: Bool = false
    ) {
        self.reward = reward
        self.quote = quote
        self.onPurchase = onPurchase
        self.allowsRestrictedPurchase = allowsRestrictedPurchase
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(RewardStore.self) private var rewardStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    static let maxQuantity = 99
    @State private var quantity = 1
    @State private var purchased = false
    @State private var spentAmount = 0
    @State private var purchaseErrorMessage: String? = nil
    @State private var oneTimeAdjustmentMultiplier: Double? = nil
    @State private var oneTimeAdjustedPrice: Int? = nil
    @State private var showingAdjustment = false
    @State private var showingVaultPurchase = false
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil

    private var purchaseDates: [Date] {
        tradeStore.rewardPurchaseDates(rewardId: reward.id)
    }

    private var totalPrice: Int {
        if hasPremiumAccess, let oneTimeAdjustedPrice {
            return oneTimeAdjustedPrice
        }
        return adjustedTotalPrice(oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier)
    }

    private var unadjustedTotalPrice: Int { adjustedTotalPrice(oneTimeAdjustmentMultiplier: nil) }

    private var adjustmentCaptions: [String] {
        var captions: [String] = []
        if hasPremiumAccess, oneTimeAdjustedPrice != nil || oneTimeAdjustmentMultiplier != nil {
            captions.append("One-time adjustment")
        }
        return captions
    }

    private func adjustedTotalPrice(
        oneTimeAdjustmentMultiplier: Double?
    ) -> Int {
        if let quote {
            return quote.totalPrice(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                quantity: locksQuantity ? 1 : quantity,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                hasPremiumAccess: hasPremiumAccess
            )
        }

        return RewardPriceCalculator.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            purchaseDates: purchaseDates,
            quantity: locksQuantity ? 1 : quantity,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    private var canAfford: Bool {
        balanceStore.balance >= totalPrice
    }

    private var hasDependencies: Bool {
        rewardDependencyStore.hasDependencies(for: reward.id)
    }

    private var locksQuantityToDependencies: Bool {
        hasPremiumAccess && hasDependencies
    }

    private var locksQuantity: Bool {
        locksQuantityToDependencies || !reward.recurring
    }

    private var isLocked: Bool {
        guard !allowsRestrictedPurchase else { return false }
        return RewardLockout.isLocked(reward: reward, tradeStore: tradeStore, hasPremiumAccess: hasPremiumAccess)
            || rewardDependencyStore.isRewardBlocked(
                reward,
                taskStore: taskStore,
                tradeStore: tradeStore,
                hasPremiumAccess: hasPremiumAccess
            )
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    private var lockoutSummary: String? {
        guard let remainingSeconds = RewardLockout.remainingSeconds(
            reward: reward,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            return nil
        }
        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
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
            .background(theme.appBackground())
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
        .claimSheetPresentation(theme: theme)
        .sheet(isPresented: $showingAdjustment) {
            PriceAdjustmentModalView(
                title: "One-time Adjustment",
                basePrice: unadjustedTotalPrice,
                adjustedPrice: totalPrice,
                multiplier: $oneTimeAdjustmentMultiplier,
                adjustedPriceOverride: $oneTimeAdjustedPrice
            )
        }
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
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
        ClaimSheetFloatingActionShell(
            bottomSpacerHeight: rewardFloatingControlHeight,
            contentStyle: claimSheetContentStyle
        ) {
            VStack(spacing: claimSheetContentStyle.sectionSpacing) {
                VStack(spacing: 8) {
                    TradeAmountSummaryView(
                        amount: totalPrice,
                        polarity: .spending,
                        amountColor: theme.accentSolidFill(for: .reward),
                        titleColor: theme.highContrastText(for: .reward),
                        originalAmount: adjustmentCaptions.isEmpty ? nil : unadjustedTotalPrice,
                        adjustmentCaptions: adjustmentCaptions
                    )

                    adjustmentButton
                }

                if !locksQuantity {
                    VStack(spacing: 8) {
                        Text("Quantity")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.lowContrastText(for: .reward))

                        HStack(spacing: 24) {
                            Button {
                                if quantity > 1 { quantity -= 1 }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(quantity > 1 ? theme.solidFill(for: .reward) : theme.lowContrastText(for: .reward))
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
                                    .foregroundStyle(quantity < Self.maxQuantity ? theme.solidFill(for: .reward) : theme.lowContrastText(for: .reward))
                            }
                            .disabled(quantity >= Self.maxQuantity)
                        }
                        .padding(.vertical, 15)
                    }
                }

                if !isLocked {
                    Button("Pay with bank balance") {
                        showingVaultPurchase = true
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }
            }
        } floatingControls: {
            if isLocked {
                lockedStatusPill
            } else {
                VStack(spacing: 10) {
                    // Behaviour: the buy action floats above the sheet body like
                    // entity form actions, so it stays reachable when expanded.
                    BochiActionButton(
                        amount: totalPrice,
                        polarity: .spending,
                        layout: .expanded(title: "Buy"),
                        isEnabled: canAfford,
                        themeRoleOverride: .reward,
                        priceDeltaPercent: PriceDeltaSupport.percent(
                            currentPrice: totalPrice,
                            basePrice: reward.basePrice * quantity
                        )
                    ) {
                        purchaseReward()
                    }

                    if !canAfford {
                        Text("You need \(totalPrice - balanceStore.balance) more points to buy this reward.")
                            .font(.footnote)
                            .foregroundStyle(theme.lowContrastText(for: .reward))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .sheet(isPresented: $showingVaultPurchase) {
            VaultRewardPurchaseModalView(
                reward: reward,
                quote: quote,
                quantity: locksQuantity ? 1 : quantity,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                oneTimeAdjustedPrice: oneTimeAdjustedPrice,
                onPurchase: {
                    showingVaultPurchase = false
                    dismiss()
                    onPurchase?()
                }
            )
        }
    }

    private var claimSheetContentStyle: ClaimSheetContentStyle {
        locksQuantity ? .standard : .quantityPicker
    }

    private var rewardFloatingControlHeight: CGFloat {
        if isLocked { return 94 }
        return canAfford ? 94 : 132
    }

    private var lockedStatusPill: some View {
        HStack {
            Label("Locked", systemImage: "lock.fill")
            Spacer()
            if let lockoutSummary {
                Text(lockoutSummary)
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(theme.lowContrastText(for: .reward))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.componentBackground(for: .reward), in: Capsule())
    }

    @ViewBuilder
    private var adjustmentButton: some View {
        Group {
            if hasPremiumAccess {
                Button {
                    openAdjustmentOrUpsell()
                } label: {
                    Label("Adjust", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    openAdjustmentOrUpsell()
                } label: {
                    Label("Adjust", systemImage: "crown.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.premiumFill())
            }
        }
        .controlSize(.regular)
    }

    private func purchaseReward() {
        if !allowsRestrictedPurchase {
            guard !RewardLockout.isLocked(
                reward: reward,
                tradeStore: tradeStore,
                hasPremiumAccess: hasPremiumAccess
            ) else { return }
        }
        do {
            try withAnimation(.default) {
                spentAmount = try RewardPurchaseService.purchase(
                    reward: reward,
                    rewardStore: rewardStore,
                    rewardDependencyStore: rewardDependencyStore,
                    taskStore: taskStore,
                    tradeStore: tradeStore,
                    balanceStore: balanceStore,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    oneTimeAdjustedTotal: oneTimeAdjustedPrice,
                    quote: quote,
                    quantity: quantity,
                    hasPremiumAccess: hasPremiumAccess,
                    allowsRestrictedPurchase: allowsRestrictedPurchase
                )
            }
            purchased = true
        } catch let error as RewardPurchaseError {
            purchaseErrorMessage = error.message
        } catch {
            purchaseErrorMessage = "Unable to complete this purchase right now."
        }
    }

    private func openAdjustmentOrUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .adjustments
            return
        }
        showingAdjustment = true
    }
}

private struct RewardPurchaseCelebrationView: View {
    @Environment(\.bochiTheme) private var theme
    let amount: Int
    let onComplete: () -> Void

    @State private var showAnimation = false

    var body: some View {
        VStack(spacing: 12) {
            PointsAmountLabel(text: "-\(amount)", iconSize: 32)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(theme.solidFill(for: .reward))
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

private struct VaultRewardPurchaseModalView: View {
    @Environment(\.bochiTheme) private var theme
    let reward: Reward
    let quote: RewardPurchaseQuote?
    let quantity: Int
    let oneTimeAdjustmentMultiplier: Double?
    let oneTimeAdjustedPrice: Int?
    let onPurchase: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(RewardStore.self) private var rewardStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @State private var purchased = false
    @State private var spentAmount = 0
    @State private var purchaseErrorMessage: String?

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    private var totalPrice: Int {
        if hasPremiumAccess, let oneTimeAdjustedPrice {
            return oneTimeAdjustedPrice
        }
        if let quote {
            return quote.totalPrice(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                quantity: quantity,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                hasPremiumAccess: hasPremiumAccess
            )
        }

        return RewardPriceCalculator.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            purchaseDates: tradeStore.rewardPurchaseDates(rewardId: reward.id),
            quantity: quantity,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    private var vaultBalanceMicro: Int {
        tradeStore.vaultBalanceMicro()
    }

    private var requiredVaultBalanceMicro: Int {
        VaultAmount.microUnits(forWholeBochi: totalPrice)
    }

    private var cooldownText: String? {
        guard let remaining = VaultRewardPurchaseService.remainingVaultCooldown(tradeStore: tradeStore) else {
            return nil
        }
        return DurationFormatting.countdown(secondsRemaining: remaining)
    }

    private var actionTitle: String {
        if vaultBalanceMicro < requiredVaultBalanceMicro { return "Insufficient" }
        if cooldownText != nil { return "Locked" }
        return "Pay"
    }

    private var canClaim: Bool {
        vaultBalanceMicro >= requiredVaultBalanceMicro && cooldownText == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if purchased {
                    RewardPurchaseCelebrationView(amount: spentAmount) {
                        // Behaviour: the parent purchase sheet owns the whole
                        // bank payment flow, so success closes both sheets
                        // together instead of briefly revealing the original sheet.
                        onPurchase()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.appBackground())
                } else {
                    vaultContent
                }
            }
            .navigationTitle("Pay With Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !purchased {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .claimSheetPresentation(theme: theme)
        .alert("Cannot Pay", isPresented: Binding(
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

    private var vaultContent: some View {
        ClaimSheetFloatingActionShell {
            VStack(spacing: 20) {
                TradeAmountSummaryView(
                    amount: totalPrice,
                    polarity: .spending,
                    amountColor: theme.accentSolidFill(for: .reward),
                    titleColor: theme.highContrastText(for: .reward)
                )

                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        PointsAmountLabel(text: VaultAmount.formatted(vaultBalanceMicro))
                        Text("in bank")
                    }
                    Text("You can only purchase from the bank once every 30 days.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText())
                        .multilineTextAlignment(.center)
                    if let cooldownText {
                        Text("Next bank purchase in \(cooldownText).")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.warningText())
                    }
                }
            }
        } floatingControls: {
            BochiActionButton(
                amount: totalPrice,
                polarity: .spending,
                layout: .expanded(title: actionTitle),
                isEnabled: canClaim,
                themeRoleOverride: .reward
            ) {
                claim()
            }
        }
    }

    private func claim() {
        do {
            spentAmount = try VaultRewardPurchaseService.purchase(
                reward: reward,
                rewardStore: rewardStore,
                rewardDependencyStore: rewardDependencyStore,
                taskStore: taskStore,
                tradeStore: tradeStore,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                oneTimeAdjustedTotal: oneTimeAdjustedPrice,
                quote: quote,
                quantity: quantity,
                hasPremiumAccess: hasPremiumAccess
            )
            purchased = true
        } catch let error as VaultRewardPurchaseError {
            purchaseErrorMessage = error.message
        } catch {
            purchaseErrorMessage = "Unable to complete this bank payment right now."
        }
    }
}
