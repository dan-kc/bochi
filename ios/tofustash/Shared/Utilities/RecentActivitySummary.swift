import Foundation

enum RecentActivitySummary {
    // Keep the wording in one place so every editor talks about recent
    // completions/purchases the same way instead of each view hand-rolling its
    // own "today / yesterday / full date" rules.
    nonisolated static func text(
        prefix: String,
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        timeText: (Date) -> String = Self.timeText,
        fullDateTimeText: (Date) -> String = Self.fullDateTimeText
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "\(prefix) at \(timeText(date)) today"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(prefix) at \(timeText(date)) yesterday"
        }

        return "\(prefix) \(fullDateTimeText(date))"
    }

    nonisolated static func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    nonisolated static func fullDateTimeText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
