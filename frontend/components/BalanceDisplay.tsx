import { View, Text } from "react-native";
import { useSyncExternalStore } from "react";
import { balanceStore } from "@/lib/store/balanceStore";

export function BalanceDisplay() {
  const balance = useSyncExternalStore(
    balanceStore.subscribe,
    balanceStore.getSnapshot,
    balanceStore.getServerSnapshot,
  );

  return (
    <View className="bg-amber-100 border border-amber-300 px-3 py-1 rounded-lg flex-row items-center">
      <Text className="text-amber-800 font-semibold">
        {balance.tofu_balance} tofu
      </Text>
    </View>
  );
}
