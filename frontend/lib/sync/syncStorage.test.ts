import { describe, test, expect } from "vitest";
import { parseSyncState, getDefaultSyncState } from "./syncStorage";

describe("parseSyncState", () => {
  describe("migration from old schemas", () => {
    test("migrates tasks to habits (rename migration)", () => {
      const oldData = JSON.stringify({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: {
          tasks: ["task-1", "task-2", "task-3"],
          trades: ["trade-1"],
        },
      });
      const result = parseSyncState(oldData);

      expect(result.dirty.habits).toEqual(["task-1", "task-2", "task-3"]);
      expect(result.dirty.trades).toEqual(["trade-1"]);
      // tasks key should be removed
      expect("tasks" in result.dirty).toBe(false);
    });

    test("handles missing dirty.trades array", () => {
      const oldData = JSON.stringify({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: {
          habits: ["habit-1"],
        },
      });
      const result = parseSyncState(oldData);

      expect(result.dirty.habits).toEqual(["habit-1"]);
      expect(result.dirty.trades).toEqual([]);
    });

    test("handles missing dirty.habits array", () => {
      const oldData = JSON.stringify({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: {
          trades: ["trade-1"],
        },
      });
      const result = parseSyncState(oldData);

      expect(result.dirty.habits).toEqual([]);
      expect(result.dirty.trades).toEqual(["trade-1"]);
    });

    test("handles both tasks migration and missing trades", () => {
      const oldData = JSON.stringify({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: {
          tasks: ["task-1"],
        },
      });
      const result = parseSyncState(oldData);

      expect(result.dirty.habits).toEqual(["task-1"]);
      expect(result.dirty.trades).toEqual([]);
    });
  });

  describe("handling null/empty input", () => {
    test("returns default state for null input", () => {
      const result = parseSyncState(null);

      expect(result).toEqual(getDefaultSyncState());
      expect(result.lastSync).toBeNull();
      expect(result.dirty.habits).toEqual([]);
      expect(result.dirty.trades).toEqual([]);
    });

    test("returns default state for empty string", () => {
      const result = parseSyncState("");

      expect(result).toEqual(getDefaultSyncState());
    });
  });

  describe("handling invalid JSON", () => {
    test("returns default state for malformed JSON", () => {
      const result = parseSyncState("not valid json {{{");

      expect(result).toEqual(getDefaultSyncState());
    });

    test("returns default state for partial JSON", () => {
      const result = parseSyncState('{"lastSync":');

      expect(result).toEqual(getDefaultSyncState());
    });
  });

  describe("preserving valid state", () => {
    test("preserves complete valid state", () => {
      const validState = {
        lastSync: "2024-06-15T12:00:00Z",
        dirty: {
          habits: ["habit-1", "habit-2"],
          trades: ["trade-1"],
        },
      };
      const result = parseSyncState(JSON.stringify(validState));

      expect(result).toEqual(validState);
    });

    test("preserves null lastSync", () => {
      const stateWithNullSync = {
        lastSync: null,
        dirty: {
          habits: [],
          trades: [],
        },
      };
      const result = parseSyncState(JSON.stringify(stateWithNullSync));

      expect(result.lastSync).toBeNull();
    });

    test("preserves empty dirty arrays", () => {
      const emptyDirtyState = {
        lastSync: "2024-01-01T00:00:00Z",
        dirty: {
          habits: [],
          trades: [],
        },
      };
      const result = parseSyncState(JSON.stringify(emptyDirtyState));

      expect(result.dirty.habits).toEqual([]);
      expect(result.dirty.trades).toEqual([]);
    });
  });

  describe("edge cases", () => {
    test("handles deeply nested extra data gracefully", () => {
      const dataWithExtras = JSON.stringify({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: {
          habits: ["h1"],
          trades: ["t1"],
        },
        extraField: {
          nested: {
            data: "ignored",
          },
        },
        oldSyncVersion: 1,
      });
      const result = parseSyncState(dataWithExtras);

      expect(result.dirty.habits).toEqual(["h1"]);
      expect(result.dirty.trades).toEqual(["t1"]);
    });

    test("handles unicode in habit IDs", () => {
      const unicodeData = JSON.stringify({
        lastSync: null,
        dirty: {
          habits: ["habit-émoji-🎯", "タスク-1"],
          trades: [],
        },
      });
      const result = parseSyncState(unicodeData);

      expect(result.dirty.habits).toContain("habit-émoji-🎯");
      expect(result.dirty.habits).toContain("タスク-1");
    });

    test("handles very large dirty arrays", () => {
      const largeArray = Array.from({ length: 1000 }, (_, i) => `habit-${i}`);
      const largeData = JSON.stringify({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: {
          habits: largeArray,
          trades: [],
        },
      });
      const result = parseSyncState(largeData);

      expect(result.dirty.habits).toHaveLength(1000);
      expect(result.dirty.habits[0]).toBe("habit-0");
      expect(result.dirty.habits[999]).toBe("habit-999");
    });
  });
});

describe("getDefaultSyncState", () => {
  test("returns correct default structure", () => {
    const defaultState = getDefaultSyncState();

    expect(defaultState.lastSync).toBeNull();
    expect(defaultState.dirty).toEqual({
      habits: [],
      trades: [],
    });
  });

  test("returns new object each time (no mutation issues)", () => {
    const state1 = getDefaultSyncState();
    const state2 = getDefaultSyncState();

    state1.dirty.habits.push("test");

    expect(state2.dirty.habits).toEqual([]);
    expect(state1).not.toBe(state2);
  });
});
