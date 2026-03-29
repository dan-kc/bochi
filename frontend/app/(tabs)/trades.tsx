import { useState, useCallback, useMemo } from "react";
import { View, Text, StyleSheet } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useAuth } from "@/lib/AuthContext";
import { LOCAL_USER_ID, useTrades } from "@/lib/store";
import { BalanceDisplay } from "@/components/BalanceDisplay";
import { SortDropdown } from "@/components/SortDropdown";
import { FilterChips } from "@/components/FilterChips";
import { TradeItem } from "@/components/TradeItem";
import type { Trade } from "@/lib/trade";
import { TRADE_SORT_OPTIONS, DEFAULT_TRADE_SORT, type TradeSortKey } from "@/lib/tradeSortOptions";
import { TRADE_FILTER_OPTIONS, DEFAULT_TRADE_FILTER, type TradeFilterKey } from "@/lib/tradeSortOptions";
import { filterTrades, sortTrades, formatTradeDate, getTradeInfo } from "@/lib/tradeSorting";
import { useColors, spacing, fontSize, fontWeight } from "@/lib/theme";

export default function Trades() {
  const { user } = useAuth();
  const userId = user?.id ?? LOCAL_USER_ID;
  const trades = useTrades(userId);
  const colors = useColors();

  const [filterKey, setFilterKey] = useState<TradeFilterKey>(DEFAULT_TRADE_FILTER);
  const [sortKey, setSortKey] = useState<TradeSortKey>(DEFAULT_TRADE_SORT);

  const displayTrades = useMemo(() => {
    const filtered = filterTrades(trades, filterKey);
    return sortTrades(filtered, sortKey);
  }, [trades, filterKey, sortKey]);

  const renderItem = useCallback(
    ({ item }: { item: Trade }) => {
      const { type, name } = getTradeInfo(item);
      return (
        <TradeItem
          type={type}
          name={name}
          amount={item.amount}
          date={formatTradeDate(item.created_at)}
        />
      );
    },
    [],
  );

  const keyExtractor = useCallback((item: Trade) => item.id, []);

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]} edges={["top"]}>
      <View style={styles.container}>
        <View style={[styles.header, { borderBottomColor: colors.border }]}>
          <View style={styles.headerTop}>
            <Text style={[styles.title, { color: colors.foreground }]}>Trades</Text>
            <BalanceDisplay />
          </View>
          <View style={styles.headerBottom}>
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
          <View style={styles.emptyState}>
            <Text style={[styles.emptyText, { color: colors.muted }]}>No trades yet.</Text>
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

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  container: {
    flex: 1,
  },
  header: {
    padding: spacing[4],
    borderBottomWidth: 1,
  },
  headerTop: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: spacing[3],
  },
  title: {
    fontSize: fontSize["2xl"],
    fontWeight: fontWeight.bold,
  },
  headerBottom: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  emptyState: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: spacing[4],
  },
  emptyText: {
    textAlign: "center",
  },
});
