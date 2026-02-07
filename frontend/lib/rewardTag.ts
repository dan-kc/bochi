export interface RewardTag {
  reward_id: string;
  tag_id: string;
  user_id: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface RewardTagInput {
  reward_id: string;
  tag_id: string;
  deleted_at?: string | null;
}

/**
 * Creates a composite key for a reward-tag association
 */
export function rewardTagKey(rewardId: string, tagId: string): string {
  return `${rewardId}:${tagId}`;
}

/**
 * Parses a composite key back into reward_id and tag_id
 */
export function parseRewardTagKey(key: string): { rewardId: string; tagId: string } {
  const [rewardId, tagId] = key.split(":");
  return { rewardId, tagId };
}
