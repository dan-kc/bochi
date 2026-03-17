import { View, Text } from "react-native";
import type { Tag } from "@/lib/tag";
import { FadingContainer } from "./FadingContainer";

interface TagRowProps {
  tags: Tag[];
}

export function TagRow({ tags }: TagRowProps) {
  if (tags.length === 0) return null;

  return (
    <FadingContainer fadeWidth={30} className="flex-1">
      <View className="flex-row gap-1">
        {tags.map((tag) => (
          <View
            key={tag.id}
            className="px-2 py-0.5 rounded shrink-0"
            style={{ backgroundColor: tag.color_hex + "30" }}
          >
            <Text
              className="text-xs font-medium"
              style={{ color: tag.color_hex }}
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
