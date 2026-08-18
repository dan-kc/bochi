import SwiftUI

// Modal for claiming a recurringTask price. Shows a quantity counter, the total
// price, and a primary claim action near that running total.
//
// The quantity counter is the centerpiece — the user can claim a recurringTask multiple
// times in one go (e.g., "I did 20 pushups" when the recurringTask is "Do 10 pushups").
// Each successive claim changes the price because the frequency multiplier
// reacts to the projected completion history, so the total is NOT simply
// price * qty.
//
// After claiming, the UI is replaced with a celebration animation, then the
// modal dismisses.
struct TradeModalView: View {
    @Environment(\.bochiTheme) private var theme
    let recurringTask: RecurringTask
    let quote: RecurringTaskTradeQuote?

    // Called after a successful claim. The parent uses this to chain
    // dismissals (e.g., dismiss the change form too).
    var onClaim: (() -> Void)?
    var allowsRestrictedClaim: Bool

    init(
        recurringTask: RecurringTask,
        quote: RecurringTaskTradeQuote? = nil,
        onClaim: (() -> Void)? = nil,
        allowsRestrictedClaim: Bool = false
    ) {
        self.recurringTask = recurringTask
        self.quote = quote
        self.onClaim = onClaim
        self.allowsRestrictedClaim = allowsRestrictedClaim
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    // How many times the user wants to claim this recurringTask. Starts at 1.
    // Capped at maxQuantity to prevent accidental excessive claims.
    static let maxQuantity = 99
    @State private var quantity = 1

    // Controls whether the celebration view replaces the form content.
    // When true, all form UI is hidden and the celebration is shown.
    @State private var claimed = false
    @State private var claimedAmount = 0
    @State private var oneTimeAdjustmentMultiplier: Double? = nil
    @State private var oneTimeAdjustedPrice: Int? = nil
    @State private var showingAdjustment = false
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil

    // The projected claim total starts from the recurringTask's actual completion
    // timestamps, not from a fixed "last N days" count.
    private var completionDates: [Date] {
        tradeStore.recurringTaskTradeDates(recurringTaskId: recurringTask.id)
    }

    // The total points earned for the selected quantity. NOT price * quantity —
    // each successive completion changes the projected history, so the
    // multiplier is recalculated after every increment.
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
                recurringTask: recurringTask,
                allRecurringTasks: recurringTaskStore.activeRecurringTasks,
                quantity: quantity,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                hasPremiumAccess: hasPremiumAccess
            )
        }

        return RecurringTaskPriceCalculator.calculateMultiClaimTotal(
            recurringTask: recurringTask,
            allRecurringTasks: recurringTaskStore.activeRecurringTasks,
            completionDates: completionDates,
            quantity: quantity,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    private var isLocked: Bool {
        guard !allowsRestrictedClaim else { return false }
        return RecurringTaskLockout.isLocked(recurringTask: recurringTask, tradeStore: tradeStore, hasPremiumAccess: hasPremiumAccess)
    }

    private var lockoutSummary: String? {
        guard let remainingSeconds = RecurringTaskLockout.remainingSeconds(
            recurringTask: recurringTask,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            return nil
        }
        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if !claimed {
                    // Main form content — hidden after claiming
                    formContent
                        .transition(.opacity)
                }

                if claimed {
                    // Celebration — replaces all form UI, centered in the modal.
                    // The amount springs in so the user gets clear feedback that
                    // the claim succeeded before the sheet dismisses itself.
                    ClaimCelebrationView(amount: claimedAmount) {
                        dismiss()
                        onClaim?()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: claimed)
            .background(theme.appBackground())
            .navigationTitle(claimed ? "" : "Complete Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !claimed {
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
    }

    private var formContent: some View {
        ClaimSheetFloatingActionShell(contentStyle: .quantityPicker) {
            VStack(spacing: ClaimSheetContentStyle.quantityPicker.sectionSpacing) {
                VStack(spacing: 8) {
                    // Behaviour: the sheet now opens with the payout summary in the
                    // most prominent spot, so the user focuses on the outcome first.
                    TradeAmountSummaryView(
                        amount: totalPrice,
                        polarity: .earning,
                        amountColor: theme.accentSolidFill(for: .recurringTask),
                        titleColor: theme.highContrastText(for: .recurringTask),
                        originalAmount: adjustmentCaptions.isEmpty ? nil : unadjustedTotalPrice,
                        adjustmentCaptions: adjustmentCaptions
                    )

                    Button {
                        openAdjustmentOrUpsell()
                    } label: {
                        Label(hasPremiumAccess ? "Adjust" : "Adjust", systemImage: hasPremiumAccess ? "slider.horizontal.3" : "crown.fill")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(spacing: 8) {
                    Text("Quantity")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.lowContrastText(for: .recurringTask))

                    // Quantity counter — the main centerpiece of the modal.
                    // Large number with decrement/increment buttons on either side.
                    HStack(spacing: 24) {
                        Button {
                            if quantity > 1 { quantity -= 1 }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(quantity > 1 ? theme.solidFill(for: .recurringTask) : theme.lowContrastText(for: .recurringTask))
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
                                .foregroundStyle(quantity < Self.maxQuantity ? theme.solidFill(for: .recurringTask) : theme.lowContrastText(for: .recurringTask))
                        }
                        .disabled(quantity >= Self.maxQuantity)
                    }
                }
            }
        } floatingControls: {
            if isLocked {
                lockedStatusPill
            } else {
                // Behaviour: the user confirms the exact quantity and payout in the
                // same visual block instead of needing to move to the top bar.
                BochiActionButton(
                    amount: totalPrice,
                    polarity: .earning,
                    layout: .expanded(title: "Claim"),
                    themeRoleOverride: .recurringTask,
                    priceDeltaPercent: PriceDeltaSupport.percent(
                        currentPrice: totalPrice,
                        basePrice: recurringTask.basePrice * quantity
                    )
                ) {
                    claimRecurringTask()
                }
            }
        }
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
        .foregroundStyle(theme.lowContrastText(for: .recurringTask))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.componentBackground(for: .recurringTask), in: Capsule())
    }

    // Execute the trade: create trade records, update balance, show celebration.
    private func claimRecurringTask() {
        if !allowsRestrictedClaim {
            guard !RecurringTaskLockout.isLocked(
                recurringTask: recurringTask,
                tradeStore: tradeStore,
                hasPremiumAccess: hasPremiumAccess
            ) else { return }
        }
        let claimDate = Date()
        let prices: [Int]
        let basePrices: [Int]

        if let quote {
            basePrices = quote.prices(
                recurringTask: recurringTask,
                allRecurringTasks: recurringTaskStore.activeRecurringTasks,
                quantity: quantity,
                oneTimeAdjustmentMultiplier: nil,
                hasPremiumAccess: false
            )
            if hasPremiumAccess, let oneTimeAdjustedPrice {
                prices = PriceAdjustmentSupport.distributedPrices(
                    adjustedTotal: oneTimeAdjustedPrice,
                    basePrices: basePrices
                )
            } else {
                prices = quote.prices(
                    recurringTask: recurringTask,
                    allRecurringTasks: recurringTaskStore.activeRecurringTasks,
                    quantity: quantity,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    hasPremiumAccess: hasPremiumAccess
                )
            }
        } else {
            var projectedCompletionDates = completionDates
            var livePrices: [Int] = []
            var liveBasePrices: [Int] = []

            // Create individual trade records for each completion so the
            // trade history accurately reflects each completion event.
            for _ in 0..<quantity {
                let price = RecurringTaskPriceCalculator.calculatePrice(
                    recurringTask: recurringTask,
                    allRecurringTasks: recurringTaskStore.activeRecurringTasks,
                    completionDates: projectedCompletionDates,
                    now: claimDate,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    hasPremiumAccess: hasPremiumAccess
                )
                let basePrice = RecurringTaskPriceCalculator.calculatePrice(
                    recurringTask: recurringTask,
                    allRecurringTasks: recurringTaskStore.activeRecurringTasks,
                    completionDates: projectedCompletionDates,
                    now: claimDate,
                    hasPremiumAccess: false
                )
                livePrices.append(price)
                liveBasePrices.append(basePrice)
                projectedCompletionDates.append(claimDate)
            }

            basePrices = liveBasePrices
            if hasPremiumAccess, let oneTimeAdjustedPrice {
                prices = PriceAdjustmentSupport.distributedPrices(
                    adjustedTotal: oneTimeAdjustedPrice,
                    basePrices: basePrices
                )
            } else {
                prices = livePrices
            }
        }

        let total = prices.reduce(0, +)
        let oneTimeSnapshot = oneTimeAdjustmentSnapshot(baseTotal: basePrices.reduce(0, +), adjustedTotal: total)
        let hasAdjustment = oneTimeSnapshot != nil
        let entries = zip(prices, basePrices).map { price, basePrice in
            // User behaviour: every completion in a multi-claim keeps the exact
            // quoted amount that contributed to the visible total.
            (id: RecordID(), amount: price, adjustmentBaseAmount: hasAdjustment ? basePrice : nil)
        }

        withAnimation(.default) {
            tradeStore.addRecurringTaskTrades(
                entries: entries,
                recurringTaskId: recurringTask.id,
                sourceName: recurringTask.name,
                oneTimeAdjustmentMultiplier: oneTimeSnapshot,
                createdAt: claimDate
            )
            balanceStore.refresh()
        }

        // Show celebration — replaces all form content instantly.
        // The celebration view auto-dismisses the modal after a short delay.
        claimedAmount = total
        claimed = true
    }

    private func oneTimeAdjustmentSnapshot(baseTotal: Int, adjustedTotal: Int) -> Double? {
        guard hasPremiumAccess, oneTimeAdjustedPrice != nil || oneTimeAdjustmentMultiplier != nil else { return nil }
        return oneTimeAdjustmentMultiplier
            ?? PriceAdjustmentSupport.multiplier(forAdjustedPrice: adjustedTotal, basePrice: baseTotal)
            ?? 1.0
    }

    private func openAdjustmentOrUpsell() {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .adjustments
            return
        }
        showingAdjustment = true
    }
}

// Celebration view shown after claiming — replaces all modal content.
// A centered amount springs in, then auto-dismisses.
struct ClaimCelebrationView: View {
    @Environment(\.bochiTheme) private var theme
    let amount: Int
    let onComplete: () -> Void

    // Drives the pop-in animation. Starts false (scaled to 0),
    // set to true on appear so it springs into view.
    @State private var showAnimation = false

    var body: some View {
        VStack(spacing: 12) {
            PointsAmountLabel(text: "+\(amount)", iconSize: 32)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(theme.solidFill(for: .recurringTask))
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

// Refund feedback reuses the same modal-replacement pattern as claiming, but
// shows a refund action glyph so the user sees the reversal succeeded.
struct RefundFeedbackView: View {
    @Environment(\.bochiTheme) private var theme
    let onComplete: () -> Void

    @State private var showAnimation = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(theme.solidFill(for: .recurringTask))
                .scaleEffect(showAnimation ? 1.0 : 0.0)
                .rotationEffect(.degrees(showAnimation ? 0 : -45))
                .animation(.spring(duration: 0.45, bounce: 0.5), value: showAnimation)
                .accessibilityLabel("Refunded")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            showAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onComplete()
            }
        }
    }
}

struct TaskRefundFeedbackSheet: View {
    @Environment(\.bochiTheme) private var theme
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            RefundFeedbackView(onComplete: onComplete)
                .background(theme.appBackground())
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationBackground(theme.appBackground())
    }
}
