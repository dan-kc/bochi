import { View, Text, StyleSheet } from "react-native";
import type { Tag } from "@/lib/tag";
import { FadingContainer } from "./FadingContainer";
import { spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

interface TagRowProps {
  tags: Tag[];
}

export function TagRow({ tags }: TagRowProps) {
  if (tags.length === 0) return null;

  return (
    <FadingContainer fadeWidth={30} style={styles.container}>
      <View style={styles.row}>
        {tags.map((tag) => (
          <View
            key={tag.id}
            style={[styles.tag, { backgroundColor: tag.color_hex + "30" }]}
          >
            <Text
              style={[styles.tagText, { color: tag.color_hex }]}
              numberOfLines={1}
            >
              {tag.name}
            </Text>
          </View>
        ))}
      </View>
    </FadingContainer>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  row: {
    flexDirection: "row",
    gap: spacing[1],
  },
  tag: {
    paddingHorizontal: spacing[2],
    paddingVertical: spacing[0.5],
    borderRadius: borderRadius.DEFAULT,
    flexShrink: 1,
  },
  tagText: {
    fontSize: fontSize.xs,
    fontWeight: fontWeight.medium,
  },
});
