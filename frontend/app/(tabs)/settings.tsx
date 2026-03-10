import { useState, useSyncExternalStore } from "react";
import { View, Text } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { router } from "expo-router";
import ProfileCard from "@/components/ProfileCard";
import { useAuth } from "@/lib/AuthContext";
import { useSync } from "@/lib/sync";
import { useTheme } from "@/lib/ThemeContext";
import { userStore } from "@/lib/store/userStore";
import { markGeneralDifficultyDirty } from "@/lib/sync/syncStorage";
import { SettingsMenuItem } from "@/components/settings/SettingsMenuItem";
import { AccountModal } from "@/components/settings/AccountModal";
import { GeneralDifficultyModal } from "@/components/settings/GeneralDifficultyModal";

export default function Settings() {
  const { user, logout, isAnonymous } = useAuth();
  const { triggerSync } = useSync();
  const { colorScheme, toggleTheme } = useTheme();
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

  return (
    <SafeAreaView className="flex-1 bg-background">
      <View className="flex-1 p-4">
        <Text className="text-2xl font-bold text-foreground mb-4">Settings</Text>

        {isLoggedIn ? (
          <>
            {/* Account Settings Menu */}
            <View className="bg-surface rounded-xl mb-4">
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
        <View className="bg-surface rounded-xl mt-4">
          <SettingsMenuItem
            icon={colorScheme === "dark" ? "moon" : "sunny"}
            label="Appearance"
            value={colorScheme === "dark" ? "Dark" : "Light"}
            onPress={toggleTheme}
            showChevron={false}
          />
        </View>

        {/* General Difficulty - available to all users */}
        <View className="bg-surface rounded-xl mt-4">
          <SettingsMenuItem
            icon="speedometer-outline"
            label="General Difficulty"
            value={userState.generalDifficulty.toString()}
            onPress={() => setShowDifficultyModal(true)}
          />
        </View>

        <Text className="text-muted mt-4">App settings and preferences.</Text>
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
