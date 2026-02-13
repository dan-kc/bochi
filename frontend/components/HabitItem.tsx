import { View, Pressable } from "react-native";
import type { Habit } from "@/lib/habit";
import { FadingText } from "./FadingText";
import { PriceDisplay } from "./PriceDisplay";
import { HabitTagRow } from "./HabitTagRow";

interface HabitItemProps {
  habit: Habit;
  onPress: (habit: Habit) => void;
}

function formatFrequency(frequency: number | null): string | null {
  if (frequency == null) return null;
  const formatted = frequency.toFixed(2).replace(/\.?0+$/, "");
  return `${formatted}/day`;
}

export function HabitItem({ habit, onPress }: HabitItemProps) {
  const frequencyText = formatFrequency(habit.min_daily_frequency);

  return (
    <Pressable
      onPress={() => onPress(habit)}
      className="border rounded-lg p-4 mb-3 bg-white border-gray-200"
    >
      {({ hovered }) => (
        <View className={hovered ? "opacity-80" : ""}>
          {/* Habit Name - max 3 lines */}
          <FadingText
            numberOfLines={3}
            className="text-lg font-semibold text-gray-900"
          >
            {habit.name}
          </FadingText>

          {/* Description - 1 line, only if exists */}
          {habit.description ? (
            <FadingText
              numberOfLines={1}
              className="text-gray-600 text-sm mt-1"
            >
              {habit.description}
            </FadingText>
          ) : null}

          {/* Frequency - 1 line */}
          {frequencyText ? (
            <FadingText
              numberOfLines={1}
              className="text-green-700 text-sm mt-1"
            >
              {frequencyText}
            </FadingText>
          ) : null}

          {/* Tags - single line with fade */}
          <View className="mt-1">
            <HabitTagRow habitId={habit.id} />
          </View>

          {/* Price Display - right-aligned on its own row */}
          <View className="items-end mt-2">
            <PriceDisplay habitId={habit.id} />
          </View>
        </View>
      )}
    </Pressable>
  );
}
