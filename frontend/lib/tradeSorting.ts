import type { Trade } from "./trade";
import type { TradeSortKey, TradeFilterKey } from "./tradeSortOptions";

export function filterTrades(trades: Trade[], filter: TradeFilterKey): Trade[] {
  switch (filter) {
    case "habit":
      return trades.filter((t) => t.habit_id != null);
    case "reward":
      return trades.filter((t) => t.reward_id != null);
    case "both":
    default:
      return trades;
  }
}

export function sortTrades(trades: Trade[], sortKey: TradeSortKey): Trade[] {
  const sorted = [...trades];
  switch (sortKey) {
    case "newest":
      sorted.sort((a, b) => b.created_at.localeCompare(a.created_at));
      break;
    case "oldest":
      sorted.sort((a, b) => a.created_at.localeCompare(b.created_at));
      break;
    case "most_expensive":
      sorted.sort((a, b) => Math.abs(b.amount) - Math.abs(a.amount));
      break;
    case "cheapest":
      sorted.sort((a, b) => Math.abs(a.amount) - Math.abs(b.amount));
      break;
  }
  return sorted;
}
