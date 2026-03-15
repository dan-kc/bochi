import type { RewardTag } from "../rewardTag";
import { rewardTagKey } from "../rewardTag";
import { markRewardTagDirty, markRewardTagsDirty } from "../sync/syncStorage";
import { CompositeKeyStore } from "./createCompositeKeyStore";

export function normalizeRewardTag(rt: Partial<RewardTag>): RewardTag {
  return {
    reward_id: rt.reward_id ?? "",
    tag_id: rt.tag_id ?? "",
    user_id: rt.user_id ?? "",
    created_at: rt.created_at ?? new Date().toISOString(),
    updated_at: rt.updated_at ?? new Date().toISOString(),
    deleted_at: rt.deleted_at ?? null,
  };
}

class RewardTagStore extends CompositeKeyStore<RewardTag> {
  constructor() {
    super({
      storageKey: "tofustash_reward_tags",
      normalize: normalizeRewardTag,
      getKey: (rt) => rewardTagKey(rt.reward_id, rt.tag_id),
      markDirty: markRewardTagDirty,
      markManyDirty: markRewardTagsDirty,
    });
  }

  getTagIdsForReward(rewardId: string): string[] {
    return this.getIdsForField("reward_id", rewardId, "tag_id");
  }

  getRewardIdsForTag(tagId: string): string[] {
    return this.getIdsForField("tag_id", tagId, "reward_id");
  }

  async addTagToReward(userId: string, rewardId: string, tagId: string): Promise<RewardTag> {
    const now = new Date().toISOString();
    return this.addItem({
      reward_id: rewardId,
      tag_id: tagId,
      user_id: userId,
      created_at: now,
      updated_at: now,
      deleted_at: null,
    });
  }

  async removeTagFromReward(rewardId: string, tagId: string): Promise<boolean> {
    const key = rewardTagKey(rewardId, tagId);
    return this.removeItem(key, {} as RewardTag);
  }
}

export const rewardTagStore = new RewardTagStore();
