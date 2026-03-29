import { describe, test, expect } from "vitest";
import { getVisiblePills, type PillConfig } from "./formUtils";

describe("getVisiblePills", () => {
  const basePillConfig: PillConfig = {
    description: "",
    tags: [],
    frequency: null,
    frequencyLabel: "Frequency",
    rankLabel: "Difficulty",
    isCreateMode: false,
  };

  test("shows all pills when nothing is set in edit mode", () => {
    const pills = getVisiblePills(basePillConfig);
    const keys = pills.map((p) => p.key);
    expect(keys).toEqual(["description", "tags", "frequency", "rank"]);
  });

  test("hides description pill when description is set", () => {
    const pills = getVisiblePills({ ...basePillConfig, description: "Some text" });
    const keys = pills.map((p) => p.key);
    expect(keys).not.toContain("description");
  });

  test("hides tags pill when tags are assigned", () => {
    const pills = getVisiblePills({ ...basePillConfig, tags: ["tag1", "tag2"] });
    const keys = pills.map((p) => p.key);
    expect(keys).not.toContain("tags");
  });

  test("frequency pill always visible", () => {
    const pills = getVisiblePills({ ...basePillConfig, frequency: null });
    const freq = pills.find((p) => p.key === "frequency");
    expect(freq).toBeDefined();
    expect(freq!.label).toBe("Frequency");
    expect(freq!.isSet).toBe(false);
  });

  test("frequency pill shows value when set", () => {
    const pills = getVisiblePills({ ...basePillConfig, frequency: "3/week" });
    const freq = pills.find((p) => p.key === "frequency");
    expect(freq).toBeDefined();
    expect(freq!.label).toBe("3/week");
    expect(freq!.isSet).toBe(true);
  });

  test("rank pill always visible with label", () => {
    const pills = getVisiblePills(basePillConfig);
    const rank = pills.find((p) => p.key === "rank");
    expect(rank).toBeDefined();
    expect(rank!.label).toBe("Difficulty");
    expect(rank!.isSet).toBe(false);
  });

  test("uses custom labels", () => {
    const pills = getVisiblePills({
      ...basePillConfig,
      frequencyLabel: "Max Frequency",
      rankLabel: "Damage",
    });
    const freq = pills.find((p) => p.key === "frequency");
    const rank = pills.find((p) => p.key === "rank");
    expect(freq!.label).toBe("Max Frequency");
    expect(rank!.label).toBe("Damage");
  });

  test("description pill shows 'Description' label when unset", () => {
    const pills = getVisiblePills(basePillConfig);
    const desc = pills.find((p) => p.key === "description");
    expect(desc).toBeDefined();
    expect(desc!.label).toBe("Description");
    expect(desc!.isSet).toBe(false);
  });

  test("tags pill shows 'Tags' label when unset in edit mode", () => {
    const pills = getVisiblePills(basePillConfig);
    const tags = pills.find((p) => p.key === "tags");
    expect(tags).toBeDefined();
    expect(tags!.label).toBe("Tags");
    expect(tags!.isSet).toBe(false);
  });
});
