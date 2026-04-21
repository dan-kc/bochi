import SwiftUI

// Separate duration editor for expected effort time. This intentionally does
// not share an implementation with the lockout modal because the product copy
// and behaviour may diverge later.
struct HabitDurationModal: View {
    private enum DurationUnit: String, CaseIterable {
        case seconds
        case minutes
        case hours

        var label: String { rawValue.capitalized }
    }

    @Binding var durationSeconds: Int?
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var unit: DurationUnit = .minutes

    private static let maxDurationSeconds = 43_200

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set how long this habit usually takes when the user completes it properly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Duration", text: $valueText)
                        .keyboardType(.numberPad)

                    Picker("Unit", selection: $unit) {
                        ForEach(DurationUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
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
                        Button("Clear Duration", role: .destructive) {
                            durationSeconds = nil
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Duration")
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
        case .seconds:
            seconds = value
        case .minutes:
            seconds = value * 60
        case .hours:
            seconds = value * 3_600
        }

        guard seconds <= Self.maxDurationSeconds else { return nil }
        return seconds
    }

    private func initializeFromBinding() {
        guard let durationSeconds else { return }

        if durationSeconds % 3_600 == 0 {
            unit = .hours
            valueText = String(durationSeconds / 3_600)
        } else if durationSeconds % 60 == 0 {
            unit = .minutes
            valueText = String(durationSeconds / 60)
        } else {
            unit = .seconds
            valueText = String(durationSeconds)
        }
    }

    private func saveAndDismiss() {
        guard let parsedSeconds else { return }
        durationSeconds = parsedSeconds
        dismiss()
    }
}

