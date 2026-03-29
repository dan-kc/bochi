import { useState, useSyncExternalStore } from "react";
import { View, Text, StyleSheet } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { router } from "expo-router";
import ProfileCard from "@/components/ProfileCard";
import { useAuth } from "@/lib/AuthContext";
import { useSync, useSyncOptional } from "@/lib/sync";
import { useTheme } from "@/lib/ThemeContext";
import { userStore } from "@/lib/store/userStore";
import { markGeneralDifficultyDirty } from "@/lib/sync/syncStorage";
import { SettingsMenuItem } from "@/components/settings/SettingsMenuItem";
import { AccountModal } from "@/components/settings/AccountModal";
import { GeneralDifficultyModal } from "@/components/settings/GeneralDifficultyModal";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

function formatSyncStatus(syncStatus: string, lastSyncTime: string | null, syncError: string | null): string {
  if (syncStatus === "syncing") return "Syncing...";
  if (syncStatus === "error") return syncError ?? "Sync failed";
  if (lastSyncTime) {
    const date = new Date(lastSyncTime);
    const now = new Date();
    const isToday =
      date.getDate() === now.getDate() &&
      date.getMonth() === now.getMonth() &&
      date.getFullYear() === now.getFullYear();
    if (isToday) {
      return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
    }
    return date.toLocaleDateString([], { day: "2-digit", month: "2-digit", year: "numeric" });
  }
  return "Not synced";
}

export default function Settings() {
  const { user, logout, isAnonymous } = useAuth();
  const { triggerSync } = useSync();
  const { colorScheme, toggleTheme } = useTheme();
  const sync = useSyncOptional();
  const userState = useSyncExternalStore(
    userStore.subscribe,
    userStore.getSnapshot,
    userStore.getServerSnapshot,
  );

  const [showAccountModal, setShowAccountModal] = useState(false);
  const [showDifficultyModal, setShowDifficultyModal] = useState(false);

  const handleRegister = () => {
    router.push("/auth/register");
  };

  const handleLogin = () => {
    router.push("/auth/login");
  };

  const handleLogout = async () => {
    await logout();
  };

  const handleClaimAccount = () => {
    router.push("/auth/claim");
  };

  const handleEmailChanged = async (newEmail: string) => {
    // Update the local store immediately for responsiveness
    await userStore.setUser(newEmail, userState.isPremium);
    // Trigger a sync to ensure server state is reflected
    triggerSync();
  };

  const handleDifficultySave = async (value: number) => {
    await userStore.setGeneralDifficulty(value);
    await markGeneralDifficultyDirty();
    triggerSync();
  };

  const isLoggedIn = user && !isAnonymous && userState.email;
  const colors = useColors();

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]}>
      <View style={styles.container}>
        <Text style={[styles.title, { color: colors.foreground }]}>Settings</Text>

        {isLoggedIn ? (
          <>
            {/* Account Settings Menu */}
            <View style={[styles.menuCard, { backgroundColor: colors.surface }]}>
              <SettingsMenuItem
                icon="person-outline"
                label="Account"
                onPress={() => setShowAccountModal(true)}
              />
            </View>

            {/* Logout option */}
            <ProfileCard
              user={user}
              onRegister={handleRegister}
              onLogin={handleLogin}
              onLogout={handleLogout}
              onClaimAccount={handleClaimAccount}
            />
          </>
        ) : (
          <ProfileCard
            user={user}
            onRegister={handleRegister}
            onLogin={handleLogin}
            onLogout={handleLogout}
            onClaimAccount={handleClaimAccount}
          />
        )}

        {/* Appearance */}
        <View style={[styles.menuCardWithMargin, { backgroundColor: colors.surface }]}>
          <SettingsMenuItem
            icon={colorScheme === "dark" ? "moon" : "sunny"}
            label="Appearance"
            value={colorScheme === "dark" ? "Dark" : "Light"}
            onPress={toggleTheme}
            showChevron={false}
          />
        </View>

        {/* General Difficulty - available to all users */}
        <View style={[styles.menuCardWithMargin, { backgroundColor: colors.surface }]}>
          <SettingsMenuItem
            icon="speedometer-outline"
            label="General Difficulty"
            value={userState.generalDifficulty.toString()}
            onPress={() => setShowDifficultyModal(true)}
          />
        </View>

        {/* Sync Status */}
        {sync && (
          <View style={[styles.menuCardWithMargin, { backgroundColor: colors.surface }]}>
            <SettingsMenuItem
              icon={sync.syncStatus === "error" ? "cloud-offline" : "cloud-done-outline"}
              iconColor={sync.syncStatus === "error" ? "#f54900" : "#197291"}
              label="Sync"
              value={formatSyncStatus(sync.syncStatus, sync.lastSyncTime, sync.syncError)}
              onPress={triggerSync}
              showChevron={false}
            />
          </View>
        )}

        <Text style={[styles.description, { color: colors.muted }]}>App settings and preferences.</Text>
      </View>

      {isLoggedIn && userState.email && (
        <AccountModal
          visible={showAccountModal}
          onClose={() => setShowAccountModal(false)}
          currentEmail={userState.email}
          onEmailChanged={handleEmailChanged}
        />
      )}

      <GeneralDifficultyModal
        visible={showDifficultyModal}
        onClose={() => setShowDifficultyModal(false)}
        currentValue={userState.generalDifficulty}
        onSave={handleDifficultySave}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  container: {
    flex: 1,
    padding: spacing[4],
  },
  title: {
    fontSize: fontSize["2xl"],
    fontWeight: fontWeight.bold,
    marginBottom: spacing[4],
  },
  menuCard: {
    borderRadius: borderRadius.xl,
    marginBottom: spacing[4],
  },
  menuCardWithMargin: {
    borderRadius: borderRadius.xl,
    marginTop: spacing[4],
  },
  description: {
    marginTop: spacing[4],
  },
});
