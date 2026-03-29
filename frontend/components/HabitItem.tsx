import { Text, Pressable, StyleSheet } from "react-native";
import type { Habit } from "@/lib/habit";
import { useTagsForHabit } from "@/lib/store/hooks";
import { useColors, fontSize, fontWeight } from "@/lib/theme";
import { ListItemCard } from "./ListItemCard";
import { TagRow } from "./TagRow";
import { PriceDisplay } from "./PriceDisplay";

interface HabitItemProps {
  habit: Habit;
  onPress: (habit: Habit) => void;
  onComplete?: (habit: Habit) => void;
  onSetRank?: (habit: Habit) => void;
}

function formatFrequency(frequency: number | null): string | null {
  if (frequency == null) return null;
  const formatted = frequency.toFixed(2).replace(/\.?0+$/, "");
  return `${formatted}/day`;
}

export function HabitItem({ habit, onPress, onSetRank }: HabitItemProps) {
  const colors = useColors();
  const tags = useTagsForHabit(habit.id);

  const bottomRight = habit.difficulty_rank == null && onSetRank ? (
    <Pressable onPress={() => onSetRank(habit)}>
      <Text style={[styles.setDifficultyText, { color: colors.accent }]}>Set Difficulty</Text>
    </Pressable>
  ) : (
    <PriceDisplay habitId={habit.id} />
  );

  return (
    <ListItemCard
      name={habit.name}
      description={habit.description}
      subtitle={formatFrequency(habit.min_daily_frequency)}
      tags={<TagRow tags={tags} />}
      bottomRight={bottomRight}
      onPress={() => onPress(habit)}
    />
  );
}

const styles = StyleSheet.create({
  setDifficultyText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
  },
});
