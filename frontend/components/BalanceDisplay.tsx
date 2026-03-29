import { View, Text, StyleSheet } from "react-native";
import { useSyncExternalStore } from "react";
import { balanceStore } from "@/lib/store/balanceStore";
import { useColors, fontSize, fontWeight, spacing, borderRadius } from "@/lib/theme";

export function BalanceDisplay() {
  const colors = useColors();
  const balance = useSyncExternalStore(
    balanceStore.subscribe,
    balanceStore.getSnapshot,
    balanceStore.getServerSnapshot,
  );

  return (
    <View
      style={[
        styles.container,
        { backgroundColor: colors.surface, borderColor: colors.border },
      ]}
    >
      <Text style={[styles.text, { color: colors.accent }]}>
        {balance.tofu_balance} tofu
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: spacing[3],
    paddingVertical: spacing[1],
    borderRadius: borderRadius.lg,
    borderWidth: 1,
  },
  text: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.semibold,
  },
});
