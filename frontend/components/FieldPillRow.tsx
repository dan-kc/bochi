import { ScrollView, Pressable, Text } from "react-native";
import Animated, { FadeIn, LinearTransition } from "react-native-reanimated";

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
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ gap: 8 }}
    >
      {pills.map((pill) => (
        <Animated.View
          key={pill.key}
          entering={isSettled ? FadeIn.duration(200) : undefined}
          layout={isSettled ? LinearTransition.duration(200) : undefined}
        >
          <Pressable
            onPress={pill.onPress}
            className={`px-4 py-1.5 rounded-full border ${
              pill.isSet ? "bg-surface border-border" : "bg-transparent border-border/50"
            }`}
          >
            <Text
              className={`text-sm font-medium ${pill.isSet ? "text-foreground" : "text-muted"}`}
            >
              {pill.label}
            </Text>
          </Pressable>
        </Animated.View>
      ))}
    </ScrollView>
  );
}
