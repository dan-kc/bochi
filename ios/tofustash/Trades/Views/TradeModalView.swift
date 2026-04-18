import SwiftUI

// Modal for claiming a habit reward. Shows the habit name, a quantity counter,
// the total price, and Cancel/Claim buttons.
//
// The quantity counter is the centerpiece — the user can claim a habit multiple
// times in one go (e.g., "I did 20 pushups" when the habit is "Do 10 pushups").
// Each successive claim changes the price because the frequency multiplier F
// adjusts based on completionsInPeriod, so the total is NOT simply price * qty.
//
// After claiming, the UI is replaced with a celebration animation, then the
// modal dismisses.
struct TradeModalView: View {
    let habit: Habit

    // Called after a successful claim. The parent uses this to chain
    // dismissals (e.g., dismiss the change form too).
    var onClaim: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(HabitStore.self) private var habitStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    // How many times the user wants to claim this habit. Starts at 1.
    // Capped at maxQuantity to prevent accidental excessive claims.
    static let maxQuantity = 99
    @State private var quantity = 1

    // Controls whether the celebration view replaces the form content.
    // When true, all form UI is hidden and the celebration is shown.
    @State private var claimed = false
    @State private var claimedAmount = 0

    // How many times this habit was completed in the last 7 days.
    // Used as the base for multi-purchase price calculation.
    private var currentCompletions: Int {
        tradeStore.tradesInPeriod(habitId: habit.id, days: 7)
    }

    // The total tofu earned for the selected quantity. NOT price * quantity —
    // each successive completion has a different price because the frequency
    // multiplier changes as completionsInPeriod increments.
    private var totalPrice: Int {
        RewardCalculation.calculateMultiPurchaseTotal(
            habit: habit,
            allHabits: habitStore.activeHabits,
            currentCompletions: currentCompletions,
            quantity: quantity,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
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
            .navigationTitle(claimed ? "" : "Claim Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !claimed {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Claim") { claimReward() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var formContent: some View {
        VStack(spacing: 24) {
            // Habit name — display only, not editable from this modal
            Text(habit.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Spacer()

            // Quantity counter — the main centerpiece of the modal.
            // Large number with decrement/increment buttons on either side.
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

            // Total price display
            VStack(spacing: 4) {
                Text("Total Reward")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("\(totalPrice)")
                        .font(.title)
                        .fontWeight(.bold)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: totalPrice)
                    Image(systemName: "cube.fill")
                        .font(.body)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // Execute the trade: create trade records, update balance, show celebration.
    private func claimReward() {
        let total = totalPrice
        var completions = currentCompletions

        // Create individual trade records for each completion so the
        // trade history accurately reflects each completion event.
        for _ in 0..<quantity {
            let price = RewardCalculation.calculateReward(
                habit: habit,
                allHabits: habitStore.activeHabits,
                completionsInPeriod: completions,
                generalDifficulty: userSettingsStore.generalDifficulty
            )
            tradeStore.addHabitTrade(habitId: habit.id, amount: price)
            completions += 1
        }

        // Update balance
        balanceStore.addTofu(total)

        // Show celebration — replaces all form content instantly.
        // The celebration view auto-dismisses the modal after a short delay.
        claimedAmount = total
        claimed = true
    }
}

// Celebration view shown after claiming — replaces all modal content.
// A centered amount springs in, then auto-dismisses.
struct ClaimCelebrationView: View {
    let amount: Int
    let onComplete: () -> Void

    // Drives the pop-in animation. Starts false (scaled to 0),
    // set to true on appear so it springs into view.
    @State private var showAnimation = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("+\(amount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Image(systemName: "cube.fill")
                    .font(.title)
            }
            .foregroundStyle(.green)
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
