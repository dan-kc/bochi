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
      <View className="bg-gradient-to-r from-amber-500 to-orange-500 rounded-xl p-5 mb-4">
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
                className={`font-semibold ${hovered ? "text-orange-700" : "text-orange-600"}`}
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
                className={`font-semibold ${hovered ? "text-orange-100" : "text-white"}`}
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
      <View className="bg-white border border-gray-200 rounded-xl p-4 mb-4">
        <View className="flex-row items-center gap-4">
          {user.avatarUrl ? (
            <Image
              source={{ uri: user.avatarUrl }}
              className="w-14 h-14 rounded-full bg-gray-200"
            />
          ) : (
            <View className="w-14 h-14 rounded-full bg-blue-500 items-center justify-center">
              <Text className="text-white text-xl font-bold">
                {user.id.charAt(0).toUpperCase()}
              </Text>
            </View>
          )}
          <View className="flex-1">
            <Text className="text-lg font-semibold text-gray-900">
              {user.id.slice(0, 8)}...
            </Text>
            <Text className="text-sm text-green-600">Account synced</Text>
          </View>
        </View>
        {onLogout && (
          <Pressable
            onPress={onLogout}
            className="mt-4 py-2 px-4 border border-gray-300 rounded-lg items-center"
          >
            {({ hovered }) => (
              <Text
                className={`font-medium ${hovered ? "text-gray-900" : "text-gray-600"}`}
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
    <View className="bg-gradient-to-r from-amber-500 to-orange-500 rounded-xl p-5 mb-4">
      <Text className="text-xl font-bold text-white mb-2">
        Get Started with Tofustash
      </Text>
      <Text className="text-orange-100 mb-4">
        Sign up to sync your tasks across devices and unlock premium features.
      </Text>
      <View className="flex-row gap-3">
        <Pressable
          onPress={onRegister}
          className="flex-1 bg-white py-3 px-6 rounded-lg items-center"
        >
          {({ hovered }) => (
            <Text
              className={`font-semibold ${hovered ? "text-orange-700" : "text-orange-600"}`}
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
              className={`font-semibold ${hovered ? "text-orange-100" : "text-white"}`}
            >
              Login
            </Text>
          )}
        </Pressable>
      </View>
    </View>
  );
}
