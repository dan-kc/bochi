import type { Habit } from "./habit";
import type { SortKey } from "./sortOptions";
import type { PriceData } from "./dateUtils";
export type { PriceData } from "./dateUtils";
export { formatShortDate } from "./dateUtils";

export type DisplayMode = "price" | "frequency" | "created_at" | "difficulty";

export function sortHabits(
  habits: Habit[],
  sortKey: SortKey,
  prices: Record<string, PriceData>
): Habit[] {
  return [...habits].sort((a, b) => {
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
        if (a.min_daily_frequency == null && b.min_daily_frequency == null)
          return 0;
        if (a.min_daily_frequency == null) return 1;
        if (b.min_daily_frequency == null) return -1;
        return b.min_daily_frequency - a.min_daily_frequency;
      case "frequency_asc":
        if (a.min_daily_frequency == null && b.min_daily_frequency == null)
          return 0;
        if (a.min_daily_frequency == null) return 1;
        if (b.min_daily_frequency == null) return -1;
        return a.min_daily_frequency - b.min_daily_frequency;
      case "difficulty_desc":
        if (a.difficulty_rank == null && b.difficulty_rank == null) return 0;
        if (a.difficulty_rank == null) return 1;
        if (b.difficulty_rank == null) return -1;
        // Higher rank string = harder (lexicographic comparison, reversed)
        return b.difficulty_rank.localeCompare(a.difficulty_rank);
      case "difficulty_asc":
        if (a.difficulty_rank == null && b.difficulty_rank == null) return 0;
        if (a.difficulty_rank == null) return 1;
        if (b.difficulty_rank == null) return -1;
        // Lower rank string = easier
        return a.difficulty_rank.localeCompare(b.difficulty_rank);
      default:
        return 0;
    }
  });
}

export function getDisplayMode(sortKey: SortKey): DisplayMode {
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
    case "difficulty_desc":
    case "difficulty_asc":
      return "difficulty";
    default:
      return "price";
  }
}
