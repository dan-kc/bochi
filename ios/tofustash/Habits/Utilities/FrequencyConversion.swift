import Foundation

// FrequencyPeriod matches the language the user sees in the UI. Internally the
// app stores one normalized "times per day" value, but forms and summaries use
// day/week/month because that is easier for people to reason about.
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

    // Small display label used in pills and summaries.
    var label: String { rawValue }
}

// Converts between stored daily rates and the user-facing values shown in the UI.
//
// Caseless enum = namespace (can't be instantiated). Like a TS module
// that only exports functions.
enum FrequencyConversion {
    private static let integerTolerance = 0.0001

    // Converts a user-entered value + period to a daily rate.
    //   3 times per week → 3 / 7 ≈ 0.4286
    // Like toDailyFrequency() in the TS version.
    static func toDailyRate(value: Double, period: FrequencyPeriod) -> Double {
        value / period.divisor
    }

    private static func isWholeNumber(_ value: Double) -> Bool {
        abs(value.rounded() - value) < integerTolerance
    }

    // Picks the friendliest period for display so the user sees "1/week"
    // instead of awkward decimals when possible.
    static func fromDailyRate(_ daily: Double) -> (value: Double, period: FrequencyPeriod) {
        if daily >= 1, isWholeNumber(daily) {
            return (daily, .day)
        }

        let weekly = daily * FrequencyPeriod.week.divisor
        if weekly >= 1, isWholeNumber(weekly) {
            return (weekly, .week)
        }

        let monthly = daily * FrequencyPeriod.month.divisor
        if monthly >= 1, isWholeNumber(monthly) {
            return (monthly, .month)
        }

        if daily >= 1 {
            return (daily, .day)
        }
        if weekly >= 1 {
            return (weekly, .week)
        }
        return (monthly, .month)
    }

    // Compact summary used in habit pills and list rows.
    static func formatSummary(_ daily: Double?) -> String? {
        guard let daily = daily else { return nil }

        let (value, period) = fromDailyRate(daily)

        let formatted = formatNumber(value)

        return "\(formatted)/\(period.label)"
    }

    // Swift's string formatting returns fixed decimal places, so this helper
    // trims the UI back to the shortest readable form.
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
