CREATE TYPE habit_difficulty_tier AS ENUM (
    'trivial',
    'light',
    'medium',
    'hard',
    'extreme'
);

CREATE TYPE reward_damage_tier AS ENUM (
    'harmless',
    'light',
    'medium',
    'heavy',
    'extreme'
);

DROP INDEX IF EXISTS idx_habits_difficulty_rank;

ALTER TABLE habits
    RENAME COLUMN difficulty_rank TO difficulty_tier;

ALTER TABLE rewards
    RENAME COLUMN damage_rank TO damage_tier;

UPDATE habits
SET difficulty_tier = 'medium'
WHERE difficulty_tier IS NOT NULL;

UPDATE rewards
SET damage_tier = 'medium'
WHERE damage_tier IS NOT NULL;

ALTER TABLE habits
    ALTER COLUMN difficulty_tier TYPE habit_difficulty_tier
    USING difficulty_tier::habit_difficulty_tier;

ALTER TABLE rewards
    ALTER COLUMN damage_tier TYPE reward_damage_tier
    USING damage_tier::reward_damage_tier;
