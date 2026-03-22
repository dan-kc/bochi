import type { Habit, HabitInput } from "@/lib/habit";
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
  actionLabel: "Complete",
};

export function HabitForm({ habit, userId, onSave, onClose, onDelete, onRerank, onComplete }: HabitFormProps) {
  const habitTags = useTagsForHabit(habit?.id ?? "");
  const { updateTag } = useTagActions();
  const { addTagToHabit, removeTagFromHabit } = useHabitTagActions();

  return (
    <ChangeForm
      config={HABIT_CONFIG}
      entity={habit}
      userId={userId}
      tags={habitTags}
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
