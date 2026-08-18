ALTER TABLE tasks
DROP COLUMN duration;

ALTER TABLE tasks
DROP COLUMN importance;

ALTER TABLE tasks
RENAME COLUMN difficulty TO difficulty_rank;
