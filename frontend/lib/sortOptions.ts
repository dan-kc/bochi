export type TabType = "both" | "habit" | "todo";

export type SortKey =
  | "price_desc"
  | "price_asc"
  | "newest"
  | "oldest"
  | "frequency_desc"
  | "frequency_asc"
  | "due_soonest"
  | "due_latest"
  | "difficulty_desc"
  | "difficulty_asc";

export interface SortOption {
  key: SortKey;
  label: string;
}

export const SORT_OPTIONS: Record<TabType, SortOption[]> = {
  both: [
    { key: "price_desc", label: "Price: High to Low" },
    { key: "price_asc", label: "Price: Low to High" },
    { key: "difficulty_desc", label: "Difficulty: Hardest First" },
    { key: "difficulty_asc", label: "Difficulty: Easiest First" },
    { key: "newest", label: "Newest First" },
    { key: "oldest", label: "Oldest First" },
  ],
  habit: [
    { key: "price_desc", label: "Price: High to Low" },
    { key: "price_asc", label: "Price: Low to High" },
    { key: "difficulty_desc", label: "Difficulty: Hardest First" },
    { key: "difficulty_asc", label: "Difficulty: Easiest First" },
    { key: "frequency_desc", label: "Frequency: Highest First" },
    { key: "frequency_asc", label: "Frequency: Lowest First" },
    { key: "newest", label: "Newest First" },
    { key: "oldest", label: "Oldest First" },
  ],
  todo: [
    { key: "price_desc", label: "Price: High to Low" },
    { key: "price_asc", label: "Price: Low to High" },
    { key: "difficulty_desc", label: "Difficulty: Hardest First" },
    { key: "difficulty_asc", label: "Difficulty: Easiest First" },
    { key: "due_soonest", label: "Due: Soonest First" },
    { key: "due_latest", label: "Due: Latest First" },
    { key: "newest", label: "Newest First" },
    { key: "oldest", label: "Oldest First" },
  ],
};

export const DEFAULT_SORT: Record<TabType, SortKey> = {
  both: "price_desc",
  habit: "price_desc",
  todo: "price_desc",
};

export function isValidSortForTab(tab: TabType, sortKey: SortKey): boolean {
  return SORT_OPTIONS[tab].some((opt) => opt.key === sortKey);
}

export function getSortLabel(sortKey: SortKey): string {
  for (const options of Object.values(SORT_OPTIONS)) {
    const found = options.find((opt) => opt.key === sortKey);
    if (found) return found.label;
  }
  return "Price: High to Low";
}
