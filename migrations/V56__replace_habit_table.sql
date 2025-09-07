ALTER TABLE trades
DROP COLUMN habit_id;

DROP TABLE habits;

ALTER TABLE tasks
ADD COLUMN daily_frequency INT;

ALTER TABLE tasks
ADD CONSTRAINT CHK_daily_frequency CHECK (daily_frequency >= 0 AND daily_frequency <= 1000);
