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
}

export interface TaskInput {
  name: string;
  description: string;
  deleted_at?: string | null;
  hidden_until?: string | null;
  due_by?: string | null;
  min_daily_frequency?: number | null;
}

export function createEmptyTaskInput(): TaskInput {
  return {
    name: "",
    description: "",
    deleted_at: null,
    hidden_until: null,
    due_by: null,
    min_daily_frequency: null,
  };
}
