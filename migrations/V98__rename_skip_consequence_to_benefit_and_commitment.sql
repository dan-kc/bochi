ALTER TABLE habits
    RENAME COLUMN skip_consequence TO benefit;

ALTER TABLE habits
    RENAME CONSTRAINT chk_habits_skip_consequence TO chk_habits_benefit;

ALTER TABLE tasks
    RENAME COLUMN skip_consequence TO commitment;

ALTER TABLE tasks
    RENAME CONSTRAINT chk_tasks_skip_consequence TO chk_tasks_commitment;
