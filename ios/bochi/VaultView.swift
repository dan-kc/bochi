import SwiftUI

struct VaultView: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore

    @State private var depositAmount = ""
    @State private var depositError: String?
    @FocusState private var isDepositFieldFocused: Bool

    private var vaultBalanceText: String {
        VaultAmount.formatted(tradeStore.vaultBalanceMicro())
    }

    private var interest24HoursText: String {
        VaultAmount.formatted(tradeStore.vaultInterestEarnedMicro(since: Date(timeIntervalSinceNow: -24 * 60 * 60)))
    }

    private var interestWeekText: String {
        VaultAmount.formatted(tradeStore.vaultInterestEarnedMicro(since: Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)))
    }

    private var nextPurchaseText: String {
        guard let availableAt = tradeStore.nextVaultPurchaseAvailableAt() else {
            return "Available now"
        }
        return availableAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        PointsAmountLabel(text: vaultBalanceText, iconSize: 32)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("Bank Balance")
                            .font(.headline)
                            .foregroundStyle(theme.secondaryText())
                    }
                    .padding(.vertical, 8)
                }

                Section("Availability") {
                    Label(nextPurchaseText, systemImage: "calendar")
                }

                Section("Interest") {
                    HStack {
                        Text("Past 24 Hours")
                        Spacer()
                        PointsAmountLabel(text: "+\(interest24HoursText)")
                            .foregroundStyle(theme.positiveText())
                    }
                    HStack {
                        Text("Past Week")
                        Spacer()
                        PointsAmountLabel(text: "+\(interestWeekText)")
                            .foregroundStyle(theme.positiveText())
                    }
                }

                Section {
                    TextField("Amount", text: $depositAmount)
                        .keyboardType(.numberPad)
                        .focused($isDepositFieldFocused)
                    Button {
                        deposit()
                    } label: {
                        Label("Deposit", systemImage: "tray.and.arrow.down.fill")
                    }
                    .disabled(parsedDepositAmount == nil)

                    if let depositError {
                        Text(depositError)
                            .font(.footnote)
                            .foregroundStyle(theme.warningText())
                    }
                } header: {
                    Text("Deposit")
                } footer: {
                    Text("Deposits are permanent and cannot be refunded.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle("Bank")
        }
        .background(theme.appBackground())
    }

    private var parsedDepositAmount: Int? {
        guard let amount = Int(depositAmount), amount > 0 else { return nil }
        return amount
    }

    private func deposit() {
        isDepositFieldFocused = false

        guard let amount = parsedDepositAmount else { return }
        guard amount <= balanceStore.balance else {
            depositError = "Insufficient spendable balance."
            return
        }

        tradeStore.addVaultDeposit(amount: amount)
        balanceStore.refresh()
        depositAmount = ""
        depositError = nil
    }
}
