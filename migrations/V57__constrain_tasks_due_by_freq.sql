ALTER TABLE tasks
ADD CONSTRAINT CHK_AtMostOneNotNull
CHECK (
    (due_by IS NOT NULL AND daily_frequency IS NULL) OR
    (due_by IS NULL AND daily_frequency IS NOT NULL) OR
    (due_by IS NULL AND daily_frequency IS NULL)
);
