import Foundation

enum ReminderOwnerTarget: Equatable, Sendable {
    case task(RecordID)
    case recurringTask(RecordID)

    var taskID: RecordID? {
        if case .task(let id) = self { return id }
        return nil
    }

    var recurringTaskID: RecordID? {
        if case .recurringTask(let id) = self { return id }
        return nil
    }
}

enum ReminderRepeatUnit: String, CaseIterable, Codable, Sendable {
    case minutes
    case hours
    case days
    case weeks

    nonisolated var title: String {
        switch self {
        case .minutes:
            return "Minutes"
        case .hours:
            return "Hours"
        case .days:
            return "Days"
        case .weeks:
            return "Weeks"
        }
    }

    nonisolated var calendarComponent: Calendar.Component {
        switch self {
        case .minutes:
            return .minute
        case .hours:
            return .hour
        case .days:
            return .day
        case .weeks:
            return .weekOfYear
        }
    }

    nonisolated var approximateSeconds: TimeInterval {
        switch self {
        case .minutes:
            return 60
        case .hours:
            return 60 * 60
        case .days:
            return 24 * 60 * 60
        case .weeks:
            return 7 * 24 * 60 * 60
        }
    }

    nonisolated func maxIntervalValue(default fallback: Int = 9_999) -> Int {
        switch self {
        case .weeks:
            return 52
        case .minutes, .hours, .days:
            return fallback
        }
    }

    nonisolated func label(for intervalValue: Int) -> String {
        switch self {
        case .minutes:
            return intervalValue == 1 ? "minute" : "minutes"
        case .hours:
            return intervalValue == 1 ? "hour" : "hours"
        case .days:
            return intervalValue == 1 ? "day" : "days"
        case .weeks:
            return intervalValue == 1 ? "week" : "weeks"
        }
    }
}

struct ReminderRecurrence: Equatable, Codable, Sendable {
    var intervalValue: Int
    var unit: ReminderRepeatUnit

    nonisolated var isValid: Bool {
        intervalValue > 0 && intervalValue <= unit.maxIntervalValue()
    }

    nonisolated var summary: String {
        "Every \(intervalValue) \(unit.label(for: intervalValue))"
    }
}

struct ReminderDraft: Identifiable, Equatable, Sendable {
    let id: RecordID
    var scheduledAt: Date
    var recurrence: ReminderRecurrence?

    init(id: RecordID = RecordID(), scheduledAt: Date, recurrence: ReminderRecurrence? = nil) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.recurrence = recurrence
    }
}

struct ReminderQuickOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let scheduledAt: Date
}

enum ReminderQuickOptions {
    private struct Template {
        let id: String
        let title: String
        let secondsBeforeDue: TimeInterval
    }

    private static let templates: [Template] = [
        Template(id: "15m", title: "15 minutes before due", secondsBeforeDue: 15 * 60),
        Template(id: "5m", title: "5 minutes before due", secondsBeforeDue: 5 * 60),
        Template(id: "1h", title: "1 hour before due", secondsBeforeDue: 60 * 60)
    ]

    static func options(dueDate: Date, now: Date = Date()) -> [ReminderQuickOption] {
        templates.compactMap { template in
            let scheduledAt = dueDate.addingTimeInterval(-template.secondsBeforeDue)
            guard scheduledAt > now else { return nil }
            return ReminderQuickOption(
                id: template.id,
                title: template.title,
                scheduledAt: scheduledAt
            )
        }
    }
}

enum ReminderDraftSupport {
    nonisolated static func active(_ drafts: [ReminderDraft], now: Date) -> [ReminderDraft] {
        drafts
            .compactMap { draft -> (ReminderDraft, Date)? in
                guard let nextOccurrence = nextOccurrence(for: draft, now: now) else { return nil }
                return (draft, nextOccurrence)
            }
            .sorted { (lhs: (ReminderDraft, Date), rhs: (ReminderDraft, Date)) in
                if lhs.1 == rhs.1 {
                    return sortDrafts(lhs.0, rhs.0)
                }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }

    nonisolated static func summary(for drafts: [ReminderDraft], now: Date) -> String {
        let count = active(drafts, now: now).count
        guard count > 0 else { return "Not set" }
        return count == 1 ? "1 reminder" : "\(count) reminders"
    }

    nonisolated static func nextOccurrence(
        for draft: ReminderDraft,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let recurrence = draft.recurrence else {
            return draft.scheduledAt > now ? draft.scheduledAt : nil
        }

        guard recurrence.isValid else { return nil }
        if draft.scheduledAt > now {
            return draft.scheduledAt
        }

        let intervalSeconds = recurrence.unit.approximateSeconds * Double(recurrence.intervalValue)
        let elapsedSeconds = now.timeIntervalSince(draft.scheduledAt)
        let approximateStep = max(Int(elapsedSeconds / intervalSeconds) - 1, 0)

        var occurrenceIndex = approximateStep
        while occurrenceIndex < approximateStep + 3 {
            if let candidate = occurrence(for: draft, step: occurrenceIndex, calendar: calendar),
               candidate > now {
                return candidate
            }
            occurrenceIndex += 1
        }

        var fallbackIndex = max(approximateStep + 3, 0)
        while fallbackIndex < approximateStep + 10_000 {
            if let candidate = occurrence(for: draft, step: fallbackIndex, calendar: calendar),
               candidate > now {
                return candidate
            }
            fallbackIndex += 1
        }

        return nil
    }

    nonisolated static func occurrenceLabel(for draft: ReminderDraft, now: Date) -> String {
        let next = nextOccurrence(for: draft, now: now)
        let nextText = next?.formatted(.dateTime.month(.abbreviated).day().hour().minute()) ?? "No upcoming occurrence"

        guard draft.recurrence != nil else {
            return nextText
        }

        return "Next \(nextText)"
    }

    nonisolated static func sortDrafts(_ lhs: ReminderDraft, _ rhs: ReminderDraft) -> Bool {
        if lhs.scheduledAt == rhs.scheduledAt {
            return lhs.id.rawValue < rhs.id.rawValue
        }

        return lhs.scheduledAt < rhs.scheduledAt
    }

    private nonisolated static func occurrence(
        for draft: ReminderDraft,
        step: Int,
        calendar: Calendar
    ) -> Date? {
        guard let recurrence = draft.recurrence else {
            return step == 0 ? draft.scheduledAt : nil
        }

        return calendar.date(
            byAdding: recurrence.unit.calendarComponent,
            value: recurrence.intervalValue * step,
            to: draft.scheduledAt
        )
    }
}
