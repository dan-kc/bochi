export type SortKey =
  | "price_desc"
  | "price_asc"
  | "newest"
  | "oldest"
  | "frequency_desc"
  | "frequency_asc"
  | "difficulty_desc"
  | "difficulty_asc";

export interface SortOption {
  key: SortKey;
  label: string;
}

export const SORT_OPTIONS: SortOption[] = [
  { key: "price_desc", label: "Price: High to Low" },
  { key: "price_asc", label: "Price: Low to High" },
  { key: "difficulty_desc", label: "Difficulty: Hardest First" },
  { key: "difficulty_asc", label: "Difficulty: Easiest First" },
  { key: "frequency_desc", label: "Frequency: Highest First" },
  { key: "frequency_asc", label: "Frequency: Lowest First" },
  { key: "newest", label: "Newest First" },
  { key: "oldest", label: "Oldest First" },
];

export const DEFAULT_SORT: SortKey = "price_desc";

export function getSortLabel(sortKey: SortKey): string {
  const found = SORT_OPTIONS.find((opt) => opt.key === sortKey);
  return found?.label ?? "Price: High to Low";
}
