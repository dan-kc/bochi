import SwiftUI

struct TaskClaimRoute: Identifiable {
    let task: TaskItem
    let price: Int
    var allowsRestrictedClaim: Bool = false

    var id: RecordID { task.id }
}

struct TaskClaimModalView: View {
    @Environment(\.bochiTheme) private var theme
    let task: TaskItem
    let price: Int
    let hasPremiumAccess: Bool
    let onClaim: (Int, Int?, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var claimed = false
    @State private var oneTimeAdjustmentMultiplier: Double? = nil
    @State private var oneTimeAdjustedPrice: Int? = nil
    @State private var showingAdjustment = false
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil

    private var priceSnapshot: TaskCompletionPriceSnapshot {
        TaskCompletionService.priceSnapshot(
            task: task,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            oneTimeAdjustedPrice: oneTimeAdjustedPrice,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    private var adjustedPrice: Int {
        priceSnapshot.price
    }

    private var unadjustedPrice: Int {
        TaskPriceCalculator.calculatePrice(
            task: task
        )
    }

    private var adjustmentCaptions: [String] {
        var captions: [String] = []
        if hasPremiumAccess, oneTimeAdjustedPrice != nil || oneTimeAdjustmentMultiplier != nil {
            captions.append("One-time adjustment")
        }
        return captions
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if claimed {
                    ClaimCelebrationView(amount: adjustedPrice) {
                        dismiss()
                    }
                    .transition(.opacity)
                } else {
                    formContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: claimed)
            .background(theme.appBackground())
            .navigationTitle(claimed ? "" : "Claim Task")
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
                basePrice: unadjustedPrice,
                adjustedPrice: adjustedPrice,
                multiplier: $oneTimeAdjustmentMultiplier,
                adjustedPriceOverride: $oneTimeAdjustedPrice
            )
        }
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
    }

    private var formContent: some View {
        ClaimSheetFloatingActionShell {
            VStack(spacing: 8) {
                TradeAmountSummaryView(
                    amount: adjustedPrice,
                    polarity: .earning,
                    amountColor: theme.accentSolidFill(for: .task),
                    titleColor: theme.highContrastText(for: .task),
                    originalAmount: adjustmentCaptions.isEmpty ? nil : unadjustedPrice,
                    adjustmentCaptions: adjustmentCaptions
                )

                Button {
                    openAdjustmentOrUpsell()
                } label: {
                    Label("Adjust", systemImage: hasPremiumAccess ? "slider.horizontal.3" : "crown.fill")
                }
                .buttonStyle(.bordered)
            }
        } floatingControls: {
            BochiActionButton(
                amount: adjustedPrice,
                polarity: .earning,
                layout: .expanded(title: "Claim Task"),
                themeRoleOverride: .task
            ) {
                let snapshot = priceSnapshot
                onClaim(
                    snapshot.price,
                    snapshot.adjustmentBaseAmount,
                    snapshot.oneTimeAdjustmentMultiplier
                )
                claimed = true
            }
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
