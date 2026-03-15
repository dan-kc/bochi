import { describe, test, expect } from "vitest";
import {
  formatFrequencySummary,
  toDailyFrequency,
  fromDailyFrequency,
  PERIOD_DIVISORS,
} from "./frequency";

describe("PERIOD_DIVISORS", () => {
  test("has correct values", () => {
    expect(PERIOD_DIVISORS.day).toBe(1);
    expect(PERIOD_DIVISORS.week).toBe(7);
    expect(PERIOD_DIVISORS.month).toBe(30);
  });
});

describe("formatFrequencySummary", () => {
  test("returns null for null input", () => {
    expect(formatFrequencySummary(null)).toBeNull();
  });

  test("formats daily frequency >= 1", () => {
    expect(formatFrequencySummary(1)).toBe("1/day");
    expect(formatFrequencySummary(3)).toBe("3/day");
    expect(formatFrequencySummary(1.5)).toBe("1.5/day");
  });

  test("formats weekly frequency", () => {
    expect(formatFrequencySummary(1 / 7)).toBe("1/week");
    expect(formatFrequencySummary(3 / 7)).toBe("3/week");
  });

  test("formats monthly frequency", () => {
    expect(formatFrequencySummary(1 / 30)).toBe("1/month");
    expect(formatFrequencySummary(2 / 30)).toBe("2/month");
  });

  test("formats with prefix", () => {
    expect(formatFrequencySummary(1, "max")).toBe("1 max/day");
    expect(formatFrequencySummary(1 / 7, "max")).toBe("1 max/week");
    expect(formatFrequencySummary(1 / 30, "max")).toBe("1 max/month");
  });

  test("strips trailing zeros", () => {
    expect(formatFrequencySummary(2.0)).toBe("2/day");
    expect(formatFrequencySummary(1.10)).toBe("1.1/day");
  });
});

describe("toDailyFrequency", () => {
  test("converts day to daily (no change)", () => {
    expect(toDailyFrequency(3, "day")).toBe(3);
  });

  test("converts week to daily", () => {
    expect(toDailyFrequency(7, "week")).toBe(1);
    expect(toDailyFrequency(1, "week")).toBeCloseTo(1 / 7);
  });

  test("converts month to daily", () => {
    expect(toDailyFrequency(30, "month")).toBe(1);
    expect(toDailyFrequency(1, "month")).toBeCloseTo(1 / 30);
  });
});

describe("fromDailyFrequency", () => {
  test("returns day for daily >= 1", () => {
    expect(fromDailyFrequency(1)).toEqual({ value: 1, period: "day" });
    expect(fromDailyFrequency(3)).toEqual({ value: 3, period: "day" });
  });

  test("returns week for weekly >= 1", () => {
    const result = fromDailyFrequency(1 / 7);
    expect(result.period).toBe("week");
    expect(result.value).toBeCloseTo(1);
  });

  test("returns month for small frequencies", () => {
    const result = fromDailyFrequency(1 / 30);
    expect(result.period).toBe("month");
    expect(result.value).toBeCloseTo(1);
  });
});
