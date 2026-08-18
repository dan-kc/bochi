-- Add user_id column to trades table (required for merge/sync support)
ALTER TABLE trades ADD COLUMN user_id UUID;

-- Populate user_id from tasks for existing trades (where task_id is not null)
UPDATE trades SET user_id = tasks.user_id
FROM tasks WHERE trades.task_id = tasks.id AND trades.user_id IS NULL;

-- Populate user_id from rewards for existing trades (where reward_id is not null)
UPDATE trades SET user_id = rewards.user_id
FROM rewards WHERE trades.reward_id = rewards.id AND trades.user_id IS NULL;

-- Make user_id NOT NULL after population
ALTER TABLE trades ALTER COLUMN user_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE trades ADD CONSTRAINT trades_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Add completed_at to tasks (for non-habit task completion tracking)
ALTER TABLE tasks ADD COLUMN completed_at TIMESTAMP;
