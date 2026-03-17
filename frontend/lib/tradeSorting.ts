import type { Trade } from "./trade";
import type { TradeSortKey, TradeFilterKey } from "./tradeSortOptions";
import { habitStore } from "./store/habitStore";
import { rewardStore } from "./store/rewardStore";

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

export function formatTradeDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

export function getTradeInfo(trade: Trade): { type: "Sold" | "Bought"; name: string } {
  if (trade.habit_id) {
    const habit = habitStore.getHabitById(trade.habit_id);
    return { type: "Sold", name: habit?.name ?? "Deleted habit" };
  }
  const reward = rewardStore.getRewardById(trade.reward_id!);
  return { type: "Bought", name: reward?.name ?? "Deleted reward" };
}
