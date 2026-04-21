import Foundation

// Shared duration copy used by the new duration and lockout inputs. The app
// stores integer seconds, but users think in minutes and hours.
enum DurationFormatting {
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    static func summary(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return formatter.string(from: TimeInterval(seconds))
    }

    static func countdown(secondsRemaining: Int) -> String {
        summary(seconds: max(0, secondsRemaining)) ?? "0s"
    }
}

