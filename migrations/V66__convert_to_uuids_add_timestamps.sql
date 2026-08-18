-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- ============================================================================
-- STEP 1: Add new UUID columns and timestamp columns to all tables
-- ============================================================================

-- users table
ALTER TABLE users ADD COLUMN id_uuid UUID DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE users ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP;

-- tasks table
ALTER TABLE tasks ADD COLUMN id_uuid UUID DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE tasks ADD COLUMN user_id_uuid UUID;
ALTER TABLE tasks ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;

-- rewards table
ALTER TABLE rewards ADD COLUMN id_uuid UUID DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE rewards ADD COLUMN user_id_uuid UUID;
ALTER TABLE rewards ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;

-- tags table
ALTER TABLE tags ADD COLUMN id_uuid UUID DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE tags ADD COLUMN user_id_uuid UUID;
ALTER TABLE tags ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE tags ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE tags ADD COLUMN deleted_at TIMESTAMP;

-- trades table
ALTER TABLE trades ADD COLUMN id_uuid UUID DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE trades ADD COLUMN task_id_uuid UUID;
ALTER TABLE trades ADD COLUMN reward_id_uuid UUID;
ALTER TABLE trades ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE trades ADD COLUMN deleted_at TIMESTAMP;

-- task_tags table
ALTER TABLE task_tags ADD COLUMN task_id_uuid UUID;
ALTER TABLE task_tags ADD COLUMN tag_id_uuid UUID;
ALTER TABLE task_tags ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE task_tags ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE task_tags ADD COLUMN deleted_at TIMESTAMP;

-- task_dependencies table
ALTER TABLE task_dependencies ADD COLUMN task_id_uuid UUID;
ALTER TABLE task_dependencies ADD COLUMN depends_on_task_id_uuid UUID;
ALTER TABLE task_dependencies ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE task_dependencies ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE task_dependencies ADD COLUMN deleted_at TIMESTAMP;

-- refresh_tokens table (no id column, composite PK)
ALTER TABLE refresh_tokens ADD COLUMN user_id_uuid UUID;
ALTER TABLE refresh_tokens ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL;
ALTER TABLE refresh_tokens ADD COLUMN deleted_at TIMESTAMP;

-- ============================================================================
-- STEP 2: Populate UUID foreign key columns by joining with referenced tables
-- ============================================================================

-- tasks.user_id_uuid
UPDATE tasks SET user_id_uuid = users.id_uuid FROM users WHERE tasks.user_id = users.id;

-- rewards.user_id_uuid
UPDATE rewards SET user_id_uuid = users.id_uuid FROM users WHERE rewards.user_id = users.id;

-- tags.user_id_uuid
UPDATE tags SET user_id_uuid = users.id_uuid FROM users WHERE tags.user_id = users.id;

-- trades.task_id_uuid
UPDATE trades SET task_id_uuid = tasks.id_uuid FROM tasks WHERE trades.task_id = tasks.id;

-- trades.reward_id_uuid
UPDATE trades SET reward_id_uuid = rewards.id_uuid FROM rewards WHERE trades.reward_id = rewards.id;

-- task_tags.task_id_uuid
UPDATE task_tags SET task_id_uuid = tasks.id_uuid FROM tasks WHERE task_tags.task_id = tasks.id;

-- task_tags.tag_id_uuid
UPDATE task_tags SET tag_id_uuid = tags.id_uuid FROM tags WHERE task_tags.tag_id = tags.id;

-- task_dependencies.task_id_uuid
UPDATE task_dependencies SET task_id_uuid = tasks.id_uuid FROM tasks WHERE task_dependencies.task_id = tasks.id;

-- task_dependencies.depends_on_task_id_uuid
UPDATE task_dependencies SET depends_on_task_id_uuid = tasks.id_uuid FROM tasks WHERE task_dependencies.depends_on_task_id = tasks.id;

-- refresh_tokens.user_id_uuid
UPDATE refresh_tokens SET user_id_uuid = users.id_uuid FROM users WHERE refresh_tokens.user_id = users.id;

-- ============================================================================
-- STEP 3: Drop all old constraints
-- ============================================================================

-- Drop foreign key constraints
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_user_id_fkey;
ALTER TABLE rewards DROP CONSTRAINT IF EXISTS fk_user;
ALTER TABLE tags DROP CONSTRAINT IF EXISTS tags_user_id_fkey;
ALTER TABLE trades DROP CONSTRAINT IF EXISTS trades_task_id_fkey;
ALTER TABLE trades DROP CONSTRAINT IF EXISTS trades_reward_id_fkey;
ALTER TABLE task_tags DROP CONSTRAINT IF EXISTS task_tags_task_id_fkey;
ALTER TABLE task_tags DROP CONSTRAINT IF EXISTS task_tags_tag_id_fkey;
ALTER TABLE task_dependencies DROP CONSTRAINT IF EXISTS task_dependencies_task_id_fkey;
ALTER TABLE task_dependencies DROP CONSTRAINT IF EXISTS task_dependencies_depends_on_task_id_fkey;
ALTER TABLE refresh_tokens DROP CONSTRAINT IF EXISTS fk_user;

-- Drop primary key constraints
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_pkey;
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_pkey;
ALTER TABLE rewards DROP CONSTRAINT IF EXISTS rewards_pkey;
ALTER TABLE tags DROP CONSTRAINT IF EXISTS tags_pkey;
ALTER TABLE trades DROP CONSTRAINT IF EXISTS trades_pkey;
ALTER TABLE task_tags DROP CONSTRAINT IF EXISTS task_tags_pkey;
ALTER TABLE task_dependencies DROP CONSTRAINT IF EXISTS task_dependencies_pkey;
ALTER TABLE refresh_tokens DROP CONSTRAINT IF EXISTS refresh_tokens_pkey;

-- Drop unique constraints that reference old columns
ALTER TABLE tags DROP CONSTRAINT IF EXISTS unique_user_id_name;
ALTER TABLE task_tags DROP CONSTRAINT IF EXISTS unique_task_id_tag_id;

-- ============================================================================
-- STEP 4: Drop old integer ID columns
-- ============================================================================

ALTER TABLE users DROP COLUMN id;
ALTER TABLE tasks DROP COLUMN id;
ALTER TABLE tasks DROP COLUMN user_id;
ALTER TABLE rewards DROP COLUMN id;
ALTER TABLE rewards DROP COLUMN user_id;
ALTER TABLE tags DROP COLUMN id;
ALTER TABLE tags DROP COLUMN user_id;
ALTER TABLE trades DROP COLUMN id;
ALTER TABLE trades DROP COLUMN task_id;
ALTER TABLE trades DROP COLUMN reward_id;
ALTER TABLE task_tags DROP COLUMN task_id;
ALTER TABLE task_tags DROP COLUMN tag_id;
ALTER TABLE task_dependencies DROP COLUMN task_id;
ALTER TABLE task_dependencies DROP COLUMN depends_on_task_id;
ALTER TABLE refresh_tokens DROP COLUMN user_id;

-- ============================================================================
-- STEP 5: Rename UUID columns to their final names
-- ============================================================================

ALTER TABLE users RENAME COLUMN id_uuid TO id;
ALTER TABLE tasks RENAME COLUMN id_uuid TO id;
ALTER TABLE tasks RENAME COLUMN user_id_uuid TO user_id;
ALTER TABLE rewards RENAME COLUMN id_uuid TO id;
ALTER TABLE rewards RENAME COLUMN user_id_uuid TO user_id;
ALTER TABLE tags RENAME COLUMN id_uuid TO id;
ALTER TABLE tags RENAME COLUMN user_id_uuid TO user_id;
ALTER TABLE trades RENAME COLUMN id_uuid TO id;
ALTER TABLE trades RENAME COLUMN task_id_uuid TO task_id;
ALTER TABLE trades RENAME COLUMN reward_id_uuid TO reward_id;
ALTER TABLE task_tags RENAME COLUMN task_id_uuid TO task_id;
ALTER TABLE task_tags RENAME COLUMN tag_id_uuid TO tag_id;
ALTER TABLE task_dependencies RENAME COLUMN task_id_uuid TO task_id;
ALTER TABLE task_dependencies RENAME COLUMN depends_on_task_id_uuid TO depends_on_task_id;
ALTER TABLE refresh_tokens RENAME COLUMN user_id_uuid TO user_id;

-- ============================================================================
-- STEP 6: Add NOT NULL constraints to UUID foreign keys
-- ============================================================================

ALTER TABLE tasks ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE rewards ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE tags ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE task_tags ALTER COLUMN task_id SET NOT NULL;
ALTER TABLE task_tags ALTER COLUMN tag_id SET NOT NULL;
ALTER TABLE task_dependencies ALTER COLUMN task_id SET NOT NULL;
ALTER TABLE task_dependencies ALTER COLUMN depends_on_task_id SET NOT NULL;
ALTER TABLE refresh_tokens ALTER COLUMN user_id SET NOT NULL;

-- ============================================================================
-- STEP 7: Add new primary key constraints
-- ============================================================================

ALTER TABLE users ADD PRIMARY KEY (id);
ALTER TABLE tasks ADD PRIMARY KEY (id);
ALTER TABLE rewards ADD PRIMARY KEY (id);
ALTER TABLE tags ADD PRIMARY KEY (id);
ALTER TABLE trades ADD PRIMARY KEY (id);
ALTER TABLE task_tags ADD PRIMARY KEY (task_id, tag_id);
ALTER TABLE task_dependencies ADD PRIMARY KEY (task_id, depends_on_task_id);
ALTER TABLE refresh_tokens ADD PRIMARY KEY (name, user_id);

-- ============================================================================
-- STEP 8: Add new foreign key constraints
-- ============================================================================

ALTER TABLE tasks ADD CONSTRAINT tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE rewards ADD CONSTRAINT rewards_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE tags ADD CONSTRAINT tags_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE trades ADD CONSTRAINT trades_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE;
ALTER TABLE trades ADD CONSTRAINT trades_reward_id_fkey FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE CASCADE;
ALTER TABLE task_tags ADD CONSTRAINT task_tags_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE;
ALTER TABLE task_tags ADD CONSTRAINT task_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE;
ALTER TABLE task_dependencies ADD CONSTRAINT task_dependencies_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE;
ALTER TABLE task_dependencies ADD CONSTRAINT task_dependencies_depends_on_task_id_fkey FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id) ON DELETE CASCADE;
ALTER TABLE refresh_tokens ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- ============================================================================
-- STEP 9: Re-add unique constraints and check constraints
-- ============================================================================

ALTER TABLE tags ADD CONSTRAINT unique_user_id_name UNIQUE (user_id, name);
ALTER TABLE task_tags ADD CONSTRAINT unique_task_id_tag_id UNIQUE (task_id, tag_id);
ALTER TABLE task_dependencies ADD CONSTRAINT check_task_id_diff_depends_on_task_id CHECK (task_id <> depends_on_task_id);

-- ============================================================================
-- STEP 10: Create triggers for updated_at columns
-- ============================================================================

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_rewards_updated_at BEFORE UPDATE ON rewards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tags_updated_at BEFORE UPDATE ON tags
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trades_updated_at BEFORE UPDATE ON trades
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_task_tags_updated_at BEFORE UPDATE ON task_tags
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_task_dependencies_updated_at BEFORE UPDATE ON task_dependencies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_refresh_tokens_updated_at BEFORE UPDATE ON refresh_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
