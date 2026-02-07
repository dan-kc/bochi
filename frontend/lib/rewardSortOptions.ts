export type RewardSortKey =
  | "price_desc"
  | "price_asc"
  | "newest"
  | "oldest"
  | "frequency_desc"
  | "frequency_asc"
  | "damage_desc"
  | "damage_asc";

export interface RewardSortOption {
  key: RewardSortKey;
  label: string;
}

export const REWARD_SORT_OPTIONS: RewardSortOption[] = [
  { key: "price_desc", label: "Price: Most Expensive" },
  { key: "price_asc", label: "Price: Cheapest" },
  { key: "damage_desc", label: "Damage: Highest First" },
  { key: "damage_asc", label: "Damage: Lowest First" },
  { key: "frequency_desc", label: "Frequency: Highest First" },
  { key: "frequency_asc", label: "Frequency: Lowest First" },
  { key: "newest", label: "Newest First" },
  { key: "oldest", label: "Oldest First" },
];

export const DEFAULT_REWARD_SORT: RewardSortKey = "price_desc";

export function getRewardSortLabel(sortKey: RewardSortKey): string {
  const found = REWARD_SORT_OPTIONS.find((opt) => opt.key === sortKey);
  return found?.label ?? "Price: Most Expensive";
}
