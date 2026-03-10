import { View, Text, Pressable } from "react-native";
import { Link, usePathname } from "expo-router";

export default function Navbar() {
  const pathname = usePathname();

  const navItems = [
    { name: "Habits", path: "/" },
    { name: "Rewards", path: "/rewards" },
    { name: "Trades", path: "/trades" },
    { name: "Settings", path: "/settings" },
  ] as const;

  return (
    <View className="bg-background border-b border-border px-6 py-4">
      <View className="flex-row justify-between items-center max-w-7xl mx-auto w-full">
        <Text className="text-xl font-bold text-foreground">TOFUSTASH</Text>
        <View className="flex-row gap-6">
          {navItems.map((item) => {
            const isActive = pathname === item.path;
            return (
              <Link key={item.path} href={item.path} asChild>
                <Pressable>
                  {({ hovered }) => (
                    <Text
                      className={`text-base font-medium ${
                        isActive
                          ? "text-accent"
                          : hovered
                            ? "text-foreground"
                            : "text-muted"
                      }`}
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
