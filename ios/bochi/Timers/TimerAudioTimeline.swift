import Foundation

nonisolated enum TimerAudioCueKind: Equatable, Sendable {
    case countdown
    case transition
}

nonisolated struct TimerAudioCue: Equatable, Sendable {
    let kind: TimerAudioCueKind
    let offset: TimeInterval
}

nonisolated enum TimerAudioTimeline {
    static func elapsedDuration(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> TimeInterval {
        let components = start.duration(to: end).components
        return Double(components.seconds)
            + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }

    static func cues(intervalDurations: [TimeInterval]) -> [TimerAudioCue] {
        let durations = intervalDurations.filter { $0 > 0 && $0.isFinite }
        var cues: [TimerAudioCue] = []
        var intervalStart: TimeInterval = 0

        for (index, duration) in durations.enumerated() {
            for secondsRemaining in stride(from: 3, through: 1, by: -1) {
                let offset = intervalStart + duration - TimeInterval(secondsRemaining)
                if offset >= intervalStart {
                    cues.append(TimerAudioCue(kind: .countdown, offset: offset))
                }
            }

            intervalStart += duration
            if index < durations.count - 1 {
                cues.append(TimerAudioCue(kind: .transition, offset: intervalStart))
            }
        }

        return cues
    }

    static func remainingIntervals(
        intervalDurations: [TimeInterval],
        after elapsedDuration: TimeInterval
    ) -> [TimeInterval] {
        let durations = intervalDurations.filter { $0 > 0 && $0.isFinite }
        var elapsedRemaining = max(elapsedDuration, 0)

        for (index, duration) in durations.enumerated() {
            if elapsedRemaining < duration {
                return [duration - elapsedRemaining] + durations.dropFirst(index + 1)
            }
            elapsedRemaining -= duration
        }

        return []
    }
}
