import type { Habit, HabitInput } from "@/lib/habit";
import { usePriceUpdateOptional } from "@/lib/PriceUpdateContext";
import { useTagsForHabit, useTagActions, useHabitTagActions } from "@/lib/store/hooks";
import { ChangeForm, type ChangeFormConfig, type ChangeFormEntity } from "./ChangeForm";

interface HabitFormProps {
  habit?: Habit | null;
  userId: string;
  onSave: (input: HabitInput) => Promise<void>;
  onClose: () => void;
  onDelete?: () => Promise<void>;
  onRerank?: () => void;
  onComplete?: (habit: Habit) => Promise<void>;
}

const HABIT_CONFIG: ChangeFormConfig = {
  entityType: "habit",
  entityLabel: "Habit",
  frequencyLabel: "Frequency",
  frequencyField: "min_daily_frequency",
  rankLabel: "Difficulty",
  actionLabel: "Trade",
};

export function HabitForm({ habit, userId, onSave, onClose, onDelete, onRerank, onComplete }: HabitFormProps) {
  const habitTags = useTagsForHabit(habit?.id ?? "");
  const { updateTag } = useTagActions();
  const { addTagToHabit, removeTagFromHabit } = useHabitTagActions();
  const priceContext = usePriceUpdateOptional();
  const tradeAmount = habit ? (priceContext?.prices[habit.id]?.current ?? null) : null;

  return (
    <ChangeForm
      config={HABIT_CONFIG}
      entity={habit}
      userId={userId}
      tags={habitTags}
      tradeAmount={tradeAmount}
      onSave={(input) => onSave(input as unknown as HabitInput)}
      onClose={onClose}
      onDelete={onDelete}
      onRerank={onRerank}
      onAction={onComplete ? (entity) => onComplete(entity as unknown as Habit) : undefined}
      tagActions={{ addTag: addTagToHabit, removeTag: removeTagFromHabit }}
      updateTag={updateTag}
    />
  );
}
