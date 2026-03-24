import { useRef, useEffect } from "react";
import { ScrollView, Pressable, Text } from "react-native";
import Animated, { FadeIn, FadeOut, LinearTransition } from "react-native-reanimated";

export interface FieldPill {
  key: string;
  label: string;
  isSet: boolean;
  onPress: () => void;
}

interface FieldPillRowProps {
  pills: FieldPill[];
}

export function FieldPillRow({ pills }: FieldPillRowProps) {
  const hasMounted = useRef(false);
  useEffect(() => {
    hasMounted.current = true;
  }, []);

  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ gap: 8 }}
    >
      {pills.map((pill) => (
        <Animated.View
          key={pill.key}
          entering={hasMounted.current ? FadeIn.duration(200) : undefined}
          exiting={FadeOut.duration(200)}
          layout={LinearTransition.duration(200)}
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
