import type { Reward } from "./reward";
import type { RewardSortKey } from "./rewardSortOptions";
import type { PriceData } from "./dateUtils";
export type { PriceData } from "./dateUtils";
export { formatShortDate } from "./dateUtils";

export type DisplayMode = "price" | "frequency" | "created_at" | "damage";

export function sortRewards(
  rewards: Reward[],
  sortKey: RewardSortKey,
  prices: Record<string, PriceData>
): Reward[] {
  return [...rewards].sort((a, b) => {
    switch (sortKey) {
      case "price_desc":
        return (prices[b.id]?.current ?? 0) - (prices[a.id]?.current ?? 0);
      case "price_asc":
        return (prices[a.id]?.current ?? 0) - (prices[b.id]?.current ?? 0);
      case "newest":
        return (
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
        );
      case "oldest":
        return (
          new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
        );
      case "frequency_desc":
        if (a.max_daily_frequency == null && b.max_daily_frequency == null)
          return 0;
        if (a.max_daily_frequency == null) return 1;
        if (b.max_daily_frequency == null) return -1;
        return b.max_daily_frequency - a.max_daily_frequency;
      case "frequency_asc":
        if (a.max_daily_frequency == null && b.max_daily_frequency == null)
          return 0;
        if (a.max_daily_frequency == null) return 1;
        if (b.max_daily_frequency == null) return -1;
        return a.max_daily_frequency - b.max_daily_frequency;
      case "damage_desc":
        if (a.damage_rank == null && b.damage_rank == null) return 0;
        if (a.damage_rank == null) return 1;
        if (b.damage_rank == null) return -1;
        // Higher rank string = more damaging (lexicographic comparison, reversed)
        return b.damage_rank.localeCompare(a.damage_rank);
      case "damage_asc":
        if (a.damage_rank == null && b.damage_rank == null) return 0;
        if (a.damage_rank == null) return 1;
        if (b.damage_rank == null) return -1;
        // Lower rank string = less damaging
        return a.damage_rank.localeCompare(b.damage_rank);
      default:
        return 0;
    }
  });
}

export function getDisplayMode(sortKey: RewardSortKey): DisplayMode {
  switch (sortKey) {
    case "price_desc":
    case "price_asc":
      return "price";
    case "frequency_desc":
    case "frequency_asc":
      return "frequency";
    case "newest":
    case "oldest":
      return "created_at";
    case "damage_desc":
    case "damage_asc":
      return "damage";
    default:
      return "price";
  }
}
