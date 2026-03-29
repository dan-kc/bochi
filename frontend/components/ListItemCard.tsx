import { View, Pressable, StyleSheet } from "react-native";
import type { ReactNode } from "react";
import { FadingText } from "./FadingText";
import { useColors, spacing, fontSize, fontWeight } from "@/lib/theme";

interface ListItemCardProps {
  name: string;
  description?: string | null;
  subtitle?: string | null;
  tags?: ReactNode;
  bottomRight?: ReactNode;
  onPress: () => void;
}

export function ListItemCard({
  name,
  description,
  subtitle,
  tags,
  bottomRight,
  onPress,
}: ListItemCardProps) {
  const colors = useColors();

  return (
    <Pressable onPress={onPress} style={[styles.container, { borderBottomColor: colors.border }]}>
      {({ hovered }) => (
        <View style={hovered ? styles.hovered : undefined}>
          <FadingText
            numberOfLines={3}
            style={[styles.nameText, { color: colors.foreground }]}
          >
            {name}
          </FadingText>

          {description ? (
            <FadingText
              numberOfLines={1}
              style={[styles.descriptionText, { color: colors.muted }]}
            >
              {description}
            </FadingText>
          ) : null}

          {subtitle ? (
            <FadingText
              numberOfLines={1}
              style={[styles.subtitleText, { color: colors.accentSecondary }]}
            >
              {subtitle}
            </FadingText>
          ) : null}

          {tags ? <View style={styles.tagsContainer}>{tags}</View> : null}

          {bottomRight ? (
            <View style={styles.bottomRightContainer}>{bottomRight}</View>
          ) : null}
        </View>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    borderBottomWidth: 1,
    paddingVertical: spacing[4],
    paddingHorizontal: spacing[2],
  },
  hovered: {
    opacity: 0.8,
  },
  nameText: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
  },
  descriptionText: {
    fontSize: fontSize.sm,
    marginTop: spacing[1],
  },
  subtitleText: {
    fontSize: fontSize.sm,
    marginTop: spacing[1],
  },
  tagsContainer: {
    marginTop: spacing[1],
  },
  bottomRightContainer: {
    alignItems: "flex-end",
    marginTop: spacing[2],
  },
});
