import { describe, test, expect } from "vitest";
import { formatShortDate } from "./dateUtils";

describe("formatShortDate", () => {
  test("formats a date string to short format", () => {
    const result = formatShortDate("2024-06-15T08:00:00Z");
    // The output depends on the locale but should include month and day
    expect(result).toMatch(/Jun/);
    expect(result).toMatch(/15/);
  });

  test("formats another date", () => {
    const result = formatShortDate("2024-01-01T00:00:00Z");
    expect(result).toMatch(/Jan/);
    expect(result).toMatch(/1/);
  });

  test("handles different date formats", () => {
    const result = formatShortDate("2024-12-25T12:00:00Z");
    expect(result).toMatch(/Dec/);
    expect(result).toMatch(/25/);
  });
});
