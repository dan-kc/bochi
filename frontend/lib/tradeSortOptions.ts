export type TradeSortKey = "newest" | "oldest" | "most_expensive" | "cheapest";

export interface TradeSortOption {
  key: TradeSortKey;
  label: string;
}

export const TRADE_SORT_OPTIONS: TradeSortOption[] = [
  { key: "newest", label: "Newest" },
  { key: "oldest", label: "Oldest" },
  { key: "most_expensive", label: "Most Expensive" },
  { key: "cheapest", label: "Cheapest" },
];

export const DEFAULT_TRADE_SORT: TradeSortKey = "newest";

export type TradeFilterKey = "both" | "habit" | "reward";

export interface TradeFilterOption {
  key: TradeFilterKey;
  label: string;
}

export const TRADE_FILTER_OPTIONS: TradeFilterOption[] = [
  { key: "both", label: "Both" },
  { key: "reward", label: "Reward" },
  { key: "habit", label: "Habit" },
];

export const DEFAULT_TRADE_FILTER: TradeFilterKey = "both";
