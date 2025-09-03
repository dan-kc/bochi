-- Add a temporary column to hold converted timestamps
ALTER TABLE users ADD COLUMN created_at_temp TIMESTAMP;

-- Copy data from the old column to the temporary column, converting to local time (London)
UPDATE users SET created_at_temp = created_at AT TIME ZONE 'UTC';

-- Drop the old column
ALTER TABLE users DROP COLUMN created_at;

-- Rename the temporary column to the original column name
ALTER TABLE users RENAME COLUMN created_at_temp TO created_at;
