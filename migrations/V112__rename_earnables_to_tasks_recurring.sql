ALTER TABLE earnables ADD COLUMN recurring BOOLEAN;

UPDATE earnables
SET recurring = kind = 'habit';

ALTER TABLE earnables ALTER COLUMN recurring SET NOT NULL;

ALTER TABLE earnables DROP CONSTRAINT chk_earnables_kind;
ALTER TABLE earnables DROP CONSTRAINT chk_earnables_task_shape;
ALTER TABLE earnables DROP CONSTRAINT chk_earnables_habit_shape;

DROP INDEX idx_earnables_user_kind_created;
DROP INDEX idx_earnables_user_kind_updated;

ALTER TABLE earnables DROP COLUMN kind;

ALTER TABLE earnables RENAME TO tasks;

ALTER TABLE tasks RENAME CONSTRAINT earnables_pkey TO tasks_pkey;
ALTER TABLE tasks RENAME CONSTRAINT fk_earnables_user TO fk_tasks_user;
ALTER TABLE tasks RENAME CONSTRAINT fk_earnables_timer TO fk_tasks_timer;
ALTER TABLE tasks RENAME CONSTRAINT chk_earnables_duration_seconds TO chk_tasks_duration_seconds;
ALTER TABLE tasks RENAME CONSTRAINT chk_earnables_importance TO chk_tasks_importance;
ALTER TABLE tasks RENAME CONSTRAINT chk_earnables_min_daily_frequency TO chk_tasks_min_daily_frequency;
ALTER TABLE tasks RENAME CONSTRAINT chk_earnables_lockout_duration_seconds TO chk_tasks_lockout_duration_seconds;
ALTER TABLE tasks RENAME CONSTRAINT chk_earnables_timer_mode TO chk_tasks_timer_mode;
ALTER TABLE tasks RENAME CONSTRAINT chk_earnables_timer_shape TO chk_tasks_timer_shape;
ALTER TABLE tasks RENAME CONSTRAINT chk_earnables_permanent_adjustment_multiplier TO chk_tasks_permanent_adjustment_multiplier;

ALTER INDEX idx_earnables_user_updated RENAME TO idx_tasks_user_updated;

ALTER TRIGGER update_earnables_updated_at ON tasks RENAME TO update_tasks_updated_at;

ALTER TABLE tasks
ADD CONSTRAINT chk_tasks_one_off_shape CHECK (
    recurring OR (min_daily_frequency IS NULL AND lockout_duration_seconds IS NULL)
);

ALTER TABLE tasks
ADD CONSTRAINT chk_tasks_recurring_shape CHECK (
    NOT recurring OR due_date IS NULL
);

CREATE INDEX idx_tasks_user_recurring_created
ON tasks (user_id, recurring, created_at, id);

CREATE INDEX idx_tasks_user_recurring_updated
ON tasks (user_id, recurring, updated_at);
