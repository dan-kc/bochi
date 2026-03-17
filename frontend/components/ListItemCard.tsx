import { View, Pressable } from "react-native";
import type { ReactNode } from "react";
import { FadingText } from "./FadingText";

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
  return (
    <Pressable onPress={onPress} className="border-b border-border py-4 px-2">
      {({ hovered }) => (
        <View className={hovered ? "opacity-80" : ""}>
          <FadingText
            numberOfLines={3}
            className="text-lg font-semibold text-foreground"
          >
            {name}
          </FadingText>

          {description ? (
            <FadingText
              numberOfLines={1}
              className="text-muted text-sm mt-1"
            >
              {description}
            </FadingText>
          ) : null}

          {subtitle ? (
            <FadingText
              numberOfLines={1}
              className="text-accent-secondary text-sm mt-1"
            >
              {subtitle}
            </FadingText>
          ) : null}

          {tags ? <View className="mt-1">{tags}</View> : null}

          {bottomRight ? (
            <View className="items-end mt-2">{bottomRight}</View>
          ) : null}
        </View>
      )}
    </Pressable>
  );
}
