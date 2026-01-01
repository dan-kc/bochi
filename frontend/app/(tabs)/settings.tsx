import { View, Text } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { router } from "expo-router";
import ProfileCard from "@/components/ProfileCard";
import { useAuth } from "@/lib/AuthContext";

export default function Settings() {
  const { user, logout } = useAuth();

  const handleRegister = () => {
    router.push("/auth/register");
  };

  const handleLogin = () => {
    router.push("/auth/login");
  };

  const handleLogout = async () => {
    await logout();
  };

  return (
    <SafeAreaView className="flex-1 bg-white">
      <View className="flex-1 p-4">
        <Text className="text-2xl font-bold mb-4">Settings</Text>

        <ProfileCard
          user={user}
          onRegister={handleRegister}
          onLogin={handleLogin}
          onLogout={handleLogout}
        />

        <Text className="text-gray-600">App settings and preferences.</Text>
      </View>
    </SafeAreaView>
  );
}
