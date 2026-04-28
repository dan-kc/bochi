CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(10000) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    completed_at TIMESTAMP,
    difficulty_tier habit_difficulty_tier,
    duration_seconds INTEGER,
    skip_consequence SMALLINT,
    due_date TIMESTAMP,
    CONSTRAINT fk_tasks_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT chk_tasks_duration_seconds CHECK (
        duration_seconds IS NULL OR (duration_seconds >= 1 AND duration_seconds <= 43200)
    ),
    CONSTRAINT chk_tasks_skip_consequence CHECK (
        skip_consequence IS NULL OR (skip_consequence >= 1 AND skip_consequence <= 5)
    )
);

CREATE INDEX idx_tasks_user_created
ON tasks (user_id, created_at, id);

CREATE INDEX idx_tasks_user_updated
ON tasks (user_id, updated_at);

CREATE TRIGGER update_tasks_updated_at
BEFORE UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE task_tags (
    task_id UUID NOT NULL,
    tag_id UUID NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    PRIMARY KEY (task_id, tag_id),
    CONSTRAINT fk_task_tags_task FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_task_tags_tag FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX idx_task_tags_updated
ON task_tags (updated_at);

CREATE TRIGGER update_task_tags_updated_at
BEFORE UPDATE ON task_tags
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE trades
ADD COLUMN task_id UUID;

ALTER TABLE trades
DROP CONSTRAINT check_trade_habit_or_reward;

ALTER TABLE trades
ADD CONSTRAINT check_trade_task_habit_or_reward CHECK (
    ((task_id IS NOT NULL)::int + (habit_id IS NOT NULL)::int + (reward_id IS NOT NULL)::int) = 1
);

ALTER TABLE trades
ADD CONSTRAINT trades_task_id_fkey
FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE;
