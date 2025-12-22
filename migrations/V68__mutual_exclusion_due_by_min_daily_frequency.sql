-- Add constraint to ensure tasks cannot have both due_by and min_daily_frequency
ALTER TABLE tasks ADD CONSTRAINT check_due_by_or_min_daily_frequency
    CHECK (NOT (due_by IS NOT NULL AND min_daily_frequency IS NOT NULL));
