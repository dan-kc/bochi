import { useState, useSyncExternalStore } from "react";
import { View, Text } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { router } from "expo-router";
import ProfileCard from "@/components/ProfileCard";
import { useAuth } from "@/lib/AuthContext";
import { useSync } from "@/lib/sync";
import { userStore } from "@/lib/store/userStore";
import { SettingsMenuItem } from "@/components/settings/SettingsMenuItem";
import { AccountModal } from "@/components/settings/AccountModal";

export default function Settings() {
  const { user, logout, isAnonymous } = useAuth();
  const { triggerSync } = useSync();
  const userState = useSyncExternalStore(
    userStore.subscribe,
    userStore.getSnapshot,
    userStore.getServerSnapshot,
  );

  const [showAccountModal, setShowAccountModal] = useState(false);

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

  const isLoggedIn = user && !isAnonymous && userState.email;

  return (
    <SafeAreaView className="flex-1 bg-white">
      <View className="flex-1 p-4">
        <Text className="text-2xl font-bold mb-4">Settings</Text>

        {isLoggedIn ? (
          <>
            {/* Account Settings Menu */}
            <View className="bg-zinc-800 rounded-xl mb-4">
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

        <Text className="text-gray-600 mt-4">App settings and preferences.</Text>
      </View>

      {isLoggedIn && userState.email && (
        <AccountModal
          visible={showAccountModal}
          onClose={() => setShowAccountModal(false)}
          currentEmail={userState.email}
          onEmailChanged={handleEmailChanged}
        />
      )}
    </SafeAreaView>
  );
}
