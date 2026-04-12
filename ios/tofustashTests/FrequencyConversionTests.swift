import Foundation
import Testing
@testable import tofustash

struct FrequencyConversionTests {

    // MARK: - toDailyRate

    // Behaviour: When a user sets a habit to "3 times per day", the internal daily
    // rate is stored as 3.0 (no conversion needed).
    @Test func toDailyRateDay() {
        let rate = FrequencyConversion.toDailyRate(value: 3.0, period: .day)
        #expect(rate == 3.0)
    }

    // Behaviour: When a user sets a habit to "3 times per week", the daily rate
    // is calculated as 3/7 for internal storage.
    @Test func toDailyRateWeek() {
        let rate = FrequencyConversion.toDailyRate(value: 3.0, period: .week)
        #expect(abs(rate - 3.0 / 7.0) < 0.0001)
    }

    // Behaviour: When a user sets a habit to "3 times per month", the daily rate
    // is calculated as 3/30 for internal storage.
    @Test func toDailyRateMonth() {
        let rate = FrequencyConversion.toDailyRate(value: 3.0, period: .month)
        #expect(abs(rate - 3.0 / 30.0) < 0.0001)
    }

    // MARK: - fromDailyRate

    // Behaviour: When displaying a frequency of 3.0/day, the user sees "3/day"
    // (daily rate >= 1 is shown in days).
    @Test func fromDailyRateDay() {
        let (value, period) = FrequencyConversion.fromDailyRate(3.0)
        #expect(value == 3.0)
        #expect(period == .day)
    }

    // Behaviour: When displaying a frequency of 1/7 daily, the user sees "1/week"
    // instead of a confusing decimal like "0.14/day".
    @Test func fromDailyRateWeek() {
        let daily = 1.0 / 7.0
        let (value, period) = FrequencyConversion.fromDailyRate(daily)
        #expect(abs(value - 1.0) < 0.0001)
        #expect(period == .week)
    }

    // Behaviour: When displaying a frequency of 1/30 daily, the user sees "1/month"
    // instead of a confusing fraction.
    @Test func fromDailyRateMonth() {
        let daily = 1.0 / 30.0
        let (value, period) = FrequencyConversion.fromDailyRate(daily)
        #expect(abs(value - 1.0) < 0.0001)
        #expect(period == .month)
    }

    // Behaviour: When displaying 0.5/day, the user sees "3.5/week" because the
    // system picks the most readable period (weekly value >= 1).
    @Test func fromDailyRateChoosesBestPeriod() {
        let (value, period) = FrequencyConversion.fromDailyRate(0.5)
        #expect(abs(value - 3.5) < 0.0001)
        #expect(period == .week)
    }

    // MARK: - formatSummary

    // Behaviour: When a habit has a daily frequency, the user sees a compact
    // summary like "3/day" in the habit list.
    @Test func formatSummaryDay() {
        let summary = FrequencyConversion.formatSummary(3.0)
        #expect(summary == "3/day")
    }

    // Behaviour: When a habit has a weekly frequency, the summary shows "3/week".
    @Test func formatSummaryWeek() {
        let summary = FrequencyConversion.formatSummary(3.0 / 7.0)
        #expect(summary == "3/week")
    }

    // Behaviour: When a habit has a monthly frequency, the summary shows "1/month".
    @Test func formatSummaryMonth() {
        let summary = FrequencyConversion.formatSummary(1.0 / 30.0)
        #expect(summary == "1/month")
    }

    // Behaviour: When a habit has no frequency set, no summary is displayed.
    @Test func formatSummaryNilReturnsNil() {
        let summary = FrequencyConversion.formatSummary(nil)
        #expect(summary == nil)
    }

    // Behaviour: Frequency summaries show clean numbers (e.g. "1/day" not "1.00/day")
    // so the UI looks tidy.
    @Test func formatSummaryRemovesTrailingZeros() {
        let summary = FrequencyConversion.formatSummary(1.0)
        #expect(summary == "1/day")
    }

}
