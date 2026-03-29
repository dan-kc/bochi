import { View, Text, Pressable, ActivityIndicator, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useRouter } from "expo-router";
import { useAuth } from "@/lib/AuthContext";
import { useSyncOptional } from "@/lib/sync";
import {
  usePriceUpdateOptional,
  formatCountdown,
} from "@/lib/PriceUpdateContext";
import { useColors, spacing, fontSize, fontWeight } from "@/lib/theme";

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
  const colors = useColors();
  const priceContext = usePriceUpdateOptional();
  if (!priceContext) return null;

  const { secondsUntilUpdate } = priceContext;

  return (
    <View style={styles.countdownContainer}>
      <Ionicons name="timer-outline" size={14} color={colors.accent} />
      <Text style={[styles.countdownText, { color: colors.accent }]}>
        {formatCountdown(secondsUntilUpdate)}
      </Text>
    </View>
  );
}

export function SyncStatusIcon() {
  const colors = useColors();
  const { user } = useAuth();
  const sync = useSyncOptional();
  const router = useRouter();

  // If user is not logged in, show login prompt
  if (!user) {
    return (
      <View style={styles.container}>
        <PriceCountdown />
        <Pressable
          onPress={() => router.push("/auth/login")}
          style={styles.statusContainer}
        >
          <Ionicons name="cloud-offline-outline" size={20} color={colors.muted} />
          <Text style={[styles.statusText, { color: colors.muted }]}>Log in to sync</Text>
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
      <Text style={[styles.statusText, { color: colors.muted }]}>
        {formatLastSynced(lastSyncTime)}
      </Text>
    );
  };

  switch (syncStatus) {
    case "syncing":
      return (
        <View style={styles.container}>
          <PriceCountdown />
          <ActivityIndicator size="small" color={colors.accent} />
          <Text style={[styles.statusText, { color: colors.muted }]}>Syncing...</Text>
        </View>
      );

    case "synced":
      return (
        <View style={styles.container}>
          <PriceCountdown />
          <Ionicons name="checkmark-circle" size={20} color={colors.accentSecondary} />
          {renderLastSynced()}
        </View>
      );

    case "error":
      return (
        <View style={styles.container}>
          <PriceCountdown />
          <Pressable onPress={triggerSync} style={styles.statusContainer}>
            <Ionicons name="cloud-offline" size={20} color={colors.accent} />
            <Text style={[styles.statusText, { color: colors.accent }]}>Not synced</Text>
          </Pressable>
        </View>
      );

    case "idle":
    default:
      return (
        <View style={styles.container}>
          <PriceCountdown />
          <Ionicons name="cloud-outline" size={20} color={colors.muted} />
          {renderLastSynced()}
        </View>
      );
  }
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    alignItems: "center",
  },
  statusContainer: {
    flexDirection: "row",
    alignItems: "center",
  },
  statusText: {
    marginLeft: spacing[1],
    fontSize: fontSize.xs,
  },
  countdownContainer: {
    flexDirection: "row",
    alignItems: "center",
    marginRight: spacing[3],
  },
  countdownText: {
    marginLeft: spacing[1],
    fontSize: fontSize.xs,
    fontWeight: fontWeight.medium,
  },
});
