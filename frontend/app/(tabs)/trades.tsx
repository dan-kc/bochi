import { useState, useCallback, useMemo } from "react";
import { View, Text } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useAuth } from "@/lib/AuthContext";
import { LOCAL_USER_ID, useTrades } from "@/lib/store";
import { habitStore } from "@/lib/store/habitStore";
import { rewardStore } from "@/lib/store/rewardStore";
import { BalanceDisplay } from "@/components/BalanceDisplay";
import { SortDropdown } from "@/components/SortDropdown";
import { FilterChips } from "@/components/FilterChips";
import { TradeItem } from "@/components/TradeItem";
import type { Trade } from "@/lib/trade";
import { TRADE_SORT_OPTIONS, DEFAULT_TRADE_SORT, type TradeSortKey } from "@/lib/tradeSortOptions";
import { TRADE_FILTER_OPTIONS, DEFAULT_TRADE_FILTER, type TradeFilterKey } from "@/lib/tradeSortOptions";
import { filterTrades, sortTrades } from "@/lib/tradeSorting";

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

export default function Trades() {
  const { user } = useAuth();
  const userId = user?.id ?? LOCAL_USER_ID;
  const trades = useTrades(userId);

  const [filterKey, setFilterKey] = useState<TradeFilterKey>(DEFAULT_TRADE_FILTER);
  const [sortKey, setSortKey] = useState<TradeSortKey>(DEFAULT_TRADE_SORT);

  const displayTrades = useMemo(() => {
    const filtered = filterTrades(trades, filterKey);
    return sortTrades(filtered, sortKey);
  }, [trades, filterKey, sortKey]);

  const getTradeInfo = useCallback((trade: Trade) => {
    if (trade.habit_id) {
      const habit = habitStore.getHabitById(trade.habit_id);
      return { type: "Sold" as const, name: habit?.name ?? "Deleted habit" };
    }
    const reward = rewardStore.getRewardById(trade.reward_id!);
    return { type: "Bought" as const, name: reward?.name ?? "Deleted reward" };
  }, []);

  const renderItem = useCallback(
    ({ item }: { item: Trade }) => {
      const { type, name } = getTradeInfo(item);
      return (
        <TradeItem
          type={type}
          name={name}
          amount={item.amount}
          date={formatDate(item.created_at)}
        />
      );
    },
    [getTradeInfo],
  );

  const keyExtractor = useCallback((item: Trade) => item.id, []);

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <View className="flex-1">
        <View className="p-4 border-b border-border">
          <View className="flex-row justify-between items-center mb-3">
            <Text className="text-2xl font-bold text-foreground">Trades</Text>
            <BalanceDisplay />
          </View>
          <View className="flex-row justify-between items-center">
            <FilterChips
              options={TRADE_FILTER_OPTIONS}
              selectedKey={filterKey}
              onSelect={setFilterKey}
            />
            <SortDropdown
              options={TRADE_SORT_OPTIONS}
              selectedKey={sortKey}
              onSelect={setSortKey}
            />
          </View>
        </View>

        {displayTrades.length === 0 ? (
          <View className="flex-1 items-center justify-center p-4">
            <Text className="text-muted text-center">No trades yet.</Text>
          </View>
        ) : (
          <LegendList
            data={displayTrades}
            renderItem={renderItem}
            keyExtractor={keyExtractor}
            extraData={{ sortKey, filterKey }}
            contentContainerStyle={{ padding: 16 }}
            estimatedItemSize={80}
          />
        )}
      </View>
    </SafeAreaView>
  );
}
