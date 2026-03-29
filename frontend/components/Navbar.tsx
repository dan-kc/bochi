import { View, Text, Pressable, StyleSheet } from "react-native";
import { Link, usePathname } from "expo-router";
import { useColors, spacing, fontSize, fontWeight } from "@/lib/theme";

export default function Navbar() {
  const colors = useColors();
  const pathname = usePathname();

  const navItems = [
    { name: "Habits", path: "/" },
    { name: "Rewards", path: "/rewards" },
    { name: "Trades", path: "/trades" },
    { name: "Settings", path: "/settings" },
  ] as const;

  return (
    <View style={[styles.container, { backgroundColor: colors.background, borderBottomColor: colors.border }]}>
      <View style={styles.inner}>
        <Text style={[styles.logo, { color: colors.foreground }]}>TOFUSTASH</Text>
        <View style={styles.nav}>
          {navItems.map((item) => {
            const isActive = pathname === item.path;
            return (
              <Link key={item.path} href={item.path} asChild>
                <Pressable>
                  {({ hovered }) => (
                    <Text
                      style={[
                        styles.navItem,
                        {
                          color: isActive
                            ? colors.accent
                            : hovered
                              ? colors.foreground
                              : colors.muted
                        }
                      ]}
                    >
                      {item.name}
                    </Text>
                  )}
                </Pressable>
              </Link>
            );
          })}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderBottomWidth: 1,
    paddingHorizontal: spacing[6],
    paddingVertical: spacing[4],
  },
  inner: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    maxWidth: 1280,
    marginHorizontal: "auto",
    width: "100%",
  },
  logo: {
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
  },
  nav: {
    flexDirection: "row",
    gap: spacing[6],
  },
  navItem: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.medium,
  },
});
