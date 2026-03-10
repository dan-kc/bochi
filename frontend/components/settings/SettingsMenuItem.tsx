import { Text, Pressable } from "react-native";
import { Ionicons } from "@expo/vector-icons";

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
  return (
    <Pressable
      onPress={onPress}
      className="flex-row items-center py-4 px-4"
    >
      {({ hovered }) => (
        <>
          <Ionicons
            name={icon}
            size={24}
            color={iconColor}
            style={{ marginRight: 16 }}
          />
          <Text
            className={`flex-1 text-base ${hovered ? "text-foreground" : "text-foreground"}`}
          >
            {label}
          </Text>
          {value && (
            <Text className="text-muted text-base mr-2">{value}</Text>
          )}
          {showChevron && (
            <Ionicons name="chevron-forward" size={20} color="var(--color-muted)" />
          )}
        </>
      )}
    </Pressable>
  );
}
