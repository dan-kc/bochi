import Foundation

nonisolated enum TimerRunEvent: Equatable, Sendable {
    case intervalTransition
    case completed
}

// Timer progress is elapsed-time based so delayed UI work, suspension, and
// background execution never change how long the user's routine takes.
nonisolated struct TimerRunState: Equatable, Sendable {
    private(set) var intervals: [TimerInterval]
    private(set) var currentIntervalIndex = 0
    private(set) var remainingDuration: TimeInterval
    private(set) var isRunning = false

    init(intervals: [TimerInterval]) {
        let runnableIntervals = intervals.filter { $0.durationSeconds > 0 }
        self.intervals = runnableIntervals
        remainingDuration = TimeInterval(runnableIntervals.first?.durationSeconds ?? 0)
    }

    var currentInterval: TimerInterval? {
        guard intervals.indices.contains(currentIntervalIndex) else { return nil }
        return intervals[currentIntervalIndex]
    }

    var nextInterval: TimerInterval? {
        let nextIndex = currentIntervalIndex + 1
        guard intervals.indices.contains(nextIndex) else { return nil }
        return intervals[nextIndex]
    }

    var wholeRemainingDuration: TimeInterval {
        let futureDuration = intervals
            .dropFirst(currentIntervalIndex + 1)
            .reduce(0) { $0 + TimeInterval($1.durationSeconds) }
        return remainingDuration + futureDuration
    }

    var remainingIntervalDurations: [TimeInterval] {
        guard currentInterval != nil else { return [] }
        return [remainingDuration] + intervals
            .dropFirst(currentIntervalIndex + 1)
            .map { TimeInterval($0.durationSeconds) }
    }

    var intervalProgress: Double {
        guard let currentInterval, currentInterval.durationSeconds > 0 else { return 0 }
        let progress = 1 - (remainingDuration / TimeInterval(currentInterval.durationSeconds))
        return min(max(progress, 0), 1)
    }

    mutating func start() {
        guard !intervals.isEmpty, remainingDuration > 0 else { return }
        isRunning = true
    }

    mutating func pause() {
        isRunning = false
    }

    mutating func reset(intervals: [TimerInterval]) {
        self = TimerRunState(intervals: intervals)
    }

    mutating func advance(by elapsedDuration: TimeInterval) -> [TimerRunEvent] {
        guard isRunning, elapsedDuration > 0 else { return [] }

        var events: [TimerRunEvent] = []
        var elapsedRemaining = elapsedDuration

        while elapsedRemaining >= remainingDuration {
            elapsedRemaining -= remainingDuration
            let nextIndex = currentIntervalIndex + 1

            guard intervals.indices.contains(nextIndex) else {
                remainingDuration = 0
                isRunning = false
                events.append(.completed)
                return events
            }

            currentIntervalIndex = nextIndex
            remainingDuration = TimeInterval(intervals[nextIndex].durationSeconds)
            events.append(.intervalTransition)
        }

        remainingDuration -= elapsedRemaining
        return events
    }
}
