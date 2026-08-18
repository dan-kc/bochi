ALTER TABLE tasks ADD COLUMN base_price INTEGER;
ALTER TABLE rewards ADD COLUMN base_price INTEGER;

UPDATE tasks
SET base_price = ROUND(
    CASE
        WHEN recurring THEN 100.0
        ELSE 200.0
    END
    * CASE difficulty_tier
        WHEN 'trivial' THEN 0.2
        WHEN 'light' THEN 0.6
        WHEN 'medium' THEN 1.0
        WHEN 'hard' THEN 1.4
        WHEN 'extreme' THEN 2.0
        ELSE 0.2
    END
    * COALESCE(1.0 + (19.0 * duration_seconds::double precision / 43200.0), 1.0)
    * CASE importance
        WHEN 1 THEN 1.0
        WHEN 2 THEN 1.3
        WHEN 3 THEN 1.6
        WHEN 4 THEN 2.0
        WHEN 5 THEN 2.5
        ELSE 1.0
    END
)::INTEGER;

UPDATE rewards
SET base_price = ROUND(
    100.0
    * users.general_difficulty
    * CASE rewards.damage_tier
        WHEN 'harmless' THEN 0.2
        WHEN 'light' THEN 0.6
        WHEN 'medium' THEN 1.0
        WHEN 'heavy' THEN 1.4
        WHEN 'extreme' THEN 2.0
        ELSE 2.0
    END
)::INTEGER
FROM users
WHERE rewards.user_id = users.id;

ALTER TABLE tasks
    ALTER COLUMN base_price SET NOT NULL,
    ADD CONSTRAINT chk_tasks_base_price CHECK (base_price >= 0);

ALTER TABLE rewards
    ALTER COLUMN base_price SET NOT NULL,
    ADD CONSTRAINT chk_rewards_base_price CHECK (base_price >= 0);

DROP TABLE special_offers;

ALTER TABLE tasks
    DROP CONSTRAINT chk_tasks_duration_seconds,
    DROP CONSTRAINT chk_tasks_importance,
    DROP CONSTRAINT chk_tasks_permanent_adjustment_multiplier,
    DROP COLUMN difficulty_tier,
    DROP COLUMN duration_seconds,
    DROP COLUMN importance,
    DROP COLUMN permanent_adjustment_multiplier;

ALTER TABLE rewards
    DROP CONSTRAINT chk_rewards_permanent_adjustment_multiplier,
    DROP COLUMN damage_tier,
    DROP COLUMN permanent_adjustment_multiplier;

ALTER TABLE trades
    DROP CONSTRAINT chk_trades_permanent_adjustment_multiplier,
    DROP COLUMN permanent_adjustment_multiplier;

ALTER TABLE users
    DROP CONSTRAINT chk_users_general_difficulty,
    DROP COLUMN general_difficulty;

DROP TYPE habit_difficulty_tier;
DROP TYPE reward_damage_tier;
