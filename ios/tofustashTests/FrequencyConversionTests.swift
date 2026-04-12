import Foundation
import Testing
@testable import tofustash

struct FrequencyConversionTests {

    // MARK: - toDailyRate

    @Test func toDailyRateDay() {
        // 3 times per day = 3.0 daily rate (divisor is 1)
        let rate = FrequencyConversion.toDailyRate(value: 3.0, period: .day)
        #expect(rate == 3.0)
    }

    @Test func toDailyRateWeek() {
        // 3 times per week = 3/7 daily rate
        let rate = FrequencyConversion.toDailyRate(value: 3.0, period: .week)
        #expect(abs(rate - 3.0 / 7.0) < 0.0001)
    }

    @Test func toDailyRateMonth() {
        // 3 times per month = 3/30 daily rate
        let rate = FrequencyConversion.toDailyRate(value: 3.0, period: .month)
        #expect(abs(rate - 3.0 / 30.0) < 0.0001)
    }

    // MARK: - fromDailyRate

    @Test func fromDailyRateDay() {
        // 3.0 daily → show as 3/day (>= 1 → use day)
        let (value, period) = FrequencyConversion.fromDailyRate(3.0)
        #expect(value == 3.0)
        #expect(period == .day)
    }

    @Test func fromDailyRateWeek() {
        // 1/7 daily → 1/week (< 1 daily, but weekly >= 1)
        let daily = 1.0 / 7.0
        let (value, period) = FrequencyConversion.fromDailyRate(daily)
        #expect(abs(value - 1.0) < 0.0001)
        #expect(period == .week)
    }

    @Test func fromDailyRateMonth() {
        // 1/30 daily → 1/month (< 1 daily, < 1 weekly, monthly >= 1)
        let daily = 1.0 / 30.0
        let (value, period) = FrequencyConversion.fromDailyRate(daily)
        #expect(abs(value - 1.0) < 0.0001)
        #expect(period == .month)
    }

    @Test func fromDailyRateChoosesBestPeriod() {
        // 0.5 daily → 3.5/week (< 1 daily, but weekly >= 1)
        let (value, period) = FrequencyConversion.fromDailyRate(0.5)
        #expect(abs(value - 3.5) < 0.0001)
        #expect(period == .week)
    }

    // MARK: - formatSummary

    @Test func formatSummaryDay() {
        let summary = FrequencyConversion.formatSummary(3.0)
        #expect(summary == "3/day")
    }

    @Test func formatSummaryWeek() {
        let summary = FrequencyConversion.formatSummary(3.0 / 7.0)
        #expect(summary == "3/week")
    }

    @Test func formatSummaryMonth() {
        let summary = FrequencyConversion.formatSummary(1.0 / 30.0)
        #expect(summary == "1/month")
    }

    @Test func formatSummaryNilReturnsNil() {
        let summary = FrequencyConversion.formatSummary(nil)
        #expect(summary == nil)
    }

    @Test func formatSummaryRemovesTrailingZeros() {
        // 1.0 per day should show as "1/day", not "1.00/day"
        let summary = FrequencyConversion.formatSummary(1.0)
        #expect(summary == "1/day")
    }

}
