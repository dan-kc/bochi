import { Text, Pressable } from "react-native";
import type { Habit } from "@/lib/habit";
import { useTagsForHabit } from "@/lib/store/hooks";
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
  const tags = useTagsForHabit(habit.id);

  const bottomRight = habit.difficulty_rank == null && onSetRank ? (
    <Pressable onPress={() => onSetRank(habit)}>
      <Text className="text-sm font-medium text-accent">Set Difficulty</Text>
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
