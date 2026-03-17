import type { Habit } from "@/lib/habit";
import { useTagsForHabit } from "@/lib/store/hooks";
import { ListItemCard } from "./ListItemCard";
import { TagRow } from "./TagRow";
import { PriceDisplay } from "./PriceDisplay";

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
  const tags = useTagsForHabit(habit.id);

  return (
    <ListItemCard
      name={habit.name}
      description={habit.description}
      subtitle={formatFrequency(habit.min_daily_frequency)}
      tags={<TagRow tags={tags} />}
      bottomRight={<PriceDisplay habitId={habit.id} />}
      onPress={() => onPress(habit)}
    />
  );
}
