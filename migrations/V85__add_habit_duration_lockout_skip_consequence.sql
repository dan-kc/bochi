ALTER TABLE habits
    ADD COLUMN duration_seconds INTEGER,
    ADD COLUMN lockout_duration_seconds INTEGER,
    ADD COLUMN skip_consequence SMALLINT;

ALTER TABLE habits
    ADD CONSTRAINT chk_habits_duration_seconds
        CHECK (
            duration_seconds IS NULL
            OR (duration_seconds >= 1 AND duration_seconds <= 43200)
        ),
    ADD CONSTRAINT chk_habits_lockout_duration_seconds
        CHECK (
            lockout_duration_seconds IS NULL
            OR (lockout_duration_seconds >= 1 AND lockout_duration_seconds <= 43200)
        ),
    ADD CONSTRAINT chk_habits_skip_consequence
        CHECK (
            skip_consequence IS NULL
            OR (skip_consequence >= 1 AND skip_consequence <= 5)
        );
