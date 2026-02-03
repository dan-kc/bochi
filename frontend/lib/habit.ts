export interface Habit {
  id: string;
  user_id: string;
  name: string;
  description: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  hidden_until: string | null;
  min_daily_frequency: number | null;
  difficulty_rank: string | null;
}

export interface HabitInput {
  name: string;
  description: string;
  deleted_at?: string | null;
  hidden_until?: string | null;
  min_daily_frequency?: number | null;
  difficulty_rank?: string | null;
}

export function createEmptyHabitInput(): HabitInput {
  return {
    name: "",
    description: "",
    deleted_at: null,
    hidden_until: null,
    min_daily_frequency: null,
    difficulty_rank: null,
  };
}
