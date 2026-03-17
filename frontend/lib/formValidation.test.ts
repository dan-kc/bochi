import { describe, test, expect } from "vitest";
import { z } from "zod";
import { parseZodErrors } from "./formValidation";

describe("parseZodErrors", () => {
  test("maps single field error", () => {
    const schema = z.object({
      name: z.string().min(1, "Name is required"),
    });

    const result = schema.safeParse({ name: "" });
    if (result.success) throw new Error("Expected failure");

    const errors = parseZodErrors(result.error);
    expect(errors).toEqual({ name: ["Name is required"] });
  });

  test("maps multiple field errors", () => {
    const schema = z.object({
      name: z.string().min(1, "Name is required"),
      description: z.string().max(5, "Too long"),
    });

    const result = schema.safeParse({ name: "", description: "too long text" });
    if (result.success) throw new Error("Expected failure");

    const errors = parseZodErrors(result.error);
    expect(errors.name).toEqual(["Name is required"]);
    expect(errors.description).toEqual(["Too long"]);
  });

  test("groups multiple errors for same field", () => {
    const schema = z.object({
      value: z.number().gt(0, "Must be positive").lte(10, "Must be <= 10"),
    });

    const result = schema.safeParse({ value: -1 });
    if (result.success) throw new Error("Expected failure");

    const errors = parseZodErrors(result.error);
    expect(errors.value).toContain("Must be positive");
  });

  test("uses 'general' for root-level errors", () => {
    const schema = z.string().min(1, "Required");

    const result = schema.safeParse("");
    if (result.success) throw new Error("Expected failure");

    const errors = parseZodErrors(result.error);
    expect(errors.general).toEqual(["Required"]);
  });

  test("handles nested path", () => {
    const schema = z.object({
      nested: z.object({
        field: z.string().min(1, "Required"),
      }),
    });

    const result = schema.safeParse({ nested: { field: "" } });
    if (result.success) throw new Error("Expected failure");

    const errors = parseZodErrors(result.error);
    expect(errors["nested.field"]).toEqual(["Required"]);
  });
});
