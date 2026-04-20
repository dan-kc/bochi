import SwiftUI

// A sheet for adjusting the general difficulty setting, which scales reward
// purchase costs across the app. Habit payouts stay controlled by each
// habit's own difficulty tier and cadence.
//
// Port of frontend/components/settings/GeneralDifficultyModal.tsx.
// Uses a TextField with validation instead of the React Native TextInput.
struct GeneralDifficultyView: View {
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(\.dismiss) private var dismiss

    // Local text field state — separate from the store value so the user
    // can type freely and we only commit on Save. Like a controlled input
    // in React where onChange updates local state, not the store.
    @State private var inputText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Controls the overall scale of reward costs. Higher values make rewards more expensive. Habit payouts are not affected. Default is 5.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    // .keyboardType(.decimalPad) shows the numeric keyboard
                    // with a decimal point — like keyboardType="decimal-pad"
                    // in React Native.
                    TextField("e.g. 5.0", text: $inputText)
                        .keyboardType(.decimalPad)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("General Difficulty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            // .task runs once when the view appears — like useEffect([], ...).
            // Populate the text field with the current store value.
            .task {
                inputText = formatNumber(userSettingsStore.generalDifficulty)
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let value = Double(inputText), value > 0, value < 1000 else {
            errorMessage = "Must be a number greater than 0 and less than 1000"
            return
        }
        userSettingsStore.setGeneralDifficulty(value)
        dismiss()
    }

    // Format a Double by removing unnecessary trailing zeros.
    // 5.0 → "5", 2.5 → "2.5"
    private func formatNumber(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        var result = formatted
        while result.hasSuffix("0") { result = String(result.dropLast()) }
        if result.hasSuffix(".") { result = String(result.dropLast()) }
        return result
    }
}
