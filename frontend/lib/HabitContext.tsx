import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import type { Habit, HabitInput } from "./habit";
import { useAuth } from "./AuthContext";
import { useSyncOptional } from "./sync";
import { useHabits as useHabitsFromStore, useHabitActions, useHabitsSortedByDifficulty, LOCAL_USER_ID } from "./store";
import { completeHabit as completeHabitAction } from "./completeHabit";

interface HabitContextType {
  habits: Habit[];
  rankedHabits: Habit[];
  selectedHabit: Habit | null;
  isEditing: boolean;
  userId: string;
  createHabit: (input: HabitInput) => Promise<Habit>;
  updateHabit: (id: string, input: Partial<HabitInput>) => Promise<Habit | null>;
  deleteHabit: (id: string) => Promise<boolean>;
  completeHabit: (habit: Habit) => Promise<number>;
  selectHabit: (habit: Habit | null) => void;
  setIsEditing: (editing: boolean) => void;
}

const HabitContext = createContext<HabitContextType | null>(null);

export function HabitProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const sync = useSyncOptional();
  const actions = useHabitActions();

  // Use user ID from auth, fallback to local-user for offline mode
  const userId = user?.id ?? LOCAL_USER_ID;

  // Get habits from reactive store (fine-grained subscription)
  const habits = useHabitsFromStore(userId);
  const rankedHabits = useHabitsSortedByDifficulty(userId);

  // UI state (not persisted)
  const [selectedHabit, setSelectedHabit] = useState<Habit | null>(null);
  const [isEditing, setIsEditing] = useState(false);

  const createHabit = useCallback(
    async (input: HabitInput): Promise<Habit> => {
      const habit = await actions.createHabit(userId, input);
      // Notify sync service of change
      sync?.notifyChange();
      return habit;
    },
    [userId, sync, actions],
  );

  const updateHabit = useCallback(
    async (id: string, input: Partial<HabitInput>): Promise<Habit | null> => {
      const updated = await actions.updateHabit(id, input);
      if (updated) {
        // Notify sync service of change
        sync?.notifyChange();
      }
      return updated;
    },
    [sync, actions],
  );

  const deleteHabit = useCallback(
    async (id: string): Promise<boolean> => {
      const success = await actions.deleteHabit(id);
      if (success) {
        // Notify sync service of change
        sync?.notifyChange();
      }
      return success;
    },
    [sync, actions],
  );

  const completeHabit = useCallback(
    async (habit: Habit): Promise<number> => {
      const amount = await completeHabitAction(habit, habits, userId, () => {
        sync?.notifyChange();
      });
      return amount;
    },
    [habits, userId, sync],
  );

  const selectHabit = useCallback((habit: Habit | null) => {
    setSelectedHabit(habit);
  }, []);

  return (
    <HabitContext.Provider
      value={{
        habits,
        rankedHabits,
        selectedHabit,
        isEditing,
        userId,
        createHabit,
        updateHabit,
        deleteHabit,
        completeHabit,
        selectHabit,
        setIsEditing,
      }}
    >
      {children}
    </HabitContext.Provider>
  );
}

export function useHabitsContext(): HabitContextType {
  const context = useContext(HabitContext);
  if (!context) {
    throw new Error("useHabitsContext must be used within a HabitProvider");
  }
  return context;
}
