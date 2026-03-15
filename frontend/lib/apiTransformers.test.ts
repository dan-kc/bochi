import { describe, test, expect } from "vitest";
import {
  transformHabitFromApi,
  transformTradeFromApi,
  transformTagFromApi,
  transformHabitTagFromApi,
  transformRewardFromApi,
  transformRewardTagFromApi,
  transformSyncResponse,
} from "./apiTransformers";
import type { ApiSyncResponse } from "./apiTransformers";

describe("transformHabitFromApi", () => {
  test("converts camelCase to snake_case", () => {
    const result = transformHabitFromApi({
      id: "h1",
      name: "Exercise",
      description: "Daily workout",
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-02T00:00:00Z",
      deletedAt: null,
      minDailyFrequency: 1.5,
      difficultyRank: "B",
    });

    expect(result).toEqual({
      id: "h1",
      user_id: "",
      name: "Exercise",
      description: "Daily workout",
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-02T00:00:00Z",
      deleted_at: null,
      min_daily_frequency: 1.5,
      difficulty_rank: "B",
    });
  });

  test("handles null optional fields", () => {
    const result = transformHabitFromApi({
      id: "h2",
      name: "Read",
      description: "",
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-01T00:00:00Z",
      deletedAt: "2024-02-01T00:00:00Z",
      minDailyFrequency: null,
      difficultyRank: null,
    });

    expect(result.min_daily_frequency).toBeNull();
    expect(result.difficulty_rank).toBeNull();
    expect(result.deleted_at).toBe("2024-02-01T00:00:00Z");
  });
});

describe("transformTradeFromApi", () => {
  test("converts camelCase to snake_case", () => {
    const result = transformTradeFromApi({
      id: "t1",
      habitId: "h1",
      rewardId: null,
      amount: 10,
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-01T00:00:00Z",
      deletedAt: null,
    });

    expect(result).toEqual({
      id: "t1",
      user_id: "",
      habit_id: "h1",
      reward_id: null,
      amount: 10,
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T00:00:00Z",
      deleted_at: null,
    });
  });
});

describe("transformTagFromApi", () => {
  test("converts colorHex to color_hex", () => {
    const result = transformTagFromApi({
      id: "tag1",
      name: "Health",
      colorHex: "#FF0000FF",
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-01T00:00:00Z",
      deletedAt: null,
    });

    expect(result.color_hex).toBe("#FF0000FF");
    expect(result.user_id).toBe("");
  });
});

describe("transformHabitTagFromApi", () => {
  test("converts camelCase to snake_case", () => {
    const result = transformHabitTagFromApi({
      habitId: "h1",
      tagId: "t1",
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-01T00:00:00Z",
      deletedAt: null,
    });

    expect(result).toEqual({
      habit_id: "h1",
      tag_id: "t1",
      user_id: "",
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T00:00:00Z",
      deleted_at: null,
    });
  });
});

describe("transformRewardFromApi", () => {
  test("converts camelCase to snake_case", () => {
    const result = transformRewardFromApi({
      id: "r1",
      name: "Ice cream",
      description: "Treat yourself",
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-01T00:00:00Z",
      deletedAt: null,
      maxDailyFrequency: 2,
      damageRank: "C",
    });

    expect(result).toEqual({
      id: "r1",
      user_id: "",
      name: "Ice cream",
      description: "Treat yourself",
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T00:00:00Z",
      deleted_at: null,
      max_daily_frequency: 2,
      damage_rank: "C",
    });
  });
});

describe("transformRewardTagFromApi", () => {
  test("converts camelCase to snake_case", () => {
    const result = transformRewardTagFromApi({
      rewardId: "r1",
      tagId: "t1",
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-01T00:00:00Z",
      deletedAt: null,
    });

    expect(result).toEqual({
      reward_id: "r1",
      tag_id: "t1",
      user_id: "",
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T00:00:00Z",
      deleted_at: null,
    });
  });
});

describe("transformSyncResponse", () => {
  test("transforms complete sync response", () => {
    const apiResponse: ApiSyncResponse = {
      habits: [{
        id: "h1", name: "Exercise", description: "",
        createdAt: "2024-01-01T00:00:00Z", updatedAt: "2024-01-01T00:00:00Z",
        deletedAt: null, minDailyFrequency: 1, difficultyRank: null,
      }],
      trades: [{
        id: "t1", habitId: "h1", rewardId: null, amount: 5,
        createdAt: "2024-01-01T00:00:00Z", updatedAt: "2024-01-01T00:00:00Z",
        deletedAt: null,
      }],
      tags: [{
        id: "tag1", name: "Health", colorHex: "#00FF00FF",
        createdAt: "2024-01-01T00:00:00Z", updatedAt: "2024-01-01T00:00:00Z",
        deletedAt: null,
      }],
      habitTags: [{
        habitId: "h1", tagId: "tag1",
        createdAt: "2024-01-01T00:00:00Z", updatedAt: "2024-01-01T00:00:00Z",
        deletedAt: null,
      }],
      rewards: [{
        id: "r1", name: "Treat", description: "",
        createdAt: "2024-01-01T00:00:00Z", updatedAt: "2024-01-01T00:00:00Z",
        deletedAt: null, maxDailyFrequency: null, damageRank: null,
      }],
      rewardTags: [{
        rewardId: "r1", tagId: "tag1",
        createdAt: "2024-01-01T00:00:00Z", updatedAt: "2024-01-01T00:00:00Z",
        deletedAt: null,
      }],
      balance: { tofuBalance: 100 },
      serverTime: "2024-01-01T12:00:00Z",
      email: "test@example.com",
      isPremium: false,
      generalDifficulty: 5,
    };

    const result = transformSyncResponse(apiResponse);

    expect(result.habits).toHaveLength(1);
    expect(result.habits[0].id).toBe("h1");
    expect(result.habits[0].min_daily_frequency).toBe(1);
    expect(result.trades).toHaveLength(1);
    expect(result.trades[0].habit_id).toBe("h1");
    expect(result.tags).toHaveLength(1);
    expect(result.tags[0].color_hex).toBe("#00FF00FF");
    expect(result.habitTags).toHaveLength(1);
    expect(result.habitTags[0].habit_id).toBe("h1");
    expect(result.rewards).toHaveLength(1);
    expect(result.rewardTags).toHaveLength(1);
    expect(result.rewardTags[0].reward_id).toBe("r1");
    expect(result.balance.tofu_balance).toBe(100);
    expect(result.server_time).toBe("2024-01-01T12:00:00Z");
    expect(result.email).toBe("test@example.com");
    expect(result.isPremium).toBe(false);
    expect(result.generalDifficulty).toBe(5);
  });

  test("handles empty arrays", () => {
    const apiResponse: ApiSyncResponse = {
      habits: [],
      trades: [],
      tags: [],
      habitTags: [],
      rewards: [],
      rewardTags: [],
      balance: { tofuBalance: 0 },
      serverTime: "2024-01-01T00:00:00Z",
      email: null,
      isPremium: false,
      generalDifficulty: 0,
    };

    const result = transformSyncResponse(apiResponse);
    expect(result.habits).toEqual([]);
    expect(result.trades).toEqual([]);
    expect(result.tags).toEqual([]);
    expect(result.habitTags).toEqual([]);
    expect(result.rewards).toEqual([]);
    expect(result.rewardTags).toEqual([]);
  });
});
