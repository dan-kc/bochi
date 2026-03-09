import type { Reward, RewardInput } from "../reward";
import { markRewardDirty, markRewardsDirty } from "../sync/syncStorage";
import { EntityStore, generateUUID } from "./createStore";

const REWARDS_STORAGE_KEY = "tofustash_rewards";

// User ID used when offline (no authenticated user)
export const LOCAL_USER_ID = "local-user";

// ============ Reward Normalization ============

export function normalizeReward(reward: Partial<Reward>): Reward {
  return {
    id: reward.id ?? "",
    user_id: reward.user_id ?? "",
    name: reward.name ?? "",
    description: reward.description ?? "",
    created_at: reward.created_at ?? new Date().toISOString(),
    updated_at: reward.updated_at ?? new Date().toISOString(),
    deleted_at: reward.deleted_at ?? null,
    max_daily_frequency: reward.max_daily_frequency ?? null,
    damage_rank: reward.damage_rank ?? null,
  };
}

// ============ Reward Store ============

class RewardStore extends EntityStore<Reward> {
  constructor() {
    super({
      storageKey: REWARDS_STORAGE_KEY,
      normalize: normalizeReward,
      markDirty: markRewardDirty,
      markManyDirty: markRewardsDirty,
      enableVisibilityReload: true,
      enableAppStateReload: true,
    });
  }

  // ============ Reward-specific Selectors ============

  getAllRewards(userId: string): Reward[] {
    return this.getAll(userId);
  }

  getRewardsSortedByDamage(userId: string): Reward[] {
    return this.state.allIds
      .map((id) => this.state.byId[id])
      .filter((r) => r.user_id === userId && !r.deleted_at)
      .sort((a, b) => {
        if (a.damage_rank == null && b.damage_rank == null) return 0;
        if (a.damage_rank == null) return 1;
        if (b.damage_rank == null) return -1;
        return b.damage_rank.localeCompare(a.damage_rank);
      });
  }

  getRewardById(id: string): Reward | undefined {
    return this.getById(id);
  }

  getRewardCount(userId: string): number {
    return this.state.allIds.filter(
      (id) => this.state.byId[id].user_id === userId && !this.state.byId[id].deleted_at,
    ).length;
  }

  // ============ Reward Mutations ============

  async createReward(userId: string, input: RewardInput): Promise<Reward> {
    const now = new Date().toISOString();
    const reward: Reward = {
      id: generateUUID(),
      user_id: userId,
      name: input.name,
      description: input.description,
      created_at: now,
      updated_at: now,
      deleted_at: input.deleted_at ?? null,
      max_daily_frequency: input.max_daily_frequency ?? null,
      damage_rank: input.damage_rank ?? null,
    };

    await this.addItem(reward);
    return reward;
  }

  async updateReward(id: string, input: Partial<RewardInput>): Promise<Reward | null> {
    const existing = this.state.byId[id];
    if (!existing) return null;

    const updates: Partial<Reward> = {};
    if (input.name !== undefined) updates.name = input.name;
    if (input.description !== undefined) updates.description = input.description;
    if (input.deleted_at !== undefined) updates.deleted_at = input.deleted_at;
    if (input.max_daily_frequency !== undefined) updates.max_daily_frequency = input.max_daily_frequency;
    if (input.damage_rank !== undefined) updates.damage_rank = input.damage_rank;

    return this.updateItem(id, updates);
  }

  async deleteReward(id: string): Promise<boolean> {
    const result = await this.updateItem(id, { deleted_at: new Date().toISOString() });
    return result !== null;
  }

  // ============ Sync Helpers (aliases for compatibility) ============

  async mergeRewards(serverRewards: Partial<Reward>[], userId?: string): Promise<void> {
    return this.merge(serverRewards, userId);
  }

  getDirtyRewards(dirtyIds: Set<string>): Reward[] {
    return this.getDirty(dirtyIds);
  }

  async purgeDeletedRewards(): Promise<void> {
    return this.purgeDeleted();
  }

  async clearAllRewards(): Promise<void> {
    return this.clearAll();
  }

  async updateAllRewardsUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    return this.updateAllUserId(newUserId, fromUserId);
  }

  async migrateLocalUserRewards(newUserId: string): Promise<number> {
    const migratedIds = await this.updateAllUserId(newUserId, LOCAL_USER_ID);
    if (migratedIds.length > 0) {
      console.log(`[RewardStore] Migrated ${migratedIds.length} rewards from local-user to ${newUserId}`);
    }
    return migratedIds.length;
  }
}

// ============ Singleton Export ============

export const rewardStore = new RewardStore();
