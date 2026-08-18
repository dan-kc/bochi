ALTER TABLE tasks
DROP COLUMN strict_due_date,
DROP COLUMN hidden,
ADD COLUMN hidden_until TIMESTAMP;
