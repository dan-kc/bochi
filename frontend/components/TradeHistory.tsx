import { useState, useMemo } from "react";
import { View, Text, Pressable, StyleSheet } from "react-native";
import { useTrades } from "@/lib/store";
import { sortTrades, formatTradeDate, getTradeInfo } from "@/lib/tradeSorting";
import { TradeItem } from "./TradeItem";
import { useColors, spacing, fontSize, fontWeight } from "@/lib/theme";

const COLLAPSED_COUNT = 5;

interface TradeHistoryProps {
  userId: string;
  habitId?: string;
  rewardId?: string;
}

export function TradeHistory({ userId, habitId, rewardId }: TradeHistoryProps) {
  const colors = useColors();
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
    <View style={styles.container}>
      <Text style={[styles.header, { color: colors.muted }]}>History</Text>
      {filtered.length === 0 ? (
        <Text style={[styles.emptyText, { color: colors.muted }]}>No trades yet.</Text>
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
            <Pressable onPress={() => setShowAll(!showAll)} style={styles.showMoreButton}>
              <Text style={[styles.showMoreText, { color: colors.muted }]}>
                {showAll ? "Show less" : `Show all (${filtered.length})`}
              </Text>
            </Pressable>
          )}
        </>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginTop: spacing[6],
  },
  header: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
    marginBottom: spacing[2],
  },
  emptyText: {
    fontSize: fontSize.sm,
  },
  showMoreButton: {
    paddingVertical: spacing[3],
    alignItems: "center",
  },
  showMoreText: {
    fontSize: fontSize.sm,
  },
});
