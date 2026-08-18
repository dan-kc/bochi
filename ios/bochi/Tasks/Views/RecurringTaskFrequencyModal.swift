import SwiftUI

// Mirrors the reward frequency editor, but the copy is inverted: the user sets
// the minimum healthy rate for completing the recurring task rather than the
// maximum rate for buying a reward.
struct RecurringTaskFrequencyModal: View {
    @Environment(\.bochiTheme) private var theme
    @Binding var frequency: Double?
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var period: FrequencyPeriod = .day

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set the minimum frequency you want for completing this recurring task.")
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

                if let freq = frequency {
                    Section {
                        HStack {
                            Text("Current")
                                .foregroundStyle(theme.secondaryText())
                            Spacer()
                            Text(FrequencyConversion.formatSummary(freq) ?? "")
                                .foregroundStyle(theme.lowContrastText(for: .recurringTask))
                        }
                    }
                }

                if frequency != nil {
                    Section {
                        Button("Clear Frequency") {
                            frequency = nil
                            dismiss()
                        }
                        .foregroundStyle(theme.destructiveText())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle("Frequency")
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
        guard let freq = frequency else { return }

        let (value, p) = FrequencyConversion.fromDailyRate(freq)
        valueText = FrequencyConversion.formatNumber(value)
        period = p
    }

    private func saveAndDismiss() {
        guard hasValidFrequencyInput else { return }

        frequency = FrequencyConversion.toDailyRate(value: Double(Int(valueText) ?? 0), period: period)
        dismiss()
    }

    private var hasValidFrequencyInput: Bool {
        guard let value = Int(valueText), value > 0 else { return false }
        let rate = FrequencyConversion.toDailyRate(value: Double(value), period: period)
        return FrequencyBounds.contains(rate)
    }
}
