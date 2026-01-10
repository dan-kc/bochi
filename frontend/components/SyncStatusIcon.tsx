import { View, Text, Pressable, ActivityIndicator } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useRouter } from "expo-router";
import { useAuth } from "@/lib/AuthContext";
import { useSyncOptional } from "@/lib/sync";
import {
  usePriceUpdateOptional,
  formatCountdown,
} from "@/lib/PriceUpdateContext";

function formatLastSynced(isoString: string): string {
  const date = new Date(isoString);
  const now = new Date();

  // Check if same day
  const isToday =
    date.getDate() === now.getDate() &&
    date.getMonth() === now.getMonth() &&
    date.getFullYear() === now.getFullYear();

  if (isToday) {
    // Show time only: "16:00"
    return date.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    });
  } else {
    // Show date: "12/04/2024"
    return date.toLocaleDateString([], {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
    });
  }
}

function PriceCountdown() {
  const priceContext = usePriceUpdateOptional();
  if (!priceContext) return null;

  const { secondsUntilUpdate } = priceContext;

  return (
    <View className="flex-row items-center mr-3">
      <Ionicons name="timer-outline" size={14} color="#d97706" />
      <Text className="ml-1 text-xs text-amber-600 font-medium">
        {formatCountdown(secondsUntilUpdate)}
      </Text>
    </View>
  );
}

export function SyncStatusIcon() {
  const { user } = useAuth();
  const sync = useSyncOptional();
  const router = useRouter();

  // If user is not logged in, show login prompt
  if (!user) {
    return (
      <View className="flex-row items-center">
        <PriceCountdown />
        <Pressable
          onPress={() => router.push("/auth/login")}
          className="flex-row items-center"
        >
          <Ionicons name="cloud-offline-outline" size={20} color="#9ca3af" />
          <Text className="ml-1 text-xs text-gray-500">Log in to sync</Text>
        </Pressable>
      </View>
    );
  }

  // If no sync context available, show nothing
  if (!sync) {
    return null;
  }

  const { syncStatus, lastSyncTime, triggerSync } = sync;

  const renderLastSynced = () => {
    if (!lastSyncTime) return null;
    return (
      <Text className="ml-1 text-xs text-gray-500">
        {formatLastSynced(lastSyncTime)}
      </Text>
    );
  };

  switch (syncStatus) {
    case "syncing":
      return (
        <View className="flex-row items-center">
          <PriceCountdown />
          <ActivityIndicator size="small" color="#3b82f6" />
          <Text className="ml-1 text-xs text-gray-500">Syncing...</Text>
        </View>
      );

    case "synced":
      return (
        <View className="flex-row items-center">
          <PriceCountdown />
          <Ionicons name="checkmark-circle" size={20} color="#22c55e" />
          {renderLastSynced()}
        </View>
      );

    case "error":
      return (
        <View className="flex-row items-center">
          <PriceCountdown />
          <Pressable onPress={triggerSync} className="flex-row items-center">
            <Ionicons name="cloud-offline" size={20} color="#ef4444" />
            <Text className="ml-1 text-xs text-red-600">Not synced</Text>
          </Pressable>
        </View>
      );

    case "idle":
    default:
      return (
        <View className="flex-row items-center">
          <PriceCountdown />
          <Ionicons name="cloud-outline" size={20} color="#9ca3af" />
          {renderLastSynced()}
        </View>
      );
  }
}
