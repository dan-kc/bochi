import { describe, test, expect } from "vitest";
import { parseSyncState, getDefaultSyncState } from "./syncStorage";

describe("parseSyncState", () => {
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
});

describe("getDefaultSyncState", () => {
  test("returns correct default structure", () => {
    const defaultState = getDefaultSyncState();

    expect(defaultState.lastSync).toBeNull();
    expect(defaultState.dirty).toEqual({
      habits: [],
      trades: [],
      tags: [],
      habitTags: [],
      rewards: [],
      rewardTags: [],
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
