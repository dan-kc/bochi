import Foundation

// FrequencyPeriod represents how the user thinks about frequency — per day,
// per week, or per month. Internally, frequency is always stored as a daily rate
// (times per day), but the UI lets users enter "3 times per week" etc.
//
// This is an enum — like a union type in TypeScript: "day" | "week" | "month",
// but with attached behavior (computed properties). CaseIterable lets you loop
// over all cases (like Object.values() on a TS enum).
enum FrequencyPeriod: String, CaseIterable, Equatable {
    case day, week, month

    // Each period's divisor converts the user's value to a daily rate:
    //   dailyRate = value / divisor
    // E.g. 3 times per week → 3 / 7 = 0.4286 times per day
    var divisor: Double {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        }
    }

    // Human-readable label for display in the UI
    var label: String { rawValue }
}

// Pure functions for converting between daily rates and user-friendly
// period-based values. Port of frontend/lib/frequency.ts.
//
// Caseless enum = namespace (can't be instantiated). Like a TS module
// that only exports functions.
enum FrequencyConversion {

    // Converts a user-entered value + period to a daily rate.
    //   3 times per week → 3 / 7 ≈ 0.4286
    // Like toDailyFrequency() in the TS version.
    static func toDailyRate(value: Double, period: FrequencyPeriod) -> Double {
        value / period.divisor
    }

    // Converts a daily rate back to the most natural period for display.
    // Picks the period that gives the cleanest number:
    //   - If daily rate >= 1 → show as per day
    //   - If weekly rate >= 1 → show as per week
    //   - Otherwise → show as per month
    // Like fromDailyFrequency() in the TS version.
    static func fromDailyRate(_ daily: Double) -> (value: Double, period: FrequencyPeriod) {
        if daily >= 1 {
            return (daily, .day)
        }
        let weekly = daily * 7
        if weekly >= 1 {
            return (weekly, .week)
        }
        return (daily * 30, .month)
    }

    // Formats a daily rate as a human-readable summary string.
    // Returns nil if the input is nil (frequency not set).
    //   3.0 → "3/day"
    //   0.4286 → "3/week"
    //   nil → nil
    // Like formatFrequencySummary() in the TS version.
    static func formatSummary(_ daily: Double?) -> String? {
        guard let daily = daily else { return nil }

        let (value, period) = fromDailyRate(daily)

        // Format: remove trailing zeros (e.g. "3.00" → "3", "1.50" → "1.5")
        // In JS this was `.toFixed(2).replace(/\.?0+$/, "")`.
        // In Swift, we format to 2 decimal places then strip trailing zeros.
        let formatted = formatNumber(value)

        return "\(formatted)/\(period.label)"
    }

    // Formats a Double by removing unnecessary trailing zeros.
    //   3.0 → "3"
    //   1.5 → "1.5"
    //   0.43 → "0.43"
    static func formatNumber(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        // Drop trailing zeros and unnecessary decimal point
        var result = formatted
        while result.hasSuffix("0") {
            result = String(result.dropLast())
        }
        if result.hasSuffix(".") {
            result = String(result.dropLast())
        }
        return result
    }
}
