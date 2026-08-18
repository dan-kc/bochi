import SwiftUI

// Mirrors the recurringTask frequency editor, but the copy is inverted: the user sets
// the maximum healthy rate for buying the reward rather than the minimum rate
// for doing a recurringTask.
struct RewardFrequencyModal: View {
    @Environment(\.bochiTheme) private var theme
    @Binding var maxFrequency: Double?
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var period: FrequencyPeriod = .day

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set the maximum frequency you want for purchasing this reward.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText())
                }

                Section {
                    TextField("Times per period", text: $valueText)
                        .keyboardType(.numberPad)

                    Picker("Period", selection: $period) {
                        ForEach(FrequencyPeriod.allCases, id: \.self) { option in
                            Text(option.label.capitalized).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Enter a whole number. Allowed range: 1 per month up to 100 per day.")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText())
                }

                if let maxFrequency {
                    Section {
                        HStack {
                            Text("Current")
                                .foregroundStyle(theme.secondaryText())
                            Spacer()
                            Text(FrequencyConversion.formatSummary(maxFrequency) ?? "")
                                .foregroundStyle(theme.lowContrastText(for: .reward))
                        }
                    }
                }

                if maxFrequency != nil {
                    Section {
                        Button("Clear Max Frequency") {
                            maxFrequency = nil
                            dismiss()
                        }
                        .foregroundStyle(theme.destructiveText())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle("Max Frequency")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(theme.appBackground())
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .disabled(!hasValidFrequencyInput)
                }
            }
            .onAppear {
                initializeFromBinding()
            }
            .onChange(of: valueText) { _, newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                if digitsOnly != newValue {
                    valueText = digitsOnly
                }
            }
        }
    }

    private func initializeFromBinding() {
        guard let maxFrequency else { return }

        let (value, period) = FrequencyConversion.fromDailyRate(maxFrequency)
        valueText = FrequencyConversion.formatNumber(value)
        self.period = period
    }

    private func saveAndDismiss() {
        guard hasValidFrequencyInput else { return }
        maxFrequency = FrequencyConversion.toDailyRate(value: Double(Int(valueText) ?? 0), period: period)
        dismiss()
    }

    private var hasValidFrequencyInput: Bool {
        guard let value = Int(valueText), value > 0 else { return false }
        let rate = FrequencyConversion.toDailyRate(value: Double(value), period: period)
        return FrequencyBounds.contains(rate)
    }
}
