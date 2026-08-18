-- Add habit boolean field (default false for existing tasks)
ALTER TABLE tasks ADD COLUMN habit BOOLEAN NOT NULL DEFAULT false;

-- Set habit=true for tasks that currently have min_daily_frequency
UPDATE tasks SET habit = true WHERE min_daily_frequency IS NOT NULL;

-- Remove old constraint (no longer needed - habit field now controls this)
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS check_due_by_or_min_daily_frequency;

-- Constraint: habits cannot have completed_at
ALTER TABLE tasks ADD CONSTRAINT check_habit_no_completed_at
    CHECK (NOT (habit = true AND completed_at IS NOT NULL));

-- Constraint: non-habits cannot have min_daily_frequency
ALTER TABLE tasks ADD CONSTRAINT check_non_habit_no_frequency
    CHECK (NOT (habit = false AND min_daily_frequency IS NOT NULL));

-- Constraint: trades must have exactly one of task_id or reward_id
ALTER TABLE trades ADD CONSTRAINT check_trade_task_or_reward
    CHECK ((task_id IS NOT NULL) != (reward_id IS NOT NULL));
