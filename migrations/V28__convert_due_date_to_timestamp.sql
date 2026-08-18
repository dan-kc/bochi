ALTER TABLE tasks ADD COLUMN due_at_temp TIMESTAMP;
UPDATE tasks SET due_at_temp = due_date AT TIME ZONE 'UTC';
ALTER TABLE tasks DROP COLUMN due_date;
ALTER TABLE tasks RENAME COLUMN due_at_temp TO due_at;
