import type { Habit } from "./habit";
import type { Trade } from "./trade";
import type { Tag } from "./tag";
import type { HabitTag } from "./habitTag";
import type { Reward } from "./reward";
import type { RewardTag } from "./rewardTag";
import type { SyncResponse } from "./sync/types";

// ============ API Response Types (camelCase from server) ============

export interface ApiHabit {
  id: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  minDailyFrequency: number | null;
  difficultyRank: string | null;
}

export interface ApiTrade {
  id: string;
  habitId: string | null;
  rewardId: string | null;
  amount: number;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface ApiTag {
  id: string;
  name: string;
  colorHex: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface ApiHabitTag {
  habitId: string;
  tagId: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface ApiReward {
  id: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  maxDailyFrequency: number | null;
  damageRank: string | null;
}

export interface ApiRewardTag {
  rewardId: string;
  tagId: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface ApiSyncResponse {
  habits: ApiHabit[];
  trades: ApiTrade[];
  tags: ApiTag[];
  habitTags: ApiHabitTag[];
  rewards: ApiReward[];
  rewardTags: ApiRewardTag[];
  balance: { tofuBalance: number };
  serverTime: string;
  email: string | null;
  isPremium: boolean;
  generalDifficulty: number;
}

// ============ Transformer Functions ============

export function transformHabitFromApi(h: ApiHabit): Habit {
  return {
    id: h.id,
    user_id: "",
    name: h.name,
    description: h.description,
    created_at: h.createdAt,
    updated_at: h.updatedAt,
    deleted_at: h.deletedAt,
    min_daily_frequency: h.minDailyFrequency,
    difficulty_rank: h.difficultyRank,
  };
}

export function transformTradeFromApi(t: ApiTrade): Trade {
  return {
    id: t.id,
    user_id: "",
    habit_id: t.habitId,
    reward_id: t.rewardId,
    amount: t.amount,
    created_at: t.createdAt,
    updated_at: t.updatedAt,
    deleted_at: t.deletedAt,
  };
}

export function transformTagFromApi(t: ApiTag): Tag {
  return {
    id: t.id,
    user_id: "",
    name: t.name,
    color_hex: t.colorHex,
    created_at: t.createdAt,
    updated_at: t.updatedAt,
    deleted_at: t.deletedAt,
  };
}

export function transformHabitTagFromApi(ht: ApiHabitTag): HabitTag {
  return {
    habit_id: ht.habitId,
    tag_id: ht.tagId,
    user_id: "",
    created_at: ht.createdAt,
    updated_at: ht.updatedAt,
    deleted_at: ht.deletedAt,
  };
}

export function transformRewardFromApi(r: ApiReward): Reward {
  return {
    id: r.id,
    user_id: "",
    name: r.name,
    description: r.description,
    created_at: r.createdAt,
    updated_at: r.updatedAt,
    deleted_at: r.deletedAt,
    max_daily_frequency: r.maxDailyFrequency,
    damage_rank: r.damageRank,
  };
}

export function transformRewardTagFromApi(rt: ApiRewardTag): RewardTag {
  return {
    reward_id: rt.rewardId,
    tag_id: rt.tagId,
    user_id: "",
    created_at: rt.createdAt,
    updated_at: rt.updatedAt,
    deleted_at: rt.deletedAt,
  };
}

export function transformSyncResponse(result: ApiSyncResponse): SyncResponse {
  return {
    habits: result.habits.map(transformHabitFromApi),
    trades: result.trades.map(transformTradeFromApi),
    tags: result.tags.map(transformTagFromApi),
    habitTags: result.habitTags.map(transformHabitTagFromApi),
    rewards: result.rewards.map(transformRewardFromApi),
    rewardTags: result.rewardTags.map(transformRewardTagFromApi),
    balance: {
      tofu_balance: result.balance.tofuBalance,
    },
    server_time: result.serverTime,
    email: result.email,
    isPremium: result.isPremium,
    generalDifficulty: result.generalDifficulty,
  };
}
