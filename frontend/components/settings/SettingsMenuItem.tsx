import { Text, Pressable, View, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useColors, fontSize, spacing } from "@/lib/theme";

interface SettingsMenuItemProps {
  icon: keyof typeof Ionicons.glyphMap;
  iconColor?: string;
  label: string;
  value?: string;
  onPress: () => void;
  showChevron?: boolean;
}

export function SettingsMenuItem({
  icon,
  iconColor = "#f54900",
  label,
  value,
  onPress,
  showChevron = true,
}: SettingsMenuItemProps) {
  const colors = useColors();

  return (
    <Pressable
      onPress={onPress}
      style={styles.container}
    >
      <Ionicons
        name={icon}
        size={24}
        color={iconColor}
        style={styles.icon}
      />
      <Text style={[styles.label, { color: colors.foreground }]}>
        {label}
      </Text>
      {value && (
        <Text style={[styles.value, { color: colors.muted }]}>{value}</Text>
      )}
      {showChevron && (
        <Ionicons name="chevron-forward" size={20} color={colors.muted} />
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: spacing[4],
    paddingHorizontal: spacing[4],
  },
  icon: {
    marginRight: spacing[4],
  },
  label: {
    flex: 1,
    fontSize: fontSize.base,
  },
  value: {
    fontSize: fontSize.base,
    marginRight: spacing[2],
  },
});
