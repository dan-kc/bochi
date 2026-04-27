import SwiftUI

// Separate lockout editor for the cooldown after a claim. This is intentionally
// a standalone view instead of a reused generic time picker so it can evolve
// separately from expected duration.
struct HabitLockoutDurationModal: View {
    private enum DurationUnit: String, CaseIterable {
        case minutes
        case hours
        case days

        var label: String { rawValue.capitalized }
    }

    @Binding var durationSeconds: Int?
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var unit: DurationUnit = .minutes

    private static let minDurationSeconds = 60
    private static let maxDurationSeconds = 2_592_000

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set how long the habit should stay locked after the user claims it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Lockout", text: $valueText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("habit-lockout.value")

                    Picker("Unit", selection: $unit) {
                        ForEach(DurationUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Choose a lockout between 1 minute and 30 days.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let durationSeconds {
                    Section {
                        HStack {
                            Text("Current")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(DurationFormatting.summary(seconds: durationSeconds) ?? "")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if durationSeconds != nil {
                    Section {
                        Button("Clear Lockout", role: .destructive) {
                            durationSeconds = nil
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Lockout")
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
                    .disabled(parsedSeconds == nil)
                }
            }
            .onAppear {
                initializeFromBinding()
            }
        }
    }

    private var parsedSeconds: Int? {
        guard let value = Int(valueText), value > 0 else { return nil }

        let seconds: Int
        switch unit {
        case .minutes:
            seconds = value * 60
        case .hours:
            seconds = value * 3_600
        case .days:
            seconds = value * 86_400
        }

        guard (Self.minDurationSeconds...Self.maxDurationSeconds).contains(seconds) else { return nil }
        return seconds
    }

    private func initializeFromBinding() {
        guard let durationSeconds else { return }

        if durationSeconds % 86_400 == 0 {
            unit = .days
            valueText = String(durationSeconds / 86_400)
        } else if durationSeconds % 3_600 == 0 {
            unit = .hours
            valueText = String(durationSeconds / 3_600)
        } else {
            // Legacy values may include second-level precision, but the editor
            // now only supports minute granularity. Round up so reopening the
            // field never shortens an existing cooldown for the user.
            unit = .minutes
            valueText = String((durationSeconds + 59) / 60)
        }
    }

    private func saveAndDismiss() {
        guard let parsedSeconds else { return }
        durationSeconds = parsedSeconds
        dismiss()
    }
}
