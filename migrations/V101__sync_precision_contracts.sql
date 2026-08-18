ALTER TABLE rewards
    ADD COLUMN lockout_duration_seconds INTEGER;

ALTER TABLE rewards
    ADD CONSTRAINT chk_rewards_lockout_duration_seconds
    CHECK (
        lockout_duration_seconds IS NULL
        OR (lockout_duration_seconds >= 60 AND lockout_duration_seconds <= 2592000)
    );

ALTER TABLE habits
    ADD CONSTRAINT chk_habits_min_daily_frequency
    CHECK (
        min_daily_frequency IS NULL
        OR (min_daily_frequency >= (1.0 / 30.0) AND min_daily_frequency <= 100.0)
    );

ALTER TABLE rewards
    ADD CONSTRAINT chk_rewards_max_daily_frequency
    CHECK (
        max_daily_frequency IS NULL
        OR (max_daily_frequency >= (1.0 / 30.0) AND max_daily_frequency <= 100.0)
    );

ALTER TABLE users
    ADD CONSTRAINT chk_users_general_difficulty
    CHECK (general_difficulty > 0.0 AND general_difficulty < 1000.0);
