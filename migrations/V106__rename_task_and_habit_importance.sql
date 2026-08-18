ALTER TABLE tasks
    RENAME COLUMN commitment TO importance;

ALTER TABLE tasks
    RENAME CONSTRAINT chk_tasks_commitment TO chk_tasks_importance;

ALTER TABLE habits
    RENAME COLUMN benefit TO importance;

ALTER TABLE habits
    RENAME CONSTRAINT chk_habits_benefit TO chk_habits_importance;
