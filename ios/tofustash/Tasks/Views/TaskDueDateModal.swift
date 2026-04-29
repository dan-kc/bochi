import SwiftUI

struct TaskDueDateModal: View {
    @Binding var dueDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var draftDate: Date = Self.defaultDate()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set when this task should be due so reminder timing and list context stay aligned.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Quick Set") {
                    Button("Today at 9:00 AM") {
                        draftDate = Self.dateAtHour(9, dayOffset: 0)
                    }
                    .accessibilityIdentifier("task-due-date.quick.today")

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
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TaskFormView.dueDateSummary(dueDate))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if dueDate != nil {
                    Section {
                        Button("Clear Due Date", role: .destructive) {
                            dueDate = nil
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(.thinMaterial)
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
