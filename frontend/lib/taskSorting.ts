import type { Task } from "./task";
import type { SortKey } from "./sortOptions";

export interface PriceData {
  current: number;
  previous: number;
}

export type DisplayMode = "price" | "frequency" | "created_at" | "due_by" | "difficulty";

export function sortTasks(
  tasks: Task[],
  sortKey: SortKey,
  prices: Record<string, PriceData>
): Task[] {
  return [...tasks].sort((a, b) => {
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
      case "due_soonest":
        if (!a.due_by && !b.due_by) return 0;
        if (!a.due_by) return 1;
        if (!b.due_by) return -1;
        return new Date(a.due_by).getTime() - new Date(b.due_by).getTime();
      case "due_latest":
        if (!a.due_by && !b.due_by) return 0;
        if (!a.due_by) return 1;
        if (!b.due_by) return -1;
        return new Date(b.due_by).getTime() - new Date(a.due_by).getTime();
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
    case "due_soonest":
    case "due_latest":
      return "due_by";
    case "difficulty_desc":
    case "difficulty_asc":
      return "difficulty";
    default:
      return "price";
  }
}

export function formatShortDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
