import { useCallback } from "react";
import { View, Pressable } from "react-native";
import type { Habit } from "@/lib/habit";
import { FadingText } from "./FadingText";
import { PriceDisplay } from "./PriceDisplay";
import { HabitTagRow } from "./HabitTagRow";
import { SwipeableRow } from "./SwipeableRow";

interface HabitItemProps {
  habit: Habit;
  onPress: (habit: Habit) => void;
  onComplete?: (habit: Habit) => void;
}

function formatFrequency(frequency: number | null): string | null {
  if (frequency == null) return null;
  const formatted = frequency.toFixed(2).replace(/\.?0+$/, "");
  return `${formatted}/day`;
}

export function HabitItem({ habit, onPress, onComplete }: HabitItemProps) {
  const frequencyText = formatFrequency(habit.min_daily_frequency);

  const handleAction = useCallback(() => {
    onComplete?.(habit);
  }, [onComplete, habit]);

  const content = (
    <Pressable
      onPress={() => onPress(habit)}
      className="border-b border-border py-4 px-2 bg-background"
    >
      {({ hovered }) => (
        <View className={hovered ? "opacity-80" : ""}>
          <FadingText
            numberOfLines={3}
            className="text-lg font-semibold text-foreground"
          >
            {habit.name}
          </FadingText>

          {habit.description ? (
            <FadingText
              numberOfLines={1}
              className="text-muted text-sm mt-1"
            >
              {habit.description}
            </FadingText>
          ) : null}

          {frequencyText ? (
            <FadingText
              numberOfLines={1}
              className="text-accent-secondary text-sm mt-1"
            >
              {frequencyText}
            </FadingText>
          ) : null}

          <View className="mt-1">
            <HabitTagRow habitId={habit.id} />
          </View>

          <View className="items-end mt-2">
            <PriceDisplay habitId={habit.id} />
          </View>
        </View>
      )}
    </Pressable>
  );

  if (!onComplete) return content;

  return (
    <SwipeableRow
      onAction={handleAction}
      actionColor="#197291"
      actionIcon="checkmark-circle"
    >
      {content}
    </SwipeableRow>
  );
}
