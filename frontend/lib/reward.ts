export interface Reward {
  id: string;
  user_id: string;
  name: string;
  description: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  hidden_until: string | null;
  max_daily_frequency: number | null;
  damage_rank: string | null;
}

export interface RewardInput {
  name: string;
  description: string;
  deleted_at?: string | null;
  hidden_until?: string | null;
  max_daily_frequency?: number | null;
  damage_rank?: string | null;
}

export function createEmptyRewardInput(): RewardInput {
  return {
    name: "",
    description: "",
    deleted_at: null,
    hidden_until: null,
    max_daily_frequency: null,
    damage_rank: null,
  };
}
