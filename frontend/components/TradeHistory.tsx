import { useState, useMemo } from "react";
import { View, Text, Pressable } from "react-native";
import { useTrades } from "@/lib/store";
import { sortTrades, formatTradeDate, getTradeInfo } from "@/lib/tradeSorting";
import { TradeItem } from "./TradeItem";

const COLLAPSED_COUNT = 5;

interface TradeHistoryProps {
  userId: string;
  habitId?: string;
  rewardId?: string;
}

export function TradeHistory({ userId, habitId, rewardId }: TradeHistoryProps) {
  const [showAll, setShowAll] = useState(false);
  const trades = useTrades(userId);

  const filtered = useMemo(() => {
    const matching = trades.filter((t) =>
      habitId ? t.habit_id === habitId : t.reward_id === rewardId,
    );
    return sortTrades(matching, "newest");
  }, [trades, habitId, rewardId]);

  const visible = showAll ? filtered : filtered.slice(0, COLLAPSED_COUNT);
  const hasMore = filtered.length > COLLAPSED_COUNT;

  return (
    <View className="mt-6">
      <Text className="text-sm font-medium text-muted mb-2">History</Text>
      {filtered.length === 0 ? (
        <Text className="text-muted text-sm">No trades yet.</Text>
      ) : (
        <>
          {visible.map((trade) => {
            const { type, name } = getTradeInfo(trade);
            return (
              <TradeItem
                key={trade.id}
                type={type}
                name={name}
                amount={trade.amount}
                date={formatTradeDate(trade.created_at)}
              />
            );
          })}
          {hasMore && (
            <Pressable onPress={() => setShowAll(!showAll)} className="py-3 items-center">
              <Text className="text-muted text-sm">
                {showAll ? "Show less" : `Show all (${filtered.length})`}
              </Text>
            </Pressable>
          )}
        </>
      )}
    </View>
  );
}
