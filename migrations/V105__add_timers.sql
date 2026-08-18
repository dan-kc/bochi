CREATE TABLE timers (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(50) NOT NULL,
    sections JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    CONSTRAINT chk_timers_name_length CHECK (char_length(name) BETWEEN 1 AND 50),
    CONSTRAINT chk_timers_sections_array CHECK (jsonb_typeof(sections) = 'array'),
    CONSTRAINT chk_timers_sections_not_empty CHECK (jsonb_array_length(sections) > 0)
);

CREATE INDEX idx_timers_user_updated
ON timers (user_id, updated_at);

CREATE TRIGGER update_timers_updated_at
BEFORE UPDATE ON timers
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE tasks
ADD COLUMN timer_mode TEXT,
ADD COLUMN timer_id UUID REFERENCES timers(id) ON DELETE SET NULL,
ADD CONSTRAINT chk_tasks_timer_mode CHECK (timer_mode IS NULL OR timer_mode IN ('named', 'duration')),
ADD CONSTRAINT chk_tasks_timer_shape CHECK (
    (timer_mode IS NULL AND timer_id IS NULL)
    OR (timer_mode = 'named' AND timer_id IS NOT NULL)
    OR (timer_mode = 'duration' AND timer_id IS NULL)
);

ALTER TABLE habits
ADD COLUMN timer_mode TEXT,
ADD COLUMN timer_id UUID REFERENCES timers(id) ON DELETE SET NULL,
ADD CONSTRAINT chk_habits_timer_mode CHECK (timer_mode IS NULL OR timer_mode IN ('named', 'duration')),
ADD CONSTRAINT chk_habits_timer_shape CHECK (
    (timer_mode IS NULL AND timer_id IS NULL)
    OR (timer_mode = 'named' AND timer_id IS NOT NULL)
    OR (timer_mode = 'duration' AND timer_id IS NULL)
);

ALTER TABLE rewards
ADD COLUMN timer_mode TEXT,
ADD COLUMN timer_id UUID REFERENCES timers(id) ON DELETE SET NULL,
ADD CONSTRAINT chk_rewards_timer_mode CHECK (timer_mode IS NULL OR timer_mode = 'named'),
ADD CONSTRAINT chk_rewards_timer_shape CHECK (
    (timer_mode IS NULL AND timer_id IS NULL)
    OR (timer_mode = 'named' AND timer_id IS NOT NULL)
);
