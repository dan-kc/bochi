import SwiftUI

struct ReminderModalView: View {
    @Environment(\.bochiTheme) private var theme
    private enum DraftMode: String, CaseIterable, Identifiable {
        case oneOff
        case recurring

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oneOff:
                return "One-time"
            case .recurring:
                return "Recurring"
            }
        }
    }

    @Binding var reminders: [ReminderDraft]

    let dueDate: Date?
    let referenceDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var draftDate: Date
    @State private var draftMode: DraftMode = .oneOff
    @State private var repeatValue = 1
    @State private var repeatUnit: ReminderRepeatUnit = .days

    init(
        reminders: Binding<[ReminderDraft]>,
        dueDate: Date?,
        referenceDate: Date
    ) {
        self._reminders = reminders
        self.dueDate = dueDate
        self.referenceDate = referenceDate
        let defaultDate = max(referenceDate.addingTimeInterval(5 * 60).timeIntervalSince1970, dueDate?.timeIntervalSince1970 ?? 0)
        _draftDate = State(initialValue: Date(timeIntervalSince1970: defaultDate))
    }

    private var visibleReminders: [ReminderDraft] {
        ReminderDraftSupport.active(reminders, now: referenceDate)
    }

    private var draftRecurrence: ReminderRecurrence? {
        guard draftMode == .recurring else { return nil }
        return ReminderRecurrence(intervalValue: repeatValue, unit: repeatUnit)
    }

    private var canAddDraft: Bool {
        let draft = ReminderDraft(scheduledAt: draftDate, recurrence: draftRecurrence)
        return ReminderDraftSupport.nextOccurrence(for: draft, now: referenceDate) != nil
    }

    private var quickOptions: [ReminderQuickOption] {
        guard draftMode == .oneOff, let dueDate else { return [] }
        return ReminderQuickOptions.options(dueDate: dueDate, now: referenceDate)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Scheduled") {
                    if visibleReminders.isEmpty {
                        Text("No active reminders")
                            .foregroundStyle(theme.secondaryText())
                    } else {
                        ForEach(visibleReminders) { reminder in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let recurrence = reminder.recurrence {
                                        Text(recurrence.summary)
                                        Text(ReminderDraftSupport.occurrenceLabel(for: reminder, now: referenceDate))
                                            .font(.footnote)
                                            .foregroundStyle(theme.secondaryText())
                                    } else {
                                        Text(ReminderDraftSupport.occurrenceLabel(for: reminder, now: referenceDate))
                                    }
                                }
                                Spacer()
                                Button {
                                    deleteReminder(reminder.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(theme.destructiveText())
                                }
                            }
                        }
                    }
                }

                Section("Add Reminder") {
                    Picker("Type", selection: $draftMode) {
                        ForEach(DraftMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker(
                        draftMode == .recurring ? "Start" : "Time",
                        selection: $draftDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    if draftMode == .recurring {
                        Stepper(
                            value: $repeatValue,
                            in: 1...repeatUnit.maxIntervalValue()
                        ) {
                            Text("Every \(repeatValue) \(repeatUnit.label(for: repeatValue))")
                        }

                        Picker("Repeat Unit", selection: $repeatUnit) {
                            ForEach(ReminderRepeatUnit.allCases, id: \.self) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                    }

                    Button("Add Reminder") {
                        addReminder()
                    }
                    .disabled(!canAddDraft)
                }

                if !quickOptions.isEmpty {
                    Section("Quick Add") {
                        ForEach(quickOptions) { option in
                            Button(option.title) {
                                draftDate = option.scheduledAt
                                addReminder()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .foregroundStyle(theme.primaryText())
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(theme.appBackground())
            .presentationContentInteraction(.scrolls)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: repeatUnit) { _, newUnit in
                repeatValue = min(repeatValue, newUnit.maxIntervalValue())
            }
        }
    }

    private func addReminder() {
        let reminder = ReminderDraft(
            scheduledAt: draftDate,
            recurrence: draftRecurrence
        )
        guard ReminderDraftSupport.nextOccurrence(for: reminder, now: referenceDate) != nil else { return }
        reminders.append(reminder)
        reminders.sort(by: ReminderDraftSupport.sortDrafts)
    }

    private func deleteReminder(_ id: RecordID) {
        reminders.removeAll { $0.id == id }
    }
}
