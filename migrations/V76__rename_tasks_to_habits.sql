-- Rename tasks table to habits and remove task-specific fields
-- This migration converts the app from a task/todo tracker to a pure habit tracker

-- First, drop dependent tables that reference tasks
DROP TABLE IF EXISTS task_dependencies CASCADE;
DROP TABLE IF EXISTS task_tags CASCADE;

-- Drop constraints on trades table that reference tasks
ALTER TABLE trades DROP CONSTRAINT IF EXISTS check_trade_task_or_reward;
ALTER TABLE trades DROP CONSTRAINT IF EXISTS trades_task_id_fkey;

-- Rename task_id column to habit_id in trades
ALTER TABLE trades RENAME COLUMN task_id TO habit_id;

-- Rename the tasks table to habits
ALTER TABLE tasks RENAME TO habits;

-- Drop task-specific columns from habits table
-- Drop constraints first
ALTER TABLE habits DROP CONSTRAINT IF EXISTS check_habit_no_completed_at;
ALTER TABLE habits DROP CONSTRAINT IF EXISTS check_non_habit_no_frequency;

-- Drop the columns
ALTER TABLE habits DROP COLUMN IF EXISTS due_by;
ALTER TABLE habits DROP COLUMN IF EXISTS completed_at;
ALTER TABLE habits DROP COLUMN IF EXISTS habit;

-- Re-add foreign key constraint with new name
ALTER TABLE trades
ADD CONSTRAINT trades_habit_id_fkey
FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE;

-- Re-add check constraint with updated column name
ALTER TABLE trades
ADD CONSTRAINT check_trade_habit_or_reward
CHECK ((habit_id IS NOT NULL) <> (reward_id IS NOT NULL));

-- Rename index if it exists
ALTER INDEX IF EXISTS tasks_pkey RENAME TO habits_pkey;
ALTER INDEX IF EXISTS idx_tasks_difficulty_rank RENAME TO idx_habits_difficulty_rank;

-- Drop the old update trigger and recreate for habits table
DROP TRIGGER IF EXISTS update_tasks_updated_at ON habits;
CREATE TRIGGER update_habits_updated_at
BEFORE UPDATE ON habits
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
