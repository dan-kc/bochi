CREATE TABLE earnables (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    kind TEXT NOT NULL,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(10000) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    difficulty_tier habit_difficulty_tier,
    duration_seconds INTEGER,
    importance SMALLINT,
    due_date TIMESTAMP,
    min_daily_frequency DOUBLE PRECISION,
    lockout_duration_seconds INTEGER,
    pinned BOOLEAN NOT NULL DEFAULT FALSE,
    timer_mode TEXT,
    timer_id UUID,
    hidden BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_earnables_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_earnables_timer FOREIGN KEY (timer_id) REFERENCES timers(id) ON DELETE SET NULL,
    CONSTRAINT chk_earnables_kind CHECK (kind IN ('task', 'habit')),
    CONSTRAINT chk_earnables_task_shape CHECK (
        kind <> 'task' OR (min_daily_frequency IS NULL AND lockout_duration_seconds IS NULL)
    ),
    CONSTRAINT chk_earnables_habit_shape CHECK (
        kind <> 'habit' OR due_date IS NULL
    ),
    CONSTRAINT chk_earnables_duration_seconds CHECK (
        duration_seconds IS NULL OR (duration_seconds >= 1 AND duration_seconds <= 43200)
    ),
    CONSTRAINT chk_earnables_importance CHECK (
        importance IS NULL OR (importance >= 1 AND importance <= 5)
    ),
    CONSTRAINT chk_earnables_min_daily_frequency CHECK (
        min_daily_frequency IS NULL
            OR (min_daily_frequency >= (1.0 / 30.0)::DOUBLE PRECISION
                AND min_daily_frequency <= 100.0::DOUBLE PRECISION)
    ),
    CONSTRAINT chk_earnables_lockout_duration_seconds CHECK (
        lockout_duration_seconds IS NULL
            OR (lockout_duration_seconds >= 60 AND lockout_duration_seconds <= 2592000)
    ),
    CONSTRAINT chk_earnables_timer_mode CHECK (
        timer_mode IS NULL OR timer_mode = ANY (ARRAY['named'::TEXT, 'duration'::TEXT])
    ),
    CONSTRAINT chk_earnables_timer_shape CHECK (
        timer_mode IS NULL AND timer_id IS NULL
        OR timer_mode = 'named'::TEXT AND timer_id IS NOT NULL
        OR timer_mode = 'duration'::TEXT AND timer_id IS NULL
    )
);

CREATE INDEX idx_earnables_user_kind_created
ON earnables (user_id, kind, created_at, id);

CREATE INDEX idx_earnables_user_kind_updated
ON earnables (user_id, kind, updated_at);

CREATE INDEX idx_earnables_user_updated
ON earnables (user_id, updated_at);

CREATE TRIGGER update_earnables_updated_at
BEFORE UPDATE ON earnables
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

INSERT INTO earnables (
    id,
    user_id,
    kind,
    name,
    description,
    created_at,
    updated_at,
    deleted_at,
    difficulty_tier,
    duration_seconds,
    importance,
    due_date,
    min_daily_frequency,
    lockout_duration_seconds,
    pinned,
    timer_mode,
    timer_id,
    hidden
)
SELECT
    id,
    user_id,
    'task',
    name,
    description,
    created_at,
    updated_at,
    deleted_at,
    difficulty_tier,
    duration_seconds,
    importance,
    due_date,
    NULL,
    NULL,
    pinned,
    timer_mode,
    timer_id,
    hidden
FROM tasks;

INSERT INTO earnables (
    id,
    user_id,
    kind,
    name,
    description,
    created_at,
    updated_at,
    deleted_at,
    difficulty_tier,
    duration_seconds,
    importance,
    due_date,
    min_daily_frequency,
    lockout_duration_seconds,
    pinned,
    timer_mode,
    timer_id,
    hidden
)
SELECT
    id,
    user_id,
    'habit',
    name,
    description,
    created_at,
    updated_at,
    deleted_at,
    difficulty_tier,
    duration_seconds,
    importance,
    NULL,
    min_daily_frequency,
    lockout_duration_seconds,
    pinned,
    timer_mode,
    timer_id,
    hidden
FROM habits;

ALTER TABLE trades DROP CONSTRAINT trades_task_id_fkey;
ALTER TABLE trades DROP CONSTRAINT trades_habit_id_fkey;
ALTER TABLE task_tags DROP CONSTRAINT fk_task_tags_task;
ALTER TABLE habit_tags DROP CONSTRAINT habit_tags_habit_id_fkey;
ALTER TABLE task_task_dependencies DROP CONSTRAINT fk_task_task_dependencies_task;
ALTER TABLE task_task_dependencies DROP CONSTRAINT fk_task_task_dependencies_depends_on_task;
ALTER TABLE task_habit_dependencies DROP CONSTRAINT fk_task_habit_dependencies_task;
ALTER TABLE task_habit_dependencies DROP CONSTRAINT fk_task_habit_dependencies_habit;
ALTER TABLE reward_task_dependencies DROP CONSTRAINT fk_reward_task_dependencies_depends_on_task;
ALTER TABLE reward_habit_dependencies DROP CONSTRAINT fk_reward_habit_dependencies_habit;
ALTER TABLE special_offers DROP CONSTRAINT fk_special_offers_task;
ALTER TABLE special_offers DROP CONSTRAINT fk_special_offers_habit;

ALTER TABLE trades
ADD CONSTRAINT trades_task_id_fkey
FOREIGN KEY (task_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE trades
ADD CONSTRAINT trades_habit_id_fkey
FOREIGN KEY (habit_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE task_tags
ADD CONSTRAINT fk_task_tags_task
FOREIGN KEY (task_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE habit_tags
ADD CONSTRAINT habit_tags_habit_id_fkey
FOREIGN KEY (habit_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE task_task_dependencies
ADD CONSTRAINT fk_task_task_dependencies_task
FOREIGN KEY (task_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE task_task_dependencies
ADD CONSTRAINT fk_task_task_dependencies_depends_on_task
FOREIGN KEY (depends_on_task_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE task_habit_dependencies
ADD CONSTRAINT fk_task_habit_dependencies_task
FOREIGN KEY (task_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE task_habit_dependencies
ADD CONSTRAINT fk_task_habit_dependencies_habit
FOREIGN KEY (habit_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE reward_task_dependencies
ADD CONSTRAINT fk_reward_task_dependencies_depends_on_task
FOREIGN KEY (depends_on_task_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE reward_habit_dependencies
ADD CONSTRAINT fk_reward_habit_dependencies_habit
FOREIGN KEY (habit_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE special_offers
ADD CONSTRAINT fk_special_offers_task
FOREIGN KEY (task_id) REFERENCES earnables(id) ON DELETE CASCADE;

ALTER TABLE special_offers
ADD CONSTRAINT fk_special_offers_habit
FOREIGN KEY (habit_id) REFERENCES earnables(id) ON DELETE CASCADE;

DROP TABLE tasks;
DROP TABLE habits;
