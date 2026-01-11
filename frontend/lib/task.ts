export interface Task {
  id: string;
  user_id: string;
  name: string;
  description: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  hidden_until: string | null;
  due_by: string | null;
  min_daily_frequency: number | null;
  difficulty_rank: string | null;
  completed_at: string | null;
}

export interface TaskInput {
  name: string;
  description: string;
  deleted_at?: string | null;
  hidden_until?: string | null;
  due_by?: string | null;
  min_daily_frequency?: number | null;
  difficulty_rank?: string | null;
  completed_at?: string | null;
}

export function createEmptyTaskInput(): TaskInput {
  return {
    name: "",
    description: "",
    deleted_at: null,
    hidden_until: null,
    due_by: null,
    min_daily_frequency: null,
    difficulty_rank: null,
    completed_at: null,
  };
}

/**
 * Returns true if this task is a habit (has min_daily_frequency)
 */
export function isHabit(task: Task): boolean {
  return task.min_daily_frequency !== null;
}
