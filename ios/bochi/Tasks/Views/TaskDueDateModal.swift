import SwiftUI

struct TaskDueDateModal: View {
    @Environment(\.bochiTheme) private var theme
    @Binding var dueDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var draftDate: Date = Self.defaultDate()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set when this task should be due so reminder timing and list context stay aligned.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText())
                }

                Section("Quick Set") {
                    Button("Today at 9:00 AM") {
                        draftDate = Self.dateAtHour(9, dayOffset: 0)
                    }

                    Button("Tomorrow at 9:00 AM") {
                        draftDate = Self.dateAtHour(9, dayOffset: 1)
                    }
                }

                Section {
                    DatePicker(
                        "Due",
                        selection: $draftDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if let dueDate {
                    Section {
                        HStack {
                            Text("Current")
                                .foregroundStyle(theme.secondaryText())
                            Spacer()
                            Text(TaskFormView.dueDateSummary(dueDate))
                                .foregroundStyle(theme.lowContrastText(for: .task))
                        }
                    }
                }

                if dueDate != nil {
                    Section {
                        Button("Clear Due Date") {
                            dueDate = nil
                            dismiss()
                        }
                        .foregroundStyle(theme.destructiveText())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(theme.appBackground())
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dueDate = draftDate
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftDate = dueDate ?? Self.defaultDate()
            }
        }
    }

    private static func defaultDate() -> Date {
        dateAtHour(9, dayOffset: 0)
    }

    private static func dateAtHour(_ hour: Int, dayOffset: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let offsetDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: offsetDay) ?? now
    }
}
