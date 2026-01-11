import { View, Text, Pressable, Image } from "react-native";

interface ProfileCardProps {
  user?: {
    id: string;
    avatarUrl?: string;
  } | null;
  onRegister?: () => void;
  onLogin?: () => void;
  onLogout?: () => void;
}

export default function ProfileCard({
  user,
  onRegister,
  onLogin,
  onLogout,
}: ProfileCardProps) {
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
              {user.id}
            </Text>
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

  return (
    <View className="bg-gradient-to-r from-blue-500 to-blue-600 rounded-xl p-5 mb-4">
      <Text className="text-xl font-bold text-white mb-2">
        Get Started with Tofustash
      </Text>
      <Text className="text-blue-100 mb-4">
        Sign up to sync your tasks across devices and unlock premium features.
      </Text>
      <View className="flex-row gap-3">
        <Pressable
          onPress={onRegister}
          className="flex-1 bg-white py-3 px-6 rounded-lg items-center"
        >
          {({ hovered }) => (
            <Text
              className={`font-semibold ${hovered ? "text-blue-700" : "text-blue-600"}`}
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
              className={`font-semibold ${hovered ? "text-blue-100" : "text-white"}`}
            >
              Login
            </Text>
          )}
        </Pressable>
      </View>
    </View>
  );
}
