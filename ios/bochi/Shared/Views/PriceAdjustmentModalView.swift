import SwiftUI

struct PriceAdjustmentModalView: View {
    @Environment(\.bochiTheme) private var theme
    let title: String
    let basePrice: Int
    @Binding var multiplier: Double?
    @Binding var adjustedPriceOverride: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var adjustedPriceText: String
    @State private var errorMessage: String?

    init(
        title: String,
        basePrice: Int,
        adjustedPrice: Int,
        multiplier: Binding<Double?>,
        adjustedPriceOverride: Binding<Int?>
    ) {
        self.title = title
        self.basePrice = basePrice
        self._multiplier = multiplier
        self._adjustedPriceOverride = adjustedPriceOverride
        self._adjustedPriceText = State(initialValue: "\(adjustedPrice)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Use one-time adjustments sparingly when the normal price misses something important about this specific claim or purchase.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText())
                }

                Section("Price") {
                    LabeledContent("Previous") {
                        bochiAmount(basePrice)
                    }
                    LabeledContent("New Price") {
                        TextField("Price", text: $adjustedPriceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                            .onChange(of: adjustedPriceText) { _, newValue in
                                applyAdjustedPriceText(newValue)
                            }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(theme.warningText())
                    }
                    Button("Reset to Previous Price") {
                        adjustedPriceText = "\(basePrice)"
                        multiplier = nil
                        adjustedPriceOverride = nil
                        errorMessage = nil
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(errorMessage != nil || adjustedPriceText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.appBackground())
    }

    private func bochiAmount(_ amount: Int) -> some View {
        PointsAmountLabel(text: "\(amount)")
            .font(.body.weight(.semibold))
    }

    private func applyAdjustedPriceText(_ text: String) {
        let normalizedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        guard !normalizedText.isEmpty else {
            errorMessage = "Enter a new price."
            return
        }

        guard let parsedPrice = Int(normalizedText),
              (0...BackendIntegerContract.max).contains(parsedPrice)
        else {
            errorMessage = "Enter whole points from 0 through \(BackendIntegerContract.userFacingMax)."
            return
        }

        if parsedPrice == basePrice {
            multiplier = nil
            adjustedPriceOverride = nil
            errorMessage = nil
            return
        }

        let updatedMultiplier = PriceAdjustmentSupport.multiplier(
            forAdjustedPrice: parsedPrice,
            basePrice: basePrice
        )

        multiplier = updatedMultiplier ?? 1.0
        adjustedPriceOverride = parsedPrice
        errorMessage = nil
    }
}
