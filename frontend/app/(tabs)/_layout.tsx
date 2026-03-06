import { Tabs, Slot } from "expo-router";
import { Platform, useWindowDimensions, View } from "react-native";
import Navbar from "../../components/Navbar";

export default function TabsLayout() {
  const { width } = useWindowDimensions();
  const isWeb = Platform.OS === "web";
  const isDesktop = isWeb && width >= 1024;

  if (isDesktop) {
    return (
      <View className="flex-1">
        <Navbar />
        <Slot />
      </View>
    );
  }

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: "#3b82f6",
        tabBarInactiveTintColor: "#6b7280",
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
