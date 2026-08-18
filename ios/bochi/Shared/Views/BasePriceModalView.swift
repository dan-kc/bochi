import SwiftUI

enum BasePriceFormula {
    static func taskPrice(
        seed: Double,
        difficulty: RecurringTaskDifficultyTier?,
        durationSeconds: Int?,
        importance: ImportanceTier?
    ) -> Int {
        BackendIntegerContract.clampedNonNegative(
            seed
                * (difficulty?.multiplier ?? RecurringTaskDifficultyTier.trivial.multiplier)
                * PricingDurationMultiplier.calculate(durationSeconds: durationSeconds)
                * (importance?.multiplier ?? ImportanceTier.one.multiplier)
        )
    }
}

enum BasePriceModalSupport {
    enum SaveResult {
        case valid(Int?)
        case missingRequiredPrice
    }

    static func saveResult(text: String, currentPrice: Int?, allowsUnsetPrice: Bool) -> SaveResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return allowsUnsetPrice ? .valid(nil) : .missingRequiredPrice
        }
        if let parsedPrice = Int(trimmedText) {
            return .valid(BackendIntegerContract.clampedNonNegative(parsedPrice))
        }
        if trimmedText.allSatisfy(\.isNumber) {
            return .valid(BackendIntegerContract.max)
        }
        return .valid(BackendIntegerContract.clampedNonNegative(currentPrice ?? 0))
    }
}

struct BasePriceModalView: View {
    @Environment(\.bochiTheme) private var theme
    let title: String
    let helperSeed: Double
    let allowsUnsetPrice: Bool
    @Binding var price: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var priceRequiresAttention = false
    @State private var difficulty: RecurringTaskDifficultyTier = .medium
    @State private var durationSeconds: Int? = nil
    @State private var importance: ImportanceTier = .three

    init(title: String = "Price", price: Binding<Int?>, helperSeed: Double) {
        self.title = title
        self._price = price
        self.helperSeed = helperSeed
        self.allowsUnsetPrice = true
        self._text = State(initialValue: price.wrappedValue.map(String.init) ?? "")
    }

    init(title: String = "Price", price: Binding<Int>, helperSeed: Double) {
        self.title = title
        self._price = Binding(
            get: { Optional(price.wrappedValue) },
            set: { newValue in
                guard let newValue else { return }
                price.wrappedValue = newValue
            }
        )
        self.helperSeed = helperSeed
        self.allowsUnsetPrice = false
        self._text = State(initialValue: String(price.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ImmediateFocusTextField(placeholder: "Price", text: $text, keyboardType: .numberPad)
                        .frame(minHeight: 24)
                        .padding(.horizontal, priceRequiresAttention ? 10 : 0)
                        .padding(.vertical, priceRequiresAttention ? 6 : 0)
                        .background {
                            if priceRequiresAttention {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.componentBackground(for: .neutral))
                            }
                        }
                        .overlay {
                            if priceRequiresAttention {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(BochiTheme.solidFill(palette: .red), lineWidth: 1)
                            }
                        }
                        .onChange(of: text) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                priceRequiresAttention = false
                            }
                        }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valid range: \(BackendIntegerContract.userFacingNonNegativeRange) points.")
                        if priceRequiresAttention {
                            Text("Price is required.")
                                .foregroundStyle(BochiTheme.solidFill(palette: .red))
                        }
                    }
                }

                Section {
                    suggestedPriceCalculator
                } footer: {
                    Text("Suggested prices are capped at \(BackendIntegerContract.userFacingMax) points.")
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle(title)
            .presentationBackground(theme.appBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePrice()
                    }
                }
            }
        }
    }

    private var suggestedPrice: Int {
        BasePriceFormula.taskPrice(
            seed: helperSeed,
            difficulty: difficulty,
            durationSeconds: durationSeconds,
            importance: importance
        )
    }

    private var suggestedPriceCalculator: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Calculate Suggested Price")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText())

                    Text("(Optional)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryText())
                }

                Text("Use this to estimate a fair price from the task's effort, importance, and duration.")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText())
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                CalculatorControlGroup(title: "Difficulty") {
                    TierSelectionButtonRow(selection: $difficulty)
                }

                CalculatorControlGroup(title: "Importance") {
                    TierSelectionButtonRow(selection: $importance)
                }

                CalculatorControlGroup(title: "Duration") {
                    DurationHelperRow(durationSeconds: $durationSeconds)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Divider()

                SuggestedPriceSummary(suggestedPrice: suggestedPrice)

                Button {
                    useSuggestedPrice()
                } label: {
                    Text("Use Suggested Price")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func useSuggestedPrice() {
        text = String(suggestedPrice)
        priceRequiresAttention = false
    }

    private func savePrice() {
        switch BasePriceModalSupport.saveResult(
            text: text,
            currentPrice: price,
            allowsUnsetPrice: allowsUnsetPrice
        ) {
        case .valid(let parsedPrice):
            price = parsedPrice
            dismiss()
        case .missingRequiredPrice:
            withAnimation(.easeInOut(duration: 0.18)) {
                priceRequiresAttention = true
            }
        }
    }
}

private struct CalculatorControlGroup<Content: View>: View {
    @Environment(\.bochiTheme) private var theme
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.secondaryText())

            content()
        }
    }
}

private struct SuggestedPriceSummary: View {
    @Environment(\.bochiTheme) private var theme
    let suggestedPrice: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Suggested Price")
                .font(.headline)
                .foregroundStyle(theme.primaryText())

            Spacer(minLength: 16)

            PointsAmountLabel(text: "\(suggestedPrice)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.primaryText())
        }
        .padding(.top, 4)
    }
}

private struct TierSelectionButtonRow<Tier: PricingTierOption>: View {
    @Binding var selection: Tier

    private var options: [Tier] {
        Array(Tier.allCases).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options, id: \.self) { tier in
                    TierSelectionButton(
                        title: tier.displayName,
                        isSelected: selection == tier
                    ) {
                        selection = tier
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct TierSelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        BochiControlPillButton(isSet: isSelected, action: action) {
            Text(title)
                .font(.callout)
        }
    }
}

private struct DurationHelperRow: View {
    @Environment(\.bochiTheme) private var theme
    @Binding var durationSeconds: Int?
    @State private var durationText = ""

    var body: some View {
        TextField("Minutes", text: $durationText)
            .keyboardType(.numberPad)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.componentBackground(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.subtleBorder(), lineWidth: 1)
            }
            .onAppear {
                durationText = durationSeconds.map { String($0 / 60) } ?? ""
            }
            .onChange(of: durationText) { _, newValue in
                let minutes = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                durationSeconds = minutes.map { max(0, $0) * 60 }
            }
    }
}
