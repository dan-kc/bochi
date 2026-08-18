import Foundation

nonisolated struct TimerInterval: Identifiable, Equatable, Sendable, Codable {
    var id: String { "\(name):\(durationSeconds)" }
    let name: String
    let durationSeconds: Int
}

// A saved, reusable timer. Countdown progress is intentionally not stored here;
// only the user-authored timer definition syncs across devices.
nonisolated struct BochiTimer: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let name: String
    let intervals: [TimerInterval]
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let serverRevision: Int64?

    init(
        id: RecordID,
        name: String,
        intervals: [TimerInterval],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.intervals = intervals
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}

nonisolated enum EntityTimerSelection: Equatable, Sendable, Codable {
    case none
    case named(RecordID)
    case duration

    var modeValue: String? {
        switch self {
        case .none:
            return nil
        case .named:
            return "named"
        case .duration:
            return "duration"
        }
    }

    var timerID: RecordID? {
        if case .named(let id) = self { return id }
        return nil
    }

    static func from(mode: String?, timerID: RecordID?) -> EntityTimerSelection {
        switch mode {
        case "named":
            guard let timerID else { return .none }
            return .named(timerID)
        case "duration":
            return .duration
        default:
            return .none
        }
    }

    func resolvedForDuration(_ durationSeconds: Int?) -> EntityTimerSelection {
        switch self {
        case .duration where durationSeconds == nil:
            return .none
        default:
            return self
        }
    }
}
