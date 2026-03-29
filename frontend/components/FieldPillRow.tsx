import { ScrollView, Pressable, Text, StyleSheet } from "react-native";
import Animated, { FadeIn, LinearTransition } from "react-native-reanimated";
import { useColors, fontSize, fontWeight, spacing, borderRadius } from "@/lib/theme";

export interface FieldPill {
  key: string;
  label: string;
  isSet: boolean;
  onPress: () => void;
}

interface FieldPillRowProps {
  pills: FieldPill[];
  isSettled?: boolean;
}

export function FieldPillRow({ pills, isSettled }: FieldPillRowProps) {
  const colors = useColors();

  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.scrollContent}
    >
      {pills.map((pill) => (
        <Animated.View
          key={pill.key}
          entering={isSettled ? FadeIn.duration(200) : undefined}
          layout={isSettled ? LinearTransition.duration(200) : undefined}
        >
          <Pressable
            onPress={pill.onPress}
            style={[
              styles.pill,
              {
                backgroundColor: pill.isSet ? colors.surface : "transparent",
                borderColor: pill.isSet ? colors.border : `${colors.border}80`,
              },
            ]}
          >
            <Text
              style={[
                styles.pillText,
                { color: pill.isSet ? colors.foreground : colors.muted },
              ]}
            >
              {pill.label}
            </Text>
          </Pressable>
        </Animated.View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scrollContent: {
    gap: spacing[2],
  },
  pill: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[1.5],
    borderRadius: borderRadius.full,
    borderWidth: 1,
  },
  pillText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
  },
});
