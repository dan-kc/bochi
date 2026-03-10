import { View, Text, Pressable, Image } from "react-native";

interface ProfileCardProps {
  user?: {
    id: string;
    isAnonymous?: boolean;
    avatarUrl?: string;
  } | null;
  onRegister?: () => void;
  onLogin?: () => void;
  onLogout?: () => void;
  onClaimAccount?: () => void;
}

export default function ProfileCard({
  user,
  onRegister,
  onLogin,
  onLogout,
  onClaimAccount,
}: ProfileCardProps) {
  // Anonymous user - show claim account prompt
  if (user && user.isAnonymous) {
    return (
      <View className="bg-accent rounded-xl p-5 mb-4">
        <View className="flex-row items-center gap-3 mb-3">
          <View className="w-10 h-10 rounded-full bg-white/20 items-center justify-center">
            <Text className="text-white text-lg font-bold">?</Text>
          </View>
          <View className="flex-1">
            <Text className="text-white text-sm opacity-80">Anonymous Account</Text>
            <Text className="text-white text-xs opacity-60">
              ID: {user.id.slice(0, 8)}...
            </Text>
          </View>
        </View>
        <Text className="text-white/90 mb-4">
          Create an account to sync your data across devices and keep it safe.
        </Text>
        <View className="flex-row gap-3">
          <Pressable
            onPress={onClaimAccount}
            className="flex-1 bg-white py-3 px-6 rounded-lg items-center"
          >
            {({ hovered }) => (
              <Text
                className={`font-semibold ${hovered ? "text-accent" : "text-accent"}`}
              >
                Create Account
              </Text>
            )}
          </Pressable>
          <Pressable
            onPress={onLogin}
            className="flex-1 border-2 border-white py-3 px-6 rounded-lg items-center"
          >
            {({ hovered }) => (
              <Text
                className={`font-semibold ${hovered ? "text-white/80" : "text-white"}`}
              >
                Login
              </Text>
            )}
          </Pressable>
        </View>
      </View>
    );
  }

  // Logged in user (not anonymous)
  if (user) {
    return (
      <View className="bg-surface border border-border rounded-xl p-4 mb-4">
        <View className="flex-row items-center gap-4">
          {user.avatarUrl ? (
            <Image
              source={{ uri: user.avatarUrl }}
              className="w-14 h-14 rounded-full bg-surface"
            />
          ) : (
            <View className="w-14 h-14 rounded-full bg-accent items-center justify-center">
              <Text className="text-white text-xl font-bold">
                {user.id.charAt(0).toUpperCase()}
              </Text>
            </View>
          )}
          <View className="flex-1">
            <Text className="text-lg font-semibold text-foreground">
              {user.id.slice(0, 8)}...
            </Text>
            <Text className="text-sm text-accent-secondary">Account synced</Text>
          </View>
        </View>
        {onLogout && (
          <Pressable
            onPress={onLogout}
            className="mt-4 py-2 px-4 border border-border rounded-lg items-center"
          >
            {({ hovered }) => (
              <Text
                className={`font-medium ${hovered ? "text-foreground" : "text-muted"}`}
              >
                Log Out
              </Text>
            )}
          </Pressable>
        )}
      </View>
    );
  }

  // No user at all (loading state or error)
  return (
    <View className="bg-accent rounded-xl p-5 mb-4">
      <Text className="text-xl font-bold text-white mb-2">
        Get Started with Tofustash
      </Text>
      <Text className="text-white/80 mb-4">
        Sign up to sync your habits across devices and unlock premium features.
      </Text>
      <View className="flex-row gap-3">
        <Pressable
          onPress={onRegister}
          className="flex-1 bg-white py-3 px-6 rounded-lg items-center"
        >
          {({ hovered }) => (
            <Text
              className={`font-semibold ${hovered ? "text-accent" : "text-accent"}`}
            >
              Register
            </Text>
          )}
        </Pressable>
        <Pressable
          onPress={onLogin}
          className="flex-1 border-2 border-white py-3 px-6 rounded-lg items-center"
        >
          {({ hovered }) => (
            <Text
              className={`font-semibold ${hovered ? "text-white/80" : "text-white"}`}
            >
              Login
            </Text>
          )}
        </Pressable>
      </View>
    </View>
  );
}
