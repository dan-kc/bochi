import { Tabs, Slot } from "expo-router";
import { Platform, useWindowDimensions, View, useColorScheme, StyleSheet } from "react-native";
import Navbar from "../../components/Navbar";
import { useColors } from "@/lib/theme";

export default function TabsLayout() {
  const { width } = useWindowDimensions();
  const isWeb = Platform.OS === "web";
  const isDesktop = isWeb && width >= 1024;
  const colorScheme = useColorScheme();
  const isDark = colorScheme === "dark";
  const colors = useColors();

  if (isDesktop) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <Navbar />
        <View style={styles.content}>
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

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flex: 1,
    maxWidth: 1280,
    width: "100%",
    marginLeft: "auto",
    marginRight: "auto",
  },
});
