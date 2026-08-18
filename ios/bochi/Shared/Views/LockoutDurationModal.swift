import SwiftUI

struct RecurringTaskLockoutDurationModal: View {
    @Binding var durationSeconds: Int?

    var body: some View {
        LockoutDurationModal(durationSeconds: $durationSeconds, context: .recurringTask)
    }
}

struct RewardLockoutDurationModal: View {
    @Binding var durationSeconds: Int?

    var body: some View {
        LockoutDurationModal(durationSeconds: $durationSeconds, context: .reward)
    }
}

private enum LockoutDurationContext {
    case recurringTask
    case reward

    var instructions: String {
        switch self {
        case .recurringTask:
            return "Set how long the recurring task should stay locked after the user completes it."
        case .reward:
            return "Set how long the reward should stay locked after the user purchases it."
        }
    }

    var clearButtonTitle: String {
        switch self {
        case .recurringTask:
            return "Clear Lockout"
        case .reward:
            return "Clear Reward Lockout"
        }
    }

    var themeRole: BochiThemeRole {
        switch self {
        case .recurringTask:
            return .recurringTask
        case .reward:
            return .reward
        }
    }
}

// Shared lockout editor for the cooldown after a claim or purchase. This stays
// separate from the duration picker because the user is configuring when an
// action becomes available again, not how long the action itself takes.
private struct LockoutDurationModal: View {
    @Environment(\.bochiTheme) private var theme
    private enum DurationUnit: String, CaseIterable {
        case minutes
        case hours
        case days

        var label: String { rawValue.capitalized }
    }

    @Binding var durationSeconds: Int?
    let context: LockoutDurationContext
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var unit: DurationUnit = .minutes

    private static let minDurationSeconds = 60
    private static let maxDurationSeconds = 2_592_000

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(context.instructions)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText())
                }

                Section {
                    TextField("Lockout", text: $valueText)
                        .keyboardType(.numberPad)

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
                        .foregroundStyle(theme.secondaryText())
                }

                if let durationSeconds {
                    Section {
                        HStack {
                            Text("Current")
                                .foregroundStyle(theme.secondaryText())
                            Spacer()
                            Text(DurationFormatting.summary(seconds: durationSeconds) ?? "")
                                .foregroundStyle(theme.lowContrastText(for: context.themeRole))
                        }
                    }
                }

                if durationSeconds != nil {
                    Section {
                        Button(context.clearButtonTitle) {
                            durationSeconds = nil
                            dismiss()
                        }
                        .foregroundStyle(theme.destructiveText())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle("Lockout")
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
