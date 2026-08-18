-- Tasks
-- created_at
ALTER TABLE tasks ADD COLUMN created_at_temp TIMESTAMP;
UPDATE tasks SET created_at_temp = created_at AT TIME ZONE 'UTC';
ALTER TABLE tasks DROP COLUMN created_at;
ALTER TABLE tasks RENAME COLUMN created_at_temp TO created_at;
-- delted_at
ALTER TABLE tasks ADD COLUMN deleted_at_temp TIMESTAMP;
UPDATE tasks SET deleted_at_temp = deleted_at AT TIME ZONE 'UTC';
ALTER TABLE tasks DROP COLUMN deleted_at;
ALTER TABLE tasks RENAME COLUMN deleted_at_temp TO deleted_at;
-- completed_at
ALTER TABLE tasks ADD COLUMN completed_at_temp TIMESTAMP;
UPDATE tasks SET completed_at_temp = completed_at AT TIME ZONE 'UTC';
ALTER TABLE tasks DROP COLUMN completed_at;
ALTER TABLE tasks RENAME COLUMN completed_at_temp TO completed_at;

-- Tags
-- created_at
ALTER TABLE tags DROP COLUMN created_at;
