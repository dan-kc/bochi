ALTER TABLE habits
    DROP CONSTRAINT IF EXISTS chk_habits_lockout_duration_seconds;

ALTER TABLE habits
    ADD CONSTRAINT chk_habits_lockout_duration_seconds
        CHECK (
            lockout_duration_seconds IS NULL
            OR (lockout_duration_seconds >= 60 AND lockout_duration_seconds <= 2592000)
        );
