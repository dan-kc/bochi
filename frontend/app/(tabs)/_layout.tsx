import { Tabs, Slot } from "expo-router";
import { Platform, useWindowDimensions, View } from "react-native";
import { useColorScheme } from "nativewind";
import Navbar from "../../components/Navbar";

export default function TabsLayout() {
  const { width } = useWindowDimensions();
  const isWeb = Platform.OS === "web";
  const isDesktop = isWeb && width >= 1024;
  const { colorScheme } = useColorScheme();
  const isDark = colorScheme === "dark";

  if (isDesktop) {
    return (
      <View className="flex-1 bg-background">
        <Navbar />
        <View className="flex-1 max-w-7xl w-full mx-auto">
          <Slot />
        </View>
      </View>
    );
  }

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: "#f54900",
        tabBarInactiveTintColor: isDark ? "#9e9890" : "#7d7888",
        tabBarStyle: {
          backgroundColor: isDark ? "#1b1a1f" : "#fffeff",
          borderTopColor: isDark ? "#2e2d33" : "#e5e3e7",
        },
        headerShown: false,
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: "Habits",
        }}
      />
      <Tabs.Screen
        name="rewards"
        options={{
          title: "Rewards",
        }}
      />
      <Tabs.Screen
        name="trades"
        options={{
          title: "Trades",
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: "Settings",
        }}
      />
    </Tabs>
  );
}
