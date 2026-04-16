import SwiftUI

// Modal for setting habit frequency with a period picker (Day/Week/Month)
// and a number input.
//
// In React, this would be a controlled component with value/onChange.
// Here, `@Binding var frequency: Double?` is the two-way binding to the
// parent's state. Changes to the binding propagate back automatically.
struct FrequencyModal: View {
    @Binding var frequency: Double?
    @Environment(\.dismiss) private var dismiss

    // Local state — initialized from the binding in .onAppear.
    // In React, you'd do:
    //   const [value, setValue] = useState(props.frequency ? ... : "")
    //   useEffect(() => { /* sync from props */ }, [props.frequency])
    @State private var valueText = ""
    @State private var period: FrequencyPeriod = .day

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Times per period", text: $valueText)
                        .keyboardType(.decimalPad)

                    // Picker with .segmented style renders as a segmented control —
                    // like a SegmentedControl in React Native or radio buttons in a row.
                    // The selection binding ($period) updates automatically when tapped.
                    Picker("Period", selection: $period) {
                        // CaseIterable lets us loop over all enum cases.
                        // Like Object.values(FrequencyPeriod).map(...) in TS.
                        ForEach(FrequencyPeriod.allCases, id: \.self) { p in
                            // .capitalized uppercases the first letter: "day" → "Day"
                            Text(p.label.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Show current frequency summary if set
                if let freq = frequency {
                    Section {
                        HStack {
                            Text("Current")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(FrequencyConversion.formatSummary(freq) ?? "")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Clear button when frequency is set
                if frequency != nil {
                    Section {
                        Button("Clear Frequency", role: .destructive) {
                            frequency = nil
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Frequency")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(.thinMaterial)
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .disabled(valueText.isEmpty || Double(valueText) == nil)
                }
            }
            .onAppear {
                initializeFromBinding()
            }
        }
    }

    // Initializes local state from the frequency binding — like syncing
    // props to local state in a useEffect.
    private func initializeFromBinding() {
        guard let freq = frequency else { return }

        let (value, p) = FrequencyConversion.fromDailyRate(freq)
        valueText = FrequencyConversion.formatNumber(value)
        period = p
    }

    private func saveAndDismiss() {
        guard let value = Double(valueText), value > 0 else { return }

        frequency = FrequencyConversion.toDailyRate(value: value, period: period)
        dismiss()
    }
}
