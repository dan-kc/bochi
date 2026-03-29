import { View, Text, Pressable, StyleSheet } from "react-native";
import { useColors, fontSize, fontWeight, spacing, borderRadius } from "@/lib/theme";

interface FilterOption<K extends string> {
  key: K;
  label: string;
}

interface FilterChipsProps<K extends string> {
  options: FilterOption<K>[];
  selectedKey: K;
  onSelect: (key: K) => void;
}

export function FilterChips<K extends string>({
  options,
  selectedKey,
  onSelect,
}: FilterChipsProps<K>) {
  const colors = useColors();

  return (
    <View style={styles.container}>
      {options.map((option) => {
        const isActive = option.key === selectedKey;
        return (
          <Pressable
            key={option.key}
            onPress={() => onSelect(option.key)}
            style={[
              styles.chip,
              isActive
                ? { backgroundColor: colors.accent }
                : { backgroundColor: colors.surface, borderColor: colors.border, borderWidth: 1 },
            ]}
          >
            <Text
              style={[
                styles.chipText,
                { color: isActive ? colors.white : colors.muted },
              ]}
            >
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    gap: spacing[2],
  },
  chip: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[1.5],
    borderRadius: borderRadius.full,
  },
  chipText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
  },
});
