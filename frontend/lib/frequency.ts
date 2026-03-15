export type FrequencyPeriod = "day" | "week" | "month";

export const PERIOD_DIVISORS: Record<FrequencyPeriod, number> = {
  day: 1,
  week: 7,
  month: 30,
};

export function formatFrequencySummary(frequency: number | null, prefix?: string): string | null {
  if (frequency == null) return null;
  const label = prefix ? ` ${prefix}/` : "/";
  if (frequency >= 1) {
    const formatted = frequency.toFixed(2).replace(/\.?0+$/, "");
    return `${formatted}${label}day`;
  }
  const weekly = frequency * 7;
  if (weekly >= 1) {
    const formatted = weekly.toFixed(2).replace(/\.?0+$/, "");
    return `${formatted}${label}week`;
  }
  const monthly = frequency * 30;
  const formatted = monthly.toFixed(2).replace(/\.?0+$/, "");
  return `${formatted}${label}month`;
}

export function toDailyFrequency(value: number, period: FrequencyPeriod): number {
  return value / PERIOD_DIVISORS[period];
}

export function fromDailyFrequency(dailyValue: number): { value: number; period: FrequencyPeriod } {
  if (dailyValue >= 1) {
    return { value: dailyValue, period: "day" };
  }
  if (dailyValue * 7 >= 1) {
    return { value: dailyValue * 7, period: "week" };
  }
  return { value: dailyValue * 30, period: "month" };
}
